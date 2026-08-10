#!/usr/bin/env python3
"""Unit tests for the unified config injector."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load_injector():
    path = ROOT / "scripts" / "inject-config"
    loader = importlib.machinery.SourceFileLoader("inject_config", str(path))
    spec = importlib.util.spec_from_loader("inject_config", loader)
    assert spec is not None
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


inject = load_injector()


class InjectorTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())

    def run_inject(self, source: Path, target: Path, **env_overrides) -> int:
        env = {"PATH": os.environ.get("PATH", ""), "HOME": str(self.tmp)}
        env.update(env_overrides)
        old_env, old_argv = os.environ.copy(), sys.argv[:]
        try:
            os.environ.clear()
            os.environ.update(env)
            sys.argv = ["inject-config", str(source), str(target)]
            return inject.main()
        finally:
            os.environ.clear()
            os.environ.update(old_env)
            sys.argv = old_argv

    def write(self, name: str, text: str) -> Path:
        path = self.tmp / name
        path.write_text(text)
        return path


class TomlTests(InjectorTestCase):
    def test_repo_keys_win_and_user_keys_survive(self) -> None:
        source = self.write("source.toml", (
            '[skills]\npaths = ["~/.agents/skills"]\ndisabled = ["pr-babysit"]\n'
        ))
        target = self.write("target.toml", (
            '[cli]\ninstaller = "internal"\n\n'
            '[skills]\npaths = ["~/old"]\ndisabled = ["keep-me-too"]\n'
            'extra = "user-only"\n\n'
            '[ui]\ncompact_mode = true\n\n'
            '[[marketplace.sources]]\nname = "xAI Official"\n'
        ))

        self.assertEqual(self.run_inject(source, target), 0)
        rendered = target.read_text()

        self.assertIn('paths = ["~/.agents/skills"]', rendered)
        self.assertIn('disabled = ["pr-babysit"]', rendered)
        self.assertIn('extra = "user-only"', rendered)
        self.assertIn('installer = "internal"', rendered)
        self.assertIn("compact_mode = true", rendered)
        self.assertIn("[[marketplace.sources]]", rendered)
        self.assertNotIn('paths = ["~/old"]', rendered)
        self.assertNotIn('disabled = ["keep-me-too"]', rendered)

    def test_idempotent(self) -> None:
        source = self.write("source.toml", '[skills]\npaths = ["~/.agents/skills"]\n')
        target = self.write("target.toml", '[cli]\ninstaller = "internal"\n')

        self.assertEqual(self.run_inject(source, target), 0)
        first = target.read_text()
        self.assertEqual(self.run_inject(source, target), 0)
        self.assertEqual(target.read_text(), first)

    def test_agent_rewritten_table_is_idempotent(self) -> None:
        """Grok rewrites config.toml with extra empty keys and no comments."""
        source = self.write("source.toml", (
            '[skills]\npaths = ["~/.agents/skills"]\ndisabled = ["pr-babysit"]\n'
        ))
        target = self.write("target.toml", (
            '[skills]\npaths = ["~/.agents/skills"]\ndisabled = ["pr-babysit"]\n'
            'ignore = []\nserver_skill_dirs = []\nbundled_skill_dirs = []\n\n'
            '[cli]\ninstaller = "internal"\n'
        ))

        self.assertEqual(self.run_inject(source, target), 0)
        first = target.read_text()
        self.assertIn("ignore = []", first)
        self.assertIn('installer = "internal"', first)
        self.assertEqual(self.run_inject(source, target), 0)
        self.assertEqual(target.read_text(), first)

    def test_source_comments_do_not_accumulate(self) -> None:
        source = self.write("source.toml", (
            '# managed header\n\n[skills]\npaths = ["~/.agents/skills"]\n'
        ))
        target = self.write("target.toml", '[cli]\ninstaller = "internal"\n')

        self.assertEqual(self.run_inject(source, target), 0)
        self.assertEqual(self.run_inject(source, target), 0)
        self.assertEqual(target.read_text().count("# managed header"), 1)


class JsonTests(InjectorTestCase):
    def test_repo_keys_win_and_user_keys_survive(self) -> None:
        source = self.write("source.json", json.dumps({"model": "opus", "shared": 1}))
        target = self.write("target.json", json.dumps({"shared": 2, "mine": True}))

        self.assertEqual(self.run_inject(source, target), 0)
        merged = json.loads(target.read_text())

        self.assertEqual(merged, {"model": "opus", "shared": 1, "mine": True})

    def test_reordered_keys_are_not_a_change(self) -> None:
        """Claude rewrites settings.json reordered; that must not cause churn."""
        source = self.write("source.json", json.dumps({"a": 1, "b": 2}))
        target = self.write("target.json", json.dumps({"b": 2, "a": 1}, indent=2) + "\n")
        before = target.read_text()

        self.assertEqual(self.run_inject(source, target), 0)
        self.assertEqual(target.read_text(), before)
        self.assertEqual(len(list(self.tmp.glob("target.json.bak.*"))), 0)

    def test_unparseable_target_is_not_overwritten(self) -> None:
        source = self.write("source.json", json.dumps({"a": 1}))
        target = self.write("target.json", "{not json")

        self.assertEqual(self.run_inject(source, target), 1)
        self.assertEqual(target.read_text(), "{not json")


class DriverTests(InjectorTestCase):
    def test_dry_run_writes_nothing(self) -> None:
        source = self.write("source.toml", '[skills]\npaths = ["~/.agents/skills"]\n')
        target = self.write("target.toml", '[cli]\ninstaller = "internal"\n')
        original = target.read_text()

        self.assertEqual(self.run_inject(source, target, DRY_RUN="true"), 0)
        self.assertEqual(target.read_text(), original)

    def test_target_is_backed_up_before_a_change(self) -> None:
        source = self.write("source.toml", '[skills]\npaths = ["new"]\n')
        target = self.write("target.toml", '[skills]\npaths = ["old"]\n')

        self.assertEqual(self.run_inject(source, target, TIMESTAMP="stamp"), 0)
        backup = self.tmp / "target.toml.bak.stamp"
        self.assertTrue(backup.exists())
        self.assertIn('paths = ["old"]', backup.read_text())

    def test_a_symlinked_target_is_detached(self) -> None:
        """Config synced by an older symlink must become a real file."""
        source = self.write("source.toml", '[skills]\npaths = ["new"]\n')
        target = self.tmp / "target.toml"
        target.symlink_to(source)

        self.assertEqual(self.run_inject(source, target), 0)
        self.assertFalse(target.is_symlink())
        self.assertIn('paths = ["new"]', target.read_text())
        self.assertIn('paths = ["new"]', source.read_text())

    def test_missing_source_fails(self) -> None:
        self.assertEqual(
            self.run_inject(self.tmp / "absent.toml", self.tmp / "target.toml"), 1
        )

    def test_unknown_format_fails(self) -> None:
        source = self.write("source.yaml", "a: 1\n")
        self.assertEqual(self.run_inject(source, self.tmp / "target.yaml"), 1)


if __name__ == "__main__":
    unittest.main()
