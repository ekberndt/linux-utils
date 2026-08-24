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

    def test_review_required_is_approved_not_waited_on(self) -> None:
        """Babysitting carries the approval, so this is work rather than a wait."""
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
        self.assertEqual((seconds, klass), (0, "act_now"))
        self.assertIn("approve", reason)

    def test_review_required_waits_long_when_approval_is_not_ours(self) -> None:
        seconds, reason, klass = self.nc.suggest(
            {
                "state": "OPEN",
                "mergeable": "MERGEABLE",
                "mergeStateStatus": "BLOCKED",
                "reviewDecision": "REVIEW_REQUIRED",
                "statusCheckRollup": [{"conclusion": "SUCCESS", "status": "COMPLETED"}],
            },
            0,
            approval_blocked=True,
        )
        self.assertEqual((seconds, klass), (1800, "wait_long"))
        self.assertIn("another account", reason)

    def test_green_and_unqueued_is_enqueued(self) -> None:
        seconds, reason, klass = self.nc.suggest(
            {
                "state": "OPEN",
                "isDraft": False,
                "mergeable": "MERGEABLE",
                "mergeStateStatus": "CLEAN",
                "reviewDecision": "APPROVED",
                "statusCheckRollup": [{"conclusion": "SUCCESS", "status": "COMPLETED"}],
            },
            0,
        )
        self.assertEqual((seconds, klass), (0, "act_now"))
        self.assertIn("auto-merge", reason)

    def test_green_and_queued_waits_short(self) -> None:
        seconds, reason, klass = self.nc.suggest(
            {
                "state": "OPEN",
                "isDraft": False,
                "mergeable": "MERGEABLE",
                "mergeStateStatus": "CLEAN",
                "reviewDecision": "APPROVED",
                "statusCheckRollup": [{"conclusion": "SUCCESS", "status": "COMPLETED"}],
                "autoMergeRequest": {"enabledAt": "2026-01-01T00:00:00Z"},
            },
            0,
        )
        self.assertEqual(klass, "wait_short")
        self.assertGreater(seconds, 0)
        self.assertLessEqual(seconds, 180)
        self.assertIn("queue", reason)

    def test_blocked_on_queued_checks_is_a_wait_not_a_conflict(self) -> None:
        """The regression this cost an hour of babysitting to find.

        One busy self-hosted runner held every required check in `queued`, so
        the PR read BLOCKED. Classing BLOCKED as a conflict reported act_now
        every cycle for work that did not exist.
        """
        seconds, reason, klass = self.nc.suggest(
            {
                "state": "OPEN",
                "isDraft": False,
                "mergeable": "MERGEABLE",
                "mergeStateStatus": "BLOCKED",
                "reviewDecision": "",
                "statusCheckRollup": [{"status": "QUEUED"}, {"status": "QUEUED"}],
            },
            0,
        )
        self.assertEqual(klass, "wait_short")
        self.assertGreater(seconds, 0)
        self.assertIn("pending", reason)

    def test_blocked_while_green_is_work(self) -> None:
        """Nothing left running, so BLOCKED means a gate babysitting may clear."""
        seconds, reason, klass = self.nc.suggest(
            {
                "state": "OPEN",
                "mergeable": "MERGEABLE",
                "mergeStateStatus": "BLOCKED",
                "reviewDecision": "",
                "statusCheckRollup": [{"conclusion": "SUCCESS", "status": "COMPLETED"}],
            },
            0,
        )
        self.assertEqual((seconds, klass), (0, "act_now"))
        self.assertIn("enqueue", reason)

    def test_behind_is_work_without_a_merge_queue(self) -> None:
        seconds, reason, klass = self.nc.suggest(
            {"state": "OPEN", "mergeable": "MERGEABLE", "mergeStateStatus": "BEHIND"},
            0,
        )
        self.assertEqual((seconds, klass), (0, "act_now"))
        self.assertIn("behind", reason)

    def test_behind_is_the_queues_job_when_there_is_one(self) -> None:
        """The queue tests base+PR, so chasing a moving trunk by hand is churn."""
        seconds, reason, klass = self.nc.suggest(
            {
                "state": "OPEN",
                "mergeable": "MERGEABLE",
                "mergeStateStatus": "BEHIND",
                "statusCheckRollup": [{"status": "QUEUED"}],
            },
            0,
            merge_queue=True,
        )
        self.assertEqual(klass, "wait_short")
        self.assertIn("pending", reason)
        self.assertGreater(seconds, 0)

    def test_green_and_behind_with_a_queue_gets_enqueued(self) -> None:
        seconds, reason, klass = self.nc.suggest(
            {
                "state": "OPEN",
                "mergeable": "MERGEABLE",
                "mergeStateStatus": "BEHIND",
                "reviewDecision": "APPROVED",
                "statusCheckRollup": [{"conclusion": "SUCCESS", "status": "COMPLETED"}],
            },
            0,
            merge_queue=True,
        )
        self.assertEqual((seconds, klass), (0, "act_now"))
        self.assertIn("auto-merge", reason)

    def test_sitting_in_the_merge_queue_waits(self) -> None:
        seconds, reason, klass = self.nc.suggest(
            {
                "state": "OPEN",
                "mergeable": "MERGEABLE",
                "mergeStateStatus": "QUEUED",
                "statusCheckRollup": [{"conclusion": "SUCCESS", "status": "COMPLETED"}],
            },
            0,
        )
        self.assertEqual(klass, "wait_short")
        self.assertGreater(seconds, 0)
        self.assertIn("queue", reason)

    def test_red_ci_beats_the_merge_authority(self) -> None:
        """A failing check is never approvable, however green the rest looks."""
        seconds, reason, klass = self.nc.suggest(
            {
                "state": "OPEN",
                "mergeable": "MERGEABLE",
                "mergeStateStatus": "BLOCKED",
                "reviewDecision": "REVIEW_REQUIRED",
                "statusCheckRollup": [{"conclusion": "FAILURE", "status": "COMPLETED"}],
            },
            0,
        )
        self.assertEqual((seconds, klass), (0, "act_now"))
        self.assertIn("failing", reason)

    def test_unresolved_threads_beat_the_merge_authority(self) -> None:
        seconds, reason, klass = self.nc.suggest(
            {
                "state": "OPEN",
                "mergeable": "MERGEABLE",
                "mergeStateStatus": "BLOCKED",
                "statusCheckRollup": [{"conclusion": "SUCCESS", "status": "COMPLETED"}],
            },
            0,
            has_unresolved_threads=True,
        )
        self.assertEqual((seconds, klass), (0, "act_now"))
        self.assertIn("thread", reason)

    def test_draft_act_now(self) -> None:
        seconds, reason, klass = self.nc.suggest(
            {"state": "OPEN", "isDraft": True, "mergeable": "MERGEABLE"},
            0,
        )
        self.assertEqual((seconds, klass), (0, "act_now"))
        self.assertIn("draft", reason)

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

    def test_merged_is_terminal(self) -> None:
        seconds, reason, klass = self.nc.suggest({"state": "MERGED"}, 0)
        self.assertEqual((seconds, klass), (0, "blocked"))
        self.assertIn("merged", reason)


if __name__ == "__main__":
    unittest.main()
