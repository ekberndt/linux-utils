#!/bin/bash
set -uo pipefail

# A converged tmux install rewrites no units, reloads no systemd, and leaves the
# live server alone; a first run writes, reloads, and enables the save timer.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home" "$tmp/plugins/tmux-resurrect/.git" \
    "$tmp/plugins/tmux-continuum/.git"

cat > "$tmp/bin/brew" <<'EOF'
#!/bin/bash
case "$1" in
    list) echo tmux ;;
esac
EOF
cat > "$tmp/bin/tmux" <<'EOF'
#!/bin/bash
echo "tmux $*" >> "$CALLS"
case "$1" in
    -V) echo "tmux 3.5a" ;;
    info) exit 0 ;;
esac
EOF
cat > "$tmp/bin/git" <<'EOF'
#!/bin/bash
case "$3" in
    rev-parse) cat "$GIT_HEAD" ;;
    pull) [[ -n "${PLUGIN_UPDATE:-}" ]] && echo newer > "$GIT_HEAD"; exit 0 ;;
esac
EOF
cat > "$tmp/bin/loginctl" <<'EOF'
#!/bin/bash
echo yes
EOF
cat > "$tmp/bin/systemctl" <<'EOF'
#!/bin/bash
echo "systemctl $*" >> "$CALLS"
case "$2" in
    is-enabled|is-active) [[ -e "$TIMER_ON" ]] ;;
    enable) touch "$TIMER_ON" ;;
esac
EOF
chmod +x "$tmp/bin/"*

run_component() {
    : > "$tmp/calls"
    : > "$tmp/status"
    echo abc > "$tmp/head"
    env -i HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" TMUX_PLUGIN_DIR="$tmp/plugins" \
        CALLS="$tmp/calls" GIT_HEAD="$tmp/head" TIMER_ON="$tmp/timer-on" \
        INSTALLER_STATUS_FILE="$tmp/status" "$@" \
        bash "$ROOT/installers/tmux/install.sh" >/dev/null 2>&1
}

run_component
assert_eq "a first run succeeds" "$?" "0"
assert_contains "a first run writes the boot unit" \
    "$(< "$tmp/home/.config/systemd/user/tmux.service")" "ExecStart=$tmp/bin/tmux new-session -d"
assert_contains "a first run reloads systemd" "$(< "$tmp/calls")" "systemctl --user daemon-reload"
assert_contains "a first run enables the save timer" "$(< "$tmp/calls")" \
    "systemctl --user enable --now tmux-save.timer"
assert_contains "a first run reports the units" "$(< "$tmp/status")" "updated"

run_component
assert_not_contains "a converged run does not reload systemd" "$(< "$tmp/calls")" "daemon-reload"
assert_not_contains "a converged run does not re-enable the timer" "$(< "$tmp/calls")" \
    "enable --now"
assert_not_contains "a converged run leaves the tmux server alone" "$(< "$tmp/calls")" \
    "source-file"
assert_eq "a converged run reports nothing" "$(< "$tmp/status")" ""

sed -i.bak 's/OOMPolicy=continue/OOMPolicy=stop/' "$tmp/home/.config/systemd/user/tmux.service"
run_component
assert_contains "a drifted unit is rewritten" \
    "$(< "$tmp/home/.config/systemd/user/tmux.service")" "OOMPolicy=continue"
assert_contains "a drifted unit reloads systemd" "$(< "$tmp/calls")" "daemon-reload"

unit="$tmp/home/.config/systemd/user/tmux.service"
sed -i.bak 's/OOMPolicy=continue/OOMPolicy=stop/' "$unit"
chmod a-w "$unit"
if [[ -w "$unit" ]]; then
    echo "skip unwritable unit (root writes through the mode bits)"
else
    run_component
    assert_eq "a stale unit that cannot be rewritten fails the step" "$?" "1"
    assert_contains "that failure is reported" "$(< "$tmp/status")" "could not write"
fi
chmod u+w "$unit"

run_component PLUGIN_UPDATE=1
assert_contains "an updated plugin is reported" "$(< "$tmp/status")" \
    "$(printf 'updated\ttmux-resurrect')"
assert_contains "an updated plugin reloads the running server" "$(< "$tmp/calls")" \
    "tmux source-file"

test_result
