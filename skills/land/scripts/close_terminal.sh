#!/bin/bash
set -euo pipefail

# Close the terminal this agent runs in: its tmux pane or its Herdr terminal,
# whichever sits nearer above it in the process tree. The environment alone
# cannot say which: a Herdr core started from a tmux pane hands that pane's
# TMUX_PANE to every terminal it runs, and tmux started in Herdr does the reverse.

# Agent shells inherit the Herdr core's PATH, which lacks ~/.local/bin, where
# hc links itself.
PATH="$PATH:$HOME/.local/bin"

tmux_pid=""
if [[ -n "${TMUX_PANE:-}" ]]; then
    tmux_pid="$(tmux display-message -p -t "$TMUX_PANE" '#{pane_pid}' 2>/dev/null || true)"
fi
herdr_pid=""
if [[ -n "${HC_TERMINAL_ID:-}" ]]; then
    herdr_pid="$(hc get "$HC_TERMINAL_ID" --json 2>/dev/null |
        python3 -c 'import json, sys; print(json.load(sys.stdin)["pid"] or "")' 2>/dev/null || true)"
fi

close_herdr_terminal() {
    local hc_bin
    hc_bin="$(command -v hc)"
    # With keep on, Herdr would put a shell in the agent's place.
    "$hc_bin" keep "$HC_TERMINAL_ID" --off >/dev/null
    # Only a finished terminal can be removed, and this agent's shells die with
    # it, so a terminal with no parent ends the agent and then removes it.
    # shellcheck disable=SC2016 # Expanded by the helper's sh.
    "$hc_bin" run --bg --no-parent --rm -- sh -c '
        "$1" kill "$2" >/dev/null
        i=0
        while [ "$i" -lt 50 ]; do
            "$1" rm "$2" >/dev/null 2>&1 && exit 0
            sleep 0.2
            i=$((i + 1))
        done
        exit 1' sh "$hc_bin" "$HC_TERMINAL_ID" >/dev/null
}

pid=$$
while [[ -n "$pid" && "$pid" -gt 1 ]]; do
    if [[ "$pid" == "$tmux_pid" ]]; then
        exec tmux kill-pane -t "$TMUX_PANE"
    elif [[ "$pid" == "$herdr_pid" ]]; then
        close_herdr_terminal
        exit 0
    fi
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
done

echo "close_terminal: no tmux pane or Herdr terminal of this agent to close" >&2
exit 1
