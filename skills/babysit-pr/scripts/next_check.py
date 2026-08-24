#!/usr/bin/env python3
"""Suggest a next PR babysitting poll interval.

Babysitting carries merge authority: the agent approves, enables auto-merge
with squash, and re-enqueues, so a green PR that only needs one of those is
act_now rather than a wait. Agent work (conflicts, red CI, changes requested)
is act_now too. Waits are for checks that are still running, for the queue
holding the PR, and for gates only a human can clear.

Input: JSON from `gh pr view` (extra keys ignored). Useful fields include
state, isDraft, mergeable, mergeStateStatus, reviewDecision, statusCheckRollup,
autoMergeRequest.

Output: JSON `{"seconds": int, "reason": str, "class": str}`.

Classes:
  act_now     — agent should work immediately (0s)
  wait_short  — checks settling, or the queue holds the PR (60–300s)
  wait_long   — only a human can progress it (900–1800s)
  blocked     — terminal state or hard human decision (0s)
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any


FAILURE_VALUES = {"FAILURE", "FAILED", "ERROR"}
INFRA_VALUES = {"TIMED_OUT", "CANCELLED", "CANCELED", "STARTUP_FAILURE", "STALE", "ACTION_REQUIRED"}
PENDING_VALUES = {"PENDING", "QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED"}
# BLOCKED is deliberately not a conflict. GitHub reports a merge conflict as
# DIRTY; BLOCKED means the base branch wants something the PR has not satisfied
# yet — an approval, or a required check that has not passed. Treating it as a
# conflict made every PR whose required checks were still queued report as
# needing work, on a repo where one busy runner can hold checks for an hour.
CONFLICT_VALUES = {"DIRTY"}
BEHIND_VALUES = {"BEHIND"}
# The queue holds the PR here while it tests the merge commit; nothing to do.
QUEUED_VALUES = {"QUEUED"}


def _upper(value: Any) -> str:
    return str(value or "").upper()


def _check_values(check: dict[str, Any]) -> set[str]:
    return {
        _upper(check.get("state")),
        _upper(check.get("status")),
        _upper(check.get("conclusion")),
    } - {""}


def _rollup_sets(pr: dict[str, Any]) -> tuple[set[str], set[str], set[str]]:
    failures: set[str] = set()
    infra: set[str] = set()
    pending: set[str] = set()
    checks = pr.get("statusCheckRollup") or []
    if not isinstance(checks, list):
        return failures, infra, pending
    for check in checks:
        if not isinstance(check, dict):
            continue
        values = _check_values(check)
        if values & FAILURE_VALUES:
            failures |= values & FAILURE_VALUES
        if values & INFRA_VALUES:
            infra |= values & INFRA_VALUES
        if values & PENDING_VALUES:
            pending |= values & PENDING_VALUES
    return failures, infra, pending


def _has_automerge(pr: dict[str, Any]) -> bool:
    return bool(pr.get("autoMergeRequest"))


def suggest(
    pr: dict[str, Any],
    cycle: int,
    *,
    has_unresolved_threads: bool = False,
    agent_can_fix_ci: bool = True,
    approval_blocked: bool = False,
) -> tuple[int, str, str]:
    state = _upper(pr.get("state"))
    if state == "MERGED":
        return 0, "pr is merged", "blocked"
    if state and state not in {"OPEN", ""}:
        return 0, f"pr is {state.lower()}", "blocked"

    merge_state = _upper(pr.get("mergeStateStatus"))
    mergeable = _upper(pr.get("mergeable"))

    if mergeable == "CONFLICTING" or merge_state in CONFLICT_VALUES:
        return 0, f"merge state needs action: {(merge_state or mergeable).lower()}", "act_now"

    if merge_state in BEHIND_VALUES:
        return 0, "branch is behind base; merge base on top", "act_now"

    if pr.get("isDraft"):
        return 0, "draft blocks the queue; mark ready", "act_now"

    failures, infra, pending = _rollup_sets(pr)

    if failures:
        if agent_can_fix_ci:
            return 0, "failing check needs action", "act_now"
        return 0, "failing check needs human/agent attention", "blocked"

    if has_unresolved_threads:
        return 0, "unresolved review threads need action", "act_now"

    review = _upper(pr.get("reviewDecision"))
    if review == "CHANGES_REQUESTED":
        return 0, "review decision needs action: changes_requested", "act_now"

    if mergeable == "UNKNOWN" or merge_state == "UNKNOWN":
        wait = min(60 * (2 ** max(cycle, 0)), 300)
        return wait, "mergeability unknown; brief settle wait", "wait_short"

    if merge_state in QUEUED_VALUES:
        wait = min(60 * (2 ** max(cycle, 0)), 300)
        return wait, "in the merge queue; waiting for it to land", "wait_short"

    # Checks before merge state: a required check that has not passed is the
    # usual reason a PR reads BLOCKED, and there is nothing to approve or
    # enqueue until they finish.
    if pending:
        wait = min(60 * (2 ** max(cycle, 0)), 300)
        return wait, "checks still pending", "wait_short"

    if infra:
        wait = min(120 * (2 ** max(cycle, 0)), 600)
        return wait, "infra check outcome; re-check soon", "wait_short"

    # Green from here, so anything left is a gate babysitting may clear itself.
    if approval_blocked:
        return 1800, "green; approval has to come from another account", "wait_long"

    if review == "REVIEW_REQUIRED":
        return 0, "green; approve it", "act_now"

    if merge_state == "BLOCKED":
        return 0, "green but blocked; approve it or enqueue it", "act_now"

    if _has_automerge(pr):
        wait = min(60 * (2 ** max(cycle, 0)), 180)
        return wait, "green; waiting for the queue to merge it", "wait_short"

    return 0, "green; enable auto-merge with squash", "act_now"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", help="Path to a PR JSON snapshot. Defaults to stdin.")
    parser.add_argument("--cycle", type=int, default=0, help="Consecutive short-wait cycle count.")
    parser.add_argument(
        "--has-unresolved-threads",
        action="store_true",
        help="Set when GraphQL reviewThreads has unresolved items.",
    )
    parser.add_argument(
        "--agent-can-fix-ci",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="If false, failing CI is reported as blocked rather than act_now.",
    )
    parser.add_argument(
        "--approval-blocked",
        action="store_true",
        help="Set when the approval this PR needs cannot come from this account, "
        "e.g. GitHub refused a self-approval and the ruleset requires one.",
    )
    args = parser.parse_args()

    raw = open(args.json, encoding="utf-8").read() if args.json else sys.stdin.read()
    pr = json.loads(raw)
    seconds, reason, klass = suggest(
        pr,
        args.cycle,
        has_unresolved_threads=args.has_unresolved_threads,
        agent_can_fix_ci=args.agent_can_fix_ci,
        approval_blocked=args.approval_blocked,
    )
    print(json.dumps({"seconds": seconds, "reason": reason, "class": klass}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
