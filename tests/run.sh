#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../installers/lib/package_list.sh
source "$ROOT/installers/lib/package_list.sh"
# shellcheck source=../installers/lib/stream_filter.sh
source "$ROOT/installers/lib/stream_filter.sh"

failures=0
assert_eq() {
    local name="$1" got="$2" want="$3"
    if [[ "$got" != "$want" ]]; then
        echo "FAIL $name: got=$got want=$want" >&2
        failures=$((failures + 1))
    else
        echo "ok   $name"
    fi
}

assert_parse() {
    local name="$1" line="$2" want_pkg="$3" want_opt="$4" want_ppa="$5"
    package=""; optional=false; ppa=""
    if ! parse_package_line "$line"; then
        assert_eq "$name skip" "skipped" "parsed"
        return
    fi
    assert_eq "$name package" "$package" "$want_pkg"
    assert_eq "$name optional" "$optional" "$want_opt"
    assert_eq "$name ppa" "$ppa" "$want_ppa"
}

assert_classify() {
    local name="$1" line="$2" want="$3"
    local got=0
    # classify uses exit statuses 0/1/2; do not trip set -e
    classify_output_line "$line" || got=$?
    assert_eq "$name" "$got" "$want"
}

assert_contains() {
    local name="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "ok   $name"
    else
        echo "FAIL $name: missing '$needle'" >&2
        failures=$((failures + 1))
    fi
}

assert_not_contains() {
    local name="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "FAIL $name: found '$needle'" >&2
        failures=$((failures + 1))
    else
        echo "ok   $name"
    fi
}

echo "== parse_package_line =="
assert_parse "simple" "git # version control" "git" "false" ""
assert_parse "optional" "? sway # tiling" "sway" "true" ""
assert_parse "ppa" "foo | ppa:user/repo # desc" "foo" "false" "user/repo"
package=""; optional=false; ppa=""
if parse_package_line "# comment only"; then
    assert_eq "comment" "parsed" "skipped"
else
    assert_eq "comment" "skipped" "skipped"
fi
package=""; optional=false; ppa=""
if parse_package_line ""; then
    assert_eq "blank" "parsed" "skipped"
else
    assert_eq "blank" "skipped" "skipped"
fi

echo "== classify_output_line =="
rule="$(printf '%*s' 80 '' | tr ' ' '-')"
assert_classify "dash-rule" "$rule" "0"
assert_classify "homepage" "Homepage: https://neovim.io" "0"
assert_classify "reading" "Reading package lists..." "0"
assert_classify "percent" "Downloading... 50%" "2"
assert_classify "success" "✓ Already installed: git" "1"
assert_classify "failed" "✗ Failed to install: just" "1"
assert_classify "unable" "E: Unable to locate package just" "1"
assert_classify "installing" "Installing: mosh" "1"

echo "== inject-grok/codex toml =="
if python3 "$ROOT/tests/test_inject_toml_config.py"; then
    echo "ok   inject toml config"
else
    echo "FAIL inject toml config" >&2
    failures=$((failures + 1))
fi

echo "== zoxide shell init =="
if bash "$ROOT/tests/test_zoxide_init.sh"; then
    echo "ok   zoxide shell init"
else
    echo "FAIL zoxide shell init" >&2
    failures=$((failures + 1))
fi

echo "== ducky encode =="
if python3 "$ROOT/tests/test_ducky_encode.py"; then
    echo "ok   ducky encode"
else
    echo "FAIL ducky encode" >&2
    failures=$((failures + 1))
fi

echo "== babysit-pr next_check =="
if python3 "$ROOT/tests/test_next_check.py"; then
    echo "ok   next_check"
else
    echo "FAIL next_check" >&2
    failures=$((failures + 1))
fi

echo "== tmux clipboard config =="
tmux_conf="$(< "$ROOT/tmux/tmux.conf")"
assert_contains "tmux enables clipboard forwarding" "$tmux_conf" "set -s set-clipboard on"
assert_contains "tmux clears copy-command" "$tmux_conf" "set -su copy-command"
assert_contains "tmux defines osc52 copy command" "$tmux_conf" "set -g @osc52-copy-command"
assert_contains "tmux y mirrors osc52" "$tmux_conf" 'bind -T copy-mode-vi y send -X copy-selection-and-cancel \; run-shell -b "#{E:@osc52-copy-command}"'
assert_contains "tmux enter mirrors osc52" "$tmux_conf" 'bind -T copy-mode-vi Enter send -X copy-selection-and-cancel \; run-shell -b "#{E:@osc52-copy-command}"'
assert_contains "tmux mouse mirrors osc52" "$tmux_conf" 'bind -T copy-mode-vi MouseDragEnd1Pane send -X copy-selection-no-clear \; run-shell -b "#{E:@osc52-copy-command}"'
assert_contains "tmux mosh clipboard selector" "$tmux_conf" '*:Ms=\E]52;c;%p2%s\007'
assert_not_contains "tmux avoids recursive copy pipe" "$tmux_conf" "tmux load-buffer -w -"
assert_contains "tmux guards the agent hook" "$tmux_conf" \
    "test ! -x ~/.agents/scripts/agent-tmux ||"
assert_not_contains "tmux does not force terminal features" "$tmux_conf" \
    'terminal-features ",*:usstyle"'

echo "== LazyVim runtime =="
lazyvim_installer="$(< "$ROOT/installers/lazyvim/install.sh")"
assert_contains "LazyVim installs stable Neovim and Treesitter" "$lazyvim_installer" \
    $'LAZYVIM_FORMULAE=(\n    neovim\n    tree-sitter\n)'
assert_not_contains "LazyVim avoids Neovim development PPA" "$lazyvim_installer" "neovim-ppa/unstable"

echo "== tmux session persistence =="
assert_contains "tmux restores on server start" "$tmux_conf" "set -g @continuum-restore 'on'"
# continuum only arms this itself when it believes no other tmux process
# exists, which is never true on a box where agents spawn tmux sessions.
assert_contains "tmux arms the periodic save" "$tmux_conf" \
    "set -g status-right '#(~/.tmux/plugins/tmux-continuum/scripts/continuum_save.sh)"
# Sourcing unconditionally errors on every reload until the plugins are cloned.
assert_contains "tmux guards resurrect" "$tmux_conf" \
    'if-shell "test -e ~/.tmux/plugins/tmux-resurrect/resurrect.tmux"'
assert_contains "tmux guards continuum" "$tmux_conf" \
    'if-shell "test -e ~/.tmux/plugins/tmux-continuum/continuum.tmux"'
# Unconditionally, the unit's ExecStop would kill every detached session at
# the last logout, because a non-lingering user manager stops with the login.
assert_contains "tmux gates boot support on lingering" "$tmux_conf" \
    '-p Linger --value 2>/dev/null)" = yes'
# A leading newline anchors this to column 0, where an unguarded set would sit;
# the guarded one is indented inside the if-shell.
assert_not_contains "tmux never arms boot unconditionally" "$tmux_conf" \
    $'\nset -g @continuum-boot'
# Both would grow ~/.tmux/resurrect without bound or relaunch paid agents.
assert_not_contains "tmux leaves pane capture off" "$tmux_conf" \
    "set -g @resurrect-capture-pane-contents 'on'"
assert_not_contains "tmux does not respawn agents" "$tmux_conf" "set -g @resurrect-processes"

echo "== agent-tmux state =="
# Drive the real script against a throwaway tmux server. Asserting on config
# text would not catch the failures that actually happen here: a format tmux
# refuses to parse, or a rename/option write aimed at the wrong window.
if ! command -v tmux >/dev/null 2>&1; then
    echo "skip agent-tmux (tmux not installed)"
else
    socket="linux-utils-agent-test-$$"
    tmux -L "$socket" kill-server 2>/dev/null || true
    tmux -L "$socket" new-session -d -s t -c "$ROOT" -x 80 -y 24
    trap 'tmux -L "$socket" kill-server 2>/dev/null || true' EXIT

    if tmux -L "$socket" source-file "$ROOT/tmux/tmux.conf" 2>/dev/null; then
        echo "ok   tmux.conf parses"
    else
        echo "FAIL tmux.conf parses" >&2
        failures=$((failures + 1))
    fi

    # The script talks to whichever server $TMUX names, exactly as it does when
    # an agent hook inherits the variable from its pane.
    test_socket_path="$(tmux -L "$socket" display-message -p '#{socket_path}')"
    test_server_pid="$(tmux -L "$socket" display-message -p '#{pid}')"
    TMUX="$test_socket_path,$test_server_pid,0"
    TMUX_PANE="$(tmux -L "$socket" display-message -p -t t:0 '#{pane_id}')"
    export TMUX TMUX_PANE
    agent_tmux() { bash "$ROOT/scripts/agent-tmux" "$@"; }
    win_opt() { tmux -L "$socket" display-message -p -t "${2:-t:0}" "#{$1}"; }
    # Formats render a flag option as 0/1; show reports it as on/off.
    win_flag() { tmux -L "$socket" show -wqv -t "${2:-t:0}" "$1"; }

    agent_tmux state waiting
    assert_eq "agent-tmux sets state" "$(win_opt @agent_state)" "waiting"
    assert_contains "agent-tmux renders glyph" "$(win_opt @agent_status)" "fg=colour214"
    # The bar has no room for the repo: several worktrees of one repo read the
    # same on every window. The branch, minus a type prefix that says nothing
    # about which window this is, is what distinguishes them.
    test_branch="$(git -C "$ROOT" branch --show-current 2>/dev/null)"
    test_branch="${test_branch#*/}"
    if (( ${#test_branch} > 20 )); then
        test_branch="${test_branch:0:19}…"
    fi
    assert_eq "agent-tmux names window by branch" \
        "$(win_opt window_name)" "$test_branch"
    assert_not_contains "agent-tmux omits the repo" "$(win_opt window_name)" "linux-utils"
    assert_eq "agent-tmux pins the name" "$(win_flag automatic-rename)" "off"

    # Reading a finished agent acknowledges it; a blocked one keeps asking.
    window_id="$(win_opt window_id)"
    agent_tmux seen "$window_id"
    assert_eq "seen keeps waiting" "$(win_opt @agent_state)" "waiting"
    agent_tmux state "done"
    agent_tmux seen "$window_id"
    assert_eq "seen clears done" "$(win_opt @agent_state)" "idle"

    # A parked agent goes on generating hook traffic: Stop when each turn ends,
    # the idle prompt a minute behind it. Both arrive --soft, and dragging the
    # window out of "monitoring" is exactly the bug this state exists to fix.
    agent_tmux state monitor
    assert_contains "monitor renders its own glyph" "$(win_opt @agent_status)" "fg=colour44"
    agent_tmux state "done" --soft
    agent_tmux state waiting --soft
    assert_eq "soft states yield to monitor" "$(win_opt @agent_state)" "monitor"
    # A permission prompt is not ambient; it takes the window whatever it is on.
    agent_tmux state waiting
    assert_eq "a real prompt outranks monitor" "$(win_opt @agent_state)" "waiting"
    # ...and it is only monitor that soft states yield to.
    agent_tmux state "done" --soft
    assert_eq "soft states otherwise apply" "$(win_opt @agent_state)" "done"
    agent_tmux state monitor

    tmux -L "$socket" new-window -t t: -c "$ROOT"
    tmux -L "$socket" new-window -t t: -c "$ROOT"
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
    assert_eq "clear drops state" "$(win_opt @agent_state)" ""
    assert_eq "clear restores renaming" "$(win_flag automatic-rename)" "on"

    unset TMUX TMUX_PANE
    tmux -L "$socket" kill-server 2>/dev/null || true
    trap - EXIT
fi

if (( failures > 0 )); then
    echo "$failures test(s) failed" >&2
    exit 1
fi
echo "All tests passed."
