#!/bin/bash
set -uo pipefail

# Run every tests/test_*.sh and tests/test_*.py, and report which failed.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Several tests drive a tmux server or an interactive shell. A hung one has to
# name itself and fail rather than stall the run, which on a CI runner means
# burning the job's whole time budget with no output to say where.
TIMEOUT_SECONDS=180
failed=()

for test in "$ROOT"/tests/test_*.sh "$ROOT"/tests/test_*.py; do
    name="$(basename "$test")"
    echo "== $name =="

    case "$test" in
        *.py) runner=python3 ;;
        *) runner=bash ;;
    esac

    # No test reads stdin; closing it keeps one that tries from waiting forever.
    timeout --kill-after=10 "$TIMEOUT_SECONDS" "$runner" "$test" </dev/null
    case $? in
        0) ;;
        124|137)
            echo "TIMEOUT $name after ${TIMEOUT_SECONDS}s" >&2
            failed+=("$name (timeout)")
            ;;
        *) failed+=("$name") ;;
    esac
done

if ((${#failed[@]})); then
    printf '\n%d test file(s) failed: %s\n' "${#failed[@]}" "${failed[*]}" >&2
    exit 1
fi

echo
echo "All tests passed."
