#!/bin/bash
set -uo pipefail

# Run every tests/test_*.sh and tests/test_*.py, and report which failed.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# test_agent_tmux.sh and test_tmux_osc52.py source the real tmux/tmux.conf into a
# throwaway server, which arms resurrect and continuum inside it. resurrect reads
# its directory from the environment — "${XDG_DATA_HOME:-$HOME/.local/share}"/tmux
# /resurrect — so aiming that somewhere disposable before any server starts keeps
# a one-pane scratch frame out of the developer's own save file, and keeps a
# scratch server from restoring their real session into itself.
XDG_DATA_HOME="$(mktemp -d)"
export XDG_DATA_HOME
trap 'rm -rf -- "$XDG_DATA_HOME"' EXIT

TIMEOUT_SECONDS=180
failed=()

run_with_timeout() {
    python3 -c '
import subprocess, sys
timeout = int(sys.argv[1])
try:
    sys.exit(subprocess.run(sys.argv[2:], stdin=subprocess.DEVNULL, timeout=timeout).returncode)
except subprocess.TimeoutExpired:
    sys.exit(124)
' "$TIMEOUT_SECONDS" "$@"
}

for test in "$ROOT"/tests/test_*.sh "$ROOT"/tests/test_*.py; do
    name="$(basename "$test")"
    echo "== $name =="

    case "$test" in
        *.py) runner=python3 ;;
        *) runner=bash ;;
    esac

    run_with_timeout "$runner" "$test"
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
