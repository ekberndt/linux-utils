#!/bin/bash
set -uo pipefail

# Drive the real script against a throwaway tmux server. Asserting on config
# text would not catch what actually breaks here: a format tmux refuses to
# parse, or a rename aimed at the wrong window.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

if ! command -v tmux >/dev/null 2>&1; then
    echo "skip agent-tmux (tmux not installed)"
    exit 0
fi

socket="linux-utils-agent-test-$$"

# A scratch repo on a known branch rather than this checkout: CI checks out a
# detached HEAD, where the window name is a short SHA and the rule these
# assertions care about — strip the conventional-commit type — never fires.
repo="$(mktemp -d)"
git -C "$repo" init -q -b feat/window-naming-probe
git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m probe

tmux -L "$socket" kill-server 2>/dev/null || true
tmux -L "$socket" new-session -d -s t -c "$repo" -x 80 -y 24
trap 'tmux -L "$socket" kill-server 2>/dev/null || true; rm -rf -- "$repo"' EXIT

if tmux -L "$socket" source-file "$ROOT/tmux/tmux.conf" 2>/dev/null; then
    echo "ok   tmux.conf parses"
else
    echo "FAIL tmux.conf parses" >&2
    failures=$((failures + 1))
fi

# The saver is tmux-save.timer. continuum prepends a client-gated #() to
# status-right when it loads, and tmux.conf's own assignment after the plugin is
# the only thing that strips it back off; reordering those two silently restores
# a saver that never runs on the detached server this frame usually is.
assert_not_contains "status-right carries no continuum save job" \
    "$(tmux -L "$socket" show -gv status-right)" "continuum_save"

# The script talks to whichever server $TMUX names, exactly as it does when an
# agent hook inherits the variable from its pane.
TMUX="$(tmux -L "$socket" display-message -p '#{socket_path}'),$(tmux -L "$socket" display-message -p '#{pid}'),0"
TMUX_PANE="$(tmux -L "$socket" display-message -p -t t:0 '#{pane_id}')"
export TMUX TMUX_PANE

agent_tmux() { bash "$ROOT/scripts/agent-tmux" "$@"; }
win_opt() { tmux -L "$socket" display-message -p -t "${2:-t:0}" "#{$1}"; }
# Formats render a flag option as 0/1; show reports it as on/off.
win_flag() { tmux -L "$socket" show -wqv -t "${2:-t:0}" "$1"; }

agent_tmux state waiting
assert_eq "state sets the window option" "$(win_opt @agent_state)" "waiting"
assert_contains "state renders a glyph" "$(win_opt @agent_status)" "fg=colour214"

# The bar has no room for the repo: several worktrees of one repo read the same
# on every window. The branch, minus a type prefix that says nothing about which
# window this is, is what tells them apart.
assert_eq "the window is named for its branch, type prefix stripped" \
    "$(win_opt window_name)" "window-naming-probe"
assert_eq "the name is pinned" "$(win_flag automatic-rename)" "off"

# Reading a finished agent acknowledges it; a blocked one keeps asking.
window_id="$(win_opt window_id)"
agent_tmux seen "$window_id"
assert_eq "seen leaves a waiting agent alone" "$(win_opt @agent_state)" "waiting"
agent_tmux state "done"
agent_tmux seen "$window_id"
assert_eq "seen clears a finished agent" "$(win_opt @agent_state)" "idle"

# A parked agent goes on generating hook traffic: Stop when each turn ends, the
# idle prompt behind it. Both arrive --soft, and dragging the window out of
# "monitoring" is exactly the bug this state exists to fix.
agent_tmux state monitor
assert_contains "monitor renders its own glyph" "$(win_opt @agent_status)" "fg=colour44"
agent_tmux state "done" --soft
agent_tmux state waiting --soft
assert_eq "soft states yield to monitor" "$(win_opt @agent_state)" "monitor"
# A permission prompt is not ambient; it takes the window whatever it is on.
agent_tmux state waiting
assert_eq "a real prompt outranks monitor" "$(win_opt @agent_state)" "waiting"
agent_tmux state "done" --soft
assert_eq "soft states otherwise apply" "$(win_opt @agent_state)" "done"

agent_tmux state monitor
tmux -L "$socket" new-window -t t: -c "$repo"
tmux -L "$socket" new-window -t t: -c "$repo"
tmux -L "$socket" set -w -t t:2 @agent_state "done"
tmux -L "$socket" select-window -t t:0
agent_tmux jump "$TMUX_PANE"
assert_eq "jump reaches the waiting window" "$(win_opt window_index t:)" "2"
# Window 0 is monitoring — blocked on a machine, not on you — so it is not a
# stop on the walk, leaving window 2 as the only one to come back around to.
agent_tmux jump "$(tmux -L "$socket" display-message -p -t t:2 '#{pane_id}')"
assert_eq "jump skips a monitoring window and wraps" "$(win_opt window_index t:)" "2"

# TMUX_PANE still names window 0, so that is the window clear must reset.
agent_tmux state clear
assert_eq "clear drops the state" "$(win_opt @agent_state)" ""
assert_eq "clear restores renaming" "$(win_flag automatic-rename)" "on"

test_result
