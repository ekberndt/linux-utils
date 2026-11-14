#!/bin/bash
set -euo pipefail

# Close the terminal this agent runs in: its tmux pane or its Herdr terminal,
# whichever sits nearer above it in the process tree. The environment alone
# cannot say which: a Herdr core started from a tmux pane hands that pane's
# TMUX_PANE to every terminal it runs, and tmux started in Herdr does the reverse.
#
# A Codex agent's session is archived too, as /archive would. Codex refuses to
# archive a thread during its own turn, so the helper that ends the agent
# archives it afterwards, from outside the agent's process tree.

# Agent shells inherit the Herdr core's PATH, which lacks ~/.local/bin, where
# hc and codex link themselves.
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

# Shell run by the helper: retry what only works once the agent is gone.
# shellcheck disable=SC2016 # Expanded by the helper's sh.
retry='retry() { i=0; until "$@" >/dev/null 2>&1; do [ "$i" -lt 50 ] || return 1; sleep 0.2; i=$((i + 1)); done; }'
archive=""

close_herdr_terminal() {
    local hc_bin
    hc_bin="$(command -v hc)"
    # With keep on, Herdr would put a shell in the agent's place.
    "$hc_bin" keep "$HC_TERMINAL_ID" --off >/dev/null
    # Only a finished terminal can be removed, and this agent's shells die with
    # it, so a terminal with no parent ends the agent and then removes it.
    # shellcheck disable=SC2016 # Expanded by the helper's sh.
    "$hc_bin" run --bg --no-parent --rm -- sh -c "$retry"'
        "$1" kill "$2" >/dev/null
        retry "$1" rm "$2"
        '"$archive" sh "$hc_bin" "$HC_TERMINAL_ID" >/dev/null
}

pid=$$
while [[ -n "$pid" && "$pid" -gt 1 ]]; do
    # Everything a Codex agent starts inherits CODEX_THREAD_ID, so it names this
    # agent's session only when a codex process sits at or below the terminal.
    if [[ "$(ps -o comm= -p "$pid")" == codex ]]; then
        archive="retry $(printf %q "$(command -v codex)") archive $(printf %q "$CODEX_THREAD_ID")"
    fi
    if [[ "$pid" == "$tmux_pid" ]]; then
        exec tmux run-shell -b "$retry; tmux kill-pane -t $(printf %q "$TMUX_PANE"); $archive"
    elif [[ "$pid" == "$herdr_pid" ]]; then
        close_herdr_terminal
        exit 0
    fi
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
done

echo "close_terminal: no tmux pane or Herdr terminal of this agent to close" >&2
exit 1
