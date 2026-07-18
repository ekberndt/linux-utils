#!/usr/bin/env python3
"""Suggest a next PR babysitting poll interval.

Input: JSON from `gh pr view --json state,isDraft,mergeable,mergeStateStatus,
reviewDecision,statusCheckRollup` (extra keys ignored).

Output: JSON `{"seconds": int, "reason": str, "class": str}`.

Classes:
  act_now     — agent should work immediately (0s)
  wait_short  — checks/mergeability still settling (60–300s backoff)
  wait_long   — green / awaiting human (900–1800s)
  blocked     — terminal non-open state or explicit block signal (0s, reason)
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any


# Hard failures the agent can usually act on (code or clear CI red).
FAILURE_VALUES = {"FAILURE", "FAILED", "ERROR"}
# Infra outcomes: not automatic code-fix loops.
INFRA_VALUES = {"TIMED_OUT", "CANCELLED", "CANCELED", "STARTUP_FAILURE", "STALE", "ACTION_REQUIRED"}
PENDING_VALUES = {"PENDING", "QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED"}
# Merge states that need a rebase/conflict fix (not mere UNKNOWN lag).
CONFLICT_VALUES = {"DIRTY", "BLOCKED"}
BEHIND_VALUES = {"BEHIND"}


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


def suggest(
    pr: dict[str, Any],
    cycle: int,
    *,
    has_unresolved_threads: bool = False,
    agent_can_fix_ci: bool = True,
) -> tuple[int, str, str]:
    state = _upper(pr.get("state"))
    if state and state not in {"OPEN", ""}:
        return 0, f"pr is {state.lower()}", "blocked"

    merge_state = _upper(pr.get("mergeStateStatus"))
    mergeable = _upper(pr.get("mergeable"))

    if mergeable == "CONFLICTING" or merge_state in CONFLICT_VALUES:
        return 0, f"merge state needs action: {(merge_state or mergeable).lower()}", "act_now"

    if merge_state in BEHIND_VALUES:
        return 0, "branch is behind base; rebase", "act_now"

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

    # UNKNOWN mergeability is usually GitHub lag — short wait, not thrash.
    if mergeable == "UNKNOWN" or merge_state == "UNKNOWN":
        wait = min(60 * (2 ** max(cycle, 0)), 300)
        return wait, "mergeability unknown; brief settle wait", "wait_short"

    if pending:
        wait = min(60 * (2 ** max(cycle, 0)), 300)
        return wait, "checks still pending", "wait_short"

    if infra and not failures:
        wait = min(120 * (2 ** max(cycle, 0)), 600)
        return wait, "infra check outcome (cancelled/timeout); human re-run may be needed", "wait_short"

    # Green-ish: human review or idle draft — not agent act-now.
    if review == "REVIEW_REQUIRED":
        return 1800, "green/idle; awaiting human review", "wait_long"

    if pr.get("isDraft"):
        return 900, "draft pr appears idle", "wait_long"

    return 1800, "green/idle; awaiting human activity", "wait_long"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", help="Path to a PR JSON snapshot. Defaults to stdin.")
    parser.add_argument("--cycle", type=int, default=0, help="Consecutive pending/short-wait cycle count.")
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
    args = parser.parse_args()

    raw = open(args.json, encoding="utf-8").read() if args.json else sys.stdin.read()
    pr = json.loads(raw)
    seconds, reason, klass = suggest(
        pr,
        args.cycle,
        has_unresolved_threads=args.has_unresolved_threads,
        agent_can_fix_ci=args.agent_can_fix_ci,
    )
    print(json.dumps({"seconds": seconds, "reason": reason, "class": klass}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
