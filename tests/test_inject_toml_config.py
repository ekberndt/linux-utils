#!/usr/bin/env python3
"""Unit tests for Codex/Grok TOML config injectors."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def load_injector(name: str):
    path = ROOT / "scripts" / name
    mod_name = name.replace("-", "_")
    loader = importlib.machinery.SourceFileLoader(mod_name, str(path))
    spec = importlib.util.spec_from_loader(mod_name, loader)
    assert spec is not None
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def run_main(mod, source: Path, target: Path, env: dict) -> int:
    old_env = os.environ.copy()
    old_argv = sys.argv[:]
    try:
        os.environ.clear()
        os.environ.update(env)
        sys.argv = [mod.__name__, str(source), str(target)]
        return mod.main()
    finally:
        os.environ.clear()
        os.environ.update(old_env)
        sys.argv = old_argv


class TomlInjectTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.codex = load_injector("inject-codex-config")
        cls.grok = load_injector("inject-grok-config")

    def test_repo_keys_win_user_keys_preserved(self) -> None:
        source = """
[skills]
paths = ["~/.agents/skills"]
disabled = ["pr-babysit"]
"""
        target = """
[cli]
installer = "internal"

[skills]
paths = ["~/old"]
disabled = ["keep-me-too"]
extra = "user-only"

[ui]
compact_mode = true

[[marketplace.sources]]
name = "xAI Official"
"""
        for mod in (self.codex, self.grok):
            with self.subTest(mod=mod.__name__):
                s_root, s_tables = mod.split_config(source.splitlines())
                root_keys = mod.keys_in_lines(s_root)
                s_table_keys = {
                    name: mod.keys_in_lines(section[1:])
                    for section in s_tables
                    if (name := mod.table_name(section[0]))
                }
                t_root, preserved, t_tables = mod.filter_target(
                    target.splitlines(), root_keys, s_table_keys
                )
                rendered = mod.render(s_root, s_tables, t_root, preserved, t_tables)

                self.assertIn('paths = ["~/.agents/skills"]', rendered)
                self.assertIn('disabled = ["pr-babysit"]', rendered)
                self.assertIn('extra = "user-only"', rendered)
                self.assertIn('installer = "internal"', rendered)
                self.assertIn("compact_mode = true", rendered)
                self.assertIn("[[marketplace.sources]]", rendered)
                self.assertNotIn('paths = ["~/old"]', rendered)
                self.assertNotIn('disabled = ["keep-me-too"]', rendered)

    def test_idempotent_cli(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            source = tmp_path / "source.toml"
            target = tmp_path / "target.toml"
            source.write_text(
                '[skills]\npaths = ["~/.agents/skills"]\ndisabled = ["pr-babysit"]\n'
            )
            target.write_text(
                '[cli]\ninstaller = "internal"\n\n'
                '[skills]\npaths = ["~/old"]\n'
            )

            env = {"PATH": os.environ.get("PATH", ""), "HOME": os.environ.get("HOME", tmp)}
            self.assertEqual(run_main(self.grok, source, target, env), 0)
            first = target.read_text()
            self.assertIn('paths = ["~/.agents/skills"]', first)
            self.assertIn('installer = "internal"', first)

            self.assertEqual(run_main(self.grok, source, target, env), 0)
            self.assertEqual(target.read_text(), first)

    def test_grok_rewrite_style_skills_table_is_idempotent(self) -> None:
        """Grok appends empty skill keys; sync must stabilize after one inject."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            source = tmp_path / "source.toml"
            target = tmp_path / "target.toml"
            source.write_text(
                '[skills]\npaths = ["~/.agents/skills"]\ndisabled = ["pr-babysit"]\n'
            )
            # Shape after Grok rewrites config.toml (no comments, extra empty keys).
            target.write_text(
                '[skills]\n'
                'paths = ["~/.agents/skills"]\n'
                'disabled = ["pr-babysit"]\n'
                "ignore = []\n"
                "server_skill_dirs = []\n"
                "bundled_skill_dirs = []\n"
                "\n"
                '[cli]\ninstaller = "internal"\n'
            )
            env = {"PATH": os.environ.get("PATH", ""), "HOME": os.environ.get("HOME", tmp)}
            self.assertEqual(run_main(self.grok, source, target, env), 0)
            first = target.read_text()
            self.assertIn('paths = ["~/.agents/skills"]', first)
            self.assertIn("ignore = []", first)
            self.assertIn('installer = "internal"', first)
            self.assertEqual(run_main(self.grok, source, target, env), 0)
            self.assertEqual(target.read_text(), first)

    def test_root_comments_do_not_duplicate(self) -> None:
        """Source root comments must appear once even after repeated injects."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            source = tmp_path / "source.toml"
            target = tmp_path / "target.toml"
            source.write_text(
                "# managed header\n\n"
                '[skills]\npaths = ["~/.agents/skills"]\n'
            )
            target.write_text('[cli]\ninstaller = "internal"\n')
            env = {"PATH": os.environ.get("PATH", ""), "HOME": os.environ.get("HOME", tmp)}
            self.assertEqual(run_main(self.grok, source, target, env), 0)
            first = target.read_text()
            self.assertEqual(first.count("# managed header"), 1)
            self.assertEqual(run_main(self.grok, source, target, env), 0)
            self.assertEqual(target.read_text(), first)

    def test_dry_run_does_not_write(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            source = tmp_path / "source.toml"
            target = tmp_path / "target.toml"
            source.write_text('[skills]\npaths = ["~/.agents/skills"]\n')
            original = '[cli]\ninstaller = "internal"\n'
            target.write_text(original)

            env = {
                "PATH": os.environ.get("PATH", ""),
                "HOME": os.environ.get("HOME", tmp),
                "DRY_RUN": "true",
            }
            self.assertEqual(run_main(self.grok, source, target, env), 0)
            self.assertEqual(target.read_text(), original)


if __name__ == "__main__":
    unittest.main()
