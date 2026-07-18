#!/usr/bin/env python3
"""Unit tests for skills/babysit-pr/scripts/next_check.py."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load_next_check():
    path = ROOT / "skills" / "babysit-pr" / "scripts" / "next_check.py"
    loader = importlib.machinery.SourceFileLoader("next_check", str(path))
    mod = importlib.util.module_from_spec(importlib.util.spec_from_loader("next_check", loader))
    loader.exec_module(mod)
    return mod


class NextCheckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.nc = load_next_check()

    def test_review_required_is_wait_long(self) -> None:
        seconds, reason, klass = self.nc.suggest(
            {
                "state": "OPEN",
                "isDraft": False,
                "mergeable": "MERGEABLE",
                "mergeStateStatus": "CLEAN",
                "reviewDecision": "REVIEW_REQUIRED",
                "statusCheckRollup": [{"conclusion": "SUCCESS", "status": "COMPLETED"}],
            },
            0,
        )
        self.assertEqual(klass, "wait_long")
        self.assertEqual(seconds, 1800)
        self.assertIn("review", reason)

    def test_conflicts_act_now(self) -> None:
        seconds, _, klass = self.nc.suggest(
            {"state": "OPEN", "mergeable": "CONFLICTING", "mergeStateStatus": "DIRTY"},
            0,
        )
        self.assertEqual((seconds, klass), (0, "act_now"))

    def test_unknown_mergeable_wait_short(self) -> None:
        seconds, _, klass = self.nc.suggest(
            {"state": "OPEN", "mergeable": "UNKNOWN", "mergeStateStatus": "UNKNOWN"},
            2,
        )
        self.assertEqual(klass, "wait_short")
        self.assertGreater(seconds, 0)


if __name__ == "__main__":
    unittest.main()
