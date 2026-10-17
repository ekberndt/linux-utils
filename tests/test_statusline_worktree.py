#!/usr/bin/env python3
"""Tests for scripts/statusline-worktree."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "statusline-worktree"


def run_statusline(payload: dict[str, object], cache_dir: Path) -> str:
    env = os.environ.copy()
    env["XDG_CACHE_HOME"] = str(cache_dir)
    res = subprocess.run(
        ["python3", str(SCRIPT)],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        env=env,
        check=True,
    )
    return res.stdout


class StatuslineWorktreeTests(unittest.TestCase):
    def test_primary_and_linked_worktree_rendering(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp).resolve()
            cache_dir = base / "cache"
            repo = base / "my-repo"
            wt = base / "my-repo-feat-branch"
            subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True)
            subprocess.run(
                ["git", "-C", str(repo), "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init"],
                check=True,
            )
            subprocess.run(
                ["git", "-C", str(repo), "worktree", "add", "-q", "-b", "feat/branch", str(wt), "HEAD"],
                check=True,
            )
            (wt / "dirty.txt").write_text("modified\n")

            transcript = base / "transcript.jsonl"
            transcript.write_text(
                json.dumps(
                    {
                        "message": {
                            "id": "m1",
                            "usage": {
                                "input_tokens": 1200,
                                "cache_read_input_tokens": 300,
                                "output_tokens": 450,
                            },
                        }
                    }
                )
                + "\n"
            )

            primary_out = run_statusline(
                {
                    "model": {"display_name": "Claude Opus"},
                    "effort": {"level": "high"},
                    "fast_mode": True,
                    "session_name": "refactor-session",
                    "transcript_path": str(transcript),
                    "workspace": {"current_dir": str(repo)},
                    "context_window": {
                        "total_input_tokens": 10000,
                        "total_output_tokens": 2500,
                        "context_window_size": 200000,
                    },
                    "rate_limits": {
                        "five_hour": {"used_percentage": 15.2},
                    },
                },
                cache_dir,
            )
            self.assertIn("my-repo", primary_out)
            self.assertIn("main", primary_out)
            self.assertIn("Claude Opus high fast", primary_out)
            self.assertIn("refactor-session", primary_out)
            self.assertIn("12.5K used", primary_out)
            self.assertIn("1.5K in", primary_out)
            self.assertIn("450 out", primary_out)
            self.assertIn("200K window", primary_out)
            self.assertIn("5h 85% left", primary_out)

            wt_out = run_statusline(
                {
                    "model": {"display_name": "Claude Opus"},
                    "workspace": {"current_dir": str(wt)},
                    "rate_limits": {
                        "five_hour": {"used_percentage": 92},
                    },
                },
                cache_dir,
            )
            self.assertIn("my-repo", wt_out)
            self.assertIn("feat/branch", wt_out)
            self.assertIn(str(wt), wt_out)
            self.assertIn("\uf459 1", wt_out)
            self.assertIn("5h 8% left", wt_out)


if __name__ == "__main__":
    unittest.main()
