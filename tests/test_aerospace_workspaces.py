#!/usr/bin/env python3
"""Unit tests for scripts/aerospace-workspaces."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load_script():
    path = ROOT / "scripts" / "aerospace-workspaces"
    loader = importlib.machinery.SourceFileLoader("aerospace_workspaces", str(path))
    spec = importlib.util.spec_from_loader("aerospace_workspaces", loader)
    assert spec is not None
    mod = importlib.util.module_from_spec(spec)
    sys.modules["aerospace_workspaces"] = mod
    loader.exec_module(mod)
    return mod


ws = load_script()


class WorkspacesTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())

    def run_script(self, *argv: str, **env_overrides) -> int:
        env = {"PATH": os.environ.get("PATH", ""), "HOME": str(self.tmp)}
        env.update(env_overrides)
        old_env, old_argv = os.environ.copy(), sys.argv[:]
        try:
            os.environ.clear()
            os.environ.update(env)
            sys.argv = ["aerospace-workspaces", *argv]
            return ws.main()
        finally:
            os.environ.clear()
            os.environ.update(old_env)
            sys.argv = old_argv

    def write(self, name: str, text: str) -> Path:
        path = self.tmp / name
        path.write_text(text)
        return path


class ParseTests(WorkspacesTestCase):
    def test_skips_comments_and_blanks(self) -> None:
        path = self.write("map.cfg", (
            "# header\n"
            "\n"
            "com.apple.Safari = 5\n"
            "com.apple.Terminal = 3  # shell\n"
        ))
        entries = ws.parse_mapping(path.read_text(), path)
        self.assertEqual(
            [(e.app_id, e.workspace, e.comment) for e in entries],
            [
                ("com.apple.Safari", "5", ""),
                ("com.apple.Terminal", "3", "shell"),
            ],
        )

    def test_rejects_duplicate_app_id(self) -> None:
        path = self.write("map.cfg", "com.apple.Safari = 5\ncom.apple.Safari = 4\n")
        with self.assertRaisesRegex(ValueError, "duplicate app-id"):
            ws.parse_mapping(path.read_text(), path)

    def test_rejects_missing_equals(self) -> None:
        path = self.write("map.cfg", "com.apple.Safari 5\n")
        with self.assertRaisesRegex(ValueError, "expected 'app-id = workspace'"):
            ws.parse_mapping(path.read_text(), path)

    def test_rejects_quotes(self) -> None:
        path = self.write("map.cfg", "com.apple.Safari = 5'\n")
        with self.assertRaisesRegex(ValueError, "single quotes"):
            ws.parse_mapping(path.read_text(), path)


class ComposeTests(WorkspacesTestCase):
    def test_appends_generated_blocks(self) -> None:
        source = "start-at-login = true\n"
        entries = [
            ws.Mapping("com.apple.Safari", "5", ""),
            ws.Mapping("com.todesktop.230313mzl4w4u92", "1", "Cursor"),
        ]
        rendered = ws.compose(source, entries)
        self.assertIn("start-at-login = true", rendered)
        self.assertIn("if.app-id = 'com.apple.Safari'", rendered)
        self.assertIn("run = 'move-node-to-workspace 5'", rendered)
        self.assertIn("if.app-id = 'com.todesktop.230313mzl4w4u92'  # Cursor", rendered)
        self.assertIn("run = 'move-node-to-workspace 1'", rendered)
        self.assertTrue(rendered.startswith("start-at-login = true\n\n# --- app-workspaces"))
        self.assertTrue(rendered.endswith(f"{ws.END}\n"))

    def test_empty_mapping_is_source_only(self) -> None:
        self.assertEqual(ws.compose("start-at-login = true\n", []), "start-at-login = true\n")

    def test_example_mapping_parses(self) -> None:
        path = ROOT / "macos" / "app-workspaces.cfg.example"
        entries = ws.parse_mapping(path.read_text(), path)
        self.assertGreaterEqual(len(entries), 1)


class DriverTests(WorkspacesTestCase):
    def test_writes_composed_config(self) -> None:
        source = self.write("source.toml", "start-at-login = true\n")
        mapping = self.write("map.cfg", "com.apple.Safari = 5\n")
        target = self.tmp / "target.toml"

        self.assertEqual(self.run_script(str(source), str(target), str(mapping)), 0)
        rendered = target.read_text()
        self.assertIn("start-at-login = true", rendered)
        self.assertIn("if.app-id = 'com.apple.Safari'", rendered)
        self.assertIn("run = 'move-node-to-workspace 5'", rendered)

    def test_idempotent(self) -> None:
        source = self.write("source.toml", "start-at-login = true\n")
        mapping = self.write("map.cfg", "com.apple.Safari = 5\n")
        target = self.tmp / "target.toml"

        self.assertEqual(self.run_script(str(source), str(target), str(mapping)), 0)
        first = target.read_text()
        backups = list(self.tmp.glob("target.toml.bak.*"))
        self.assertEqual(self.run_script(str(source), str(target), str(mapping)), 0)
        self.assertEqual(target.read_text(), first)
        self.assertEqual(list(self.tmp.glob("target.toml.bak.*")), backups)

    def test_replaces_previous_mappings(self) -> None:
        source = self.write("source.toml", "start-at-login = true\n")
        mapping = self.write("map.cfg", "com.apple.Safari = 5\n")
        target = self.tmp / "target.toml"
        self.assertEqual(self.run_script(str(source), str(target), str(mapping)), 0)

        mapping.write_text("com.apple.Terminal = 3\n")
        self.assertEqual(
            self.run_script(str(source), str(target), str(mapping), TIMESTAMP="stamp"),
            0,
        )
        rendered = target.read_text()
        self.assertIn("if.app-id = 'com.apple.Terminal'", rendered)
        self.assertNotIn("Safari", rendered)
        self.assertEqual((self.tmp / "target.toml.bak.stamp").read_text().count("Safari"), 1)

    def test_no_mapping_copies_source(self) -> None:
        source = self.write("source.toml", "start-at-login = true\n")
        target = self.tmp / "target.toml"

        self.assertEqual(self.run_script(str(source), str(target)), 0)
        self.assertEqual(target.read_text(), "start-at-login = true\n")
        self.assertNotIn("on-window-detected", target.read_text())

    def test_empty_mapping_file_omits_blocks(self) -> None:
        source = self.write("source.toml", "start-at-login = true\n")
        mapping = self.write("map.cfg", "# none yet\n")
        target = self.tmp / "target.toml"

        self.assertEqual(self.run_script(str(source), str(target), str(mapping)), 0)
        self.assertEqual(target.read_text(), "start-at-login = true\n")

    def test_dry_run_writes_nothing(self) -> None:
        source = self.write("source.toml", "start-at-login = true\n")
        mapping = self.write("map.cfg", "com.apple.Safari = 5\n")
        target = self.write("target.toml", "old\n")

        self.assertEqual(
            self.run_script(str(source), str(target), str(mapping), DRY_RUN="true"),
            0,
        )
        self.assertEqual(target.read_text(), "old\n")

    def test_symlinked_target_is_detached(self) -> None:
        source = self.write("source.toml", "start-at-login = true\n")
        mapping = self.write("map.cfg", "com.apple.Safari = 5\n")
        target = self.tmp / "target.toml"
        target.symlink_to(source)

        self.assertEqual(self.run_script(str(source), str(target), str(mapping)), 0)
        self.assertFalse(target.is_symlink())
        self.assertIn("if.app-id = 'com.apple.Safari'", target.read_text())
        self.assertEqual(source.read_text(), "start-at-login = true\n")

    def test_missing_mapping_fails(self) -> None:
        source = self.write("source.toml", "start-at-login = true\n")
        self.assertEqual(
            self.run_script(str(source), str(self.tmp / "target.toml"), str(self.tmp / "absent.cfg")),
            1,
        )

    def test_invalid_mapping_fails_and_does_not_write(self) -> None:
        source = self.write("source.toml", "start-at-login = true\n")
        mapping = self.write("map.cfg", "not-a-mapping\n")
        target = self.tmp / "target.toml"

        self.assertEqual(self.run_script(str(source), str(target), str(mapping)), 1)
        self.assertFalse(target.exists())


if __name__ == "__main__":
    unittest.main()
