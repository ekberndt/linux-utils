#!/bin/bash
set -uo pipefail

# Run every tests/test_*.sh and tests/test_*.py, and report which failed.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# test_agent_tmux.sh and test_tmux_osc52.py source the real tmux/tmux.conf into a
# throwaway server, which arms resurrect and continuum inside it. resurrect reads
# its directory from the environment — "${XDG_DATA_HOME:-$HOME/.local/share}"/tmux
# /resurrect — so aiming that somewhere disposable before any server starts keeps
# a one-pane scratch frame out of the developer's own save file, and keeps a
# scratch server from restoring their real session into itself. It has to be the
# environment rather than @resurrect-dir on the scratch server: the save runs
# detached, and one that outlives its server reads no tmux options at all — it
# falls back to this default, dumps nothing, and repoints "last" at the empty
# file it just wrote. That is how three 0-byte saves reached the real directory.
XDG_DATA_HOME="$(mktemp -d)"
export XDG_DATA_HOME
trap 'rm -rf -- "$XDG_DATA_HOME"' EXIT
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
