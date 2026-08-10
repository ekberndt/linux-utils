#!/bin/bash
set -uo pipefail

# Run every tests/test_*.sh and tests/test_*.py, and report which failed.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=()

for test in "$ROOT"/tests/test_*.sh "$ROOT"/tests/test_*.py; do
    name="$(basename "$test")"
    echo "== $name =="

    case "$test" in
        *.py) runner=python3 ;;
        *) runner=bash ;;
    esac

    if ! "$runner" "$test"; then
        failed+=("$name")
    fi
done

if ((${#failed[@]})); then
    printf '\n%d test file(s) failed: %s\n' "${#failed[@]}" "${failed[*]}" >&2
    exit 1
fi

echo
echo "All tests passed."
