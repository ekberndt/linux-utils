#!/usr/bin/env python3
"""Suggest a conservative next PR babysitting poll interval.

Input: JSON from `gh pr view --json state,isDraft,mergeStateStatus,reviewDecision,statusCheckRollup`.
Output: JSON with seconds and reason.
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any


FAILURE_VALUES = {"FAILURE", "FAILED", "ERROR", "TIMED_OUT", "ACTION_REQUIRED", "CANCELLED"}
PENDING_VALUES = {"PENDING", "QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED", "STARTUP_FAILURE"}
CONFLICT_VALUES = {"DIRTY", "UNKNOWN", "BLOCKED", "BEHIND"}


def _upper(value: Any) -> str:
    return str(value or "").upper()


def _check_values(check: dict[str, Any]) -> set[str]:
    return {
        _upper(check.get("state")),
        _upper(check.get("status")),
        _upper(check.get("conclusion")),
    } - {""}


def suggest(pr: dict[str, Any], cycle: int) -> tuple[int, str]:
    state = _upper(pr.get("state"))
    if state and state != "OPEN":
        return 0, f"pr is {state.lower()}"

    merge_state = _upper(pr.get("mergeStateStatus"))
    if merge_state in CONFLICT_VALUES:
        return 0, f"merge state needs action: {merge_state.lower()}"

    checks = pr.get("statusCheckRollup") or []
    values = set()
    if isinstance(checks, list):
        for check in checks:
            if isinstance(check, dict):
                values |= _check_values(check)

    if values & FAILURE_VALUES:
        return 0, "failing check needs action"

    if values & PENDING_VALUES:
        wait = min(60 * (2 ** max(cycle, 0)), 300)
        return wait, "checks still pending"

    review = _upper(pr.get("reviewDecision"))
    if review in {"CHANGES_REQUESTED", "REVIEW_REQUIRED"}:
        return 0, f"review decision needs action: {review.lower()}"

    if pr.get("isDraft"):
        return 900, "draft pr appears idle"

    return 1800, "green/idle; awaiting human activity"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", help="Path to a PR JSON snapshot. Defaults to stdin.")
    parser.add_argument("--cycle", type=int, default=0, help="Consecutive pending cycle count.")
    args = parser.parse_args()

    raw = open(args.json, encoding="utf-8").read() if args.json else sys.stdin.read()
    pr = json.loads(raw)
    seconds, reason = suggest(pr, args.cycle)
    print(json.dumps({"seconds": seconds, "reason": reason}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
