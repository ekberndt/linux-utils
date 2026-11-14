#!/bin/bash
set -uo pipefail

# The Linux installer end to end, over a copy of installers/ whose components
# are stubs: the run reads as a status list, a failed step fails the run, and
# nothing reaches apt unless a component asks.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"
cp -R "$ROOT/installers" "$tmp/installers"

cat > "$tmp/bin/uname" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == -s ]]; then
    echo Linux
    exit 0
fi
exec /usr/bin/uname "$@"
EOF
cat > "$tmp/bin/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$SUDO_LOG"
EOF
chmod +x "$tmp/bin/uname" "$tmp/bin/sudo"
export PATH="$tmp/bin:$PATH"
export SUDO_LOG="$tmp/sudo.log"

stub_component() {
    local name="$1" body="$2"
    cat > "$tmp/installers/$name/install.sh" <<EOF
#!/bin/bash
source "\$(dirname "\${BASH_SOURCE[0]}")/../lib/common.sh"
$body
EOF
}
stub_component apt 'echo "Already installed: 30 of 30 apt packages"'
stub_component gh 'echo "Installing GitHub CLI..."; print_installed "gh (gh version 2.62.0)"'
stub_component tmux 'print_warning "could not update tmux-resurrect (local changes?)"'
stub_component config 'echo "inject-config: bad TOML in ~/.codex/config.toml" >&2; exit 1'

installer() {
    XDG_STATE_HOME="$tmp/state" bash "$tmp/installers/installer.sh" "$@"
}

: > "$SUDO_LOG"
plan="$(installer plan apt gh tmux config)"
assert_contains "plan lists the steps" "$plan" "Tracked config"
assert_eq "plan creates no logs" "$(test -e "$tmp/state" && echo created || echo none)" "none"
assert_eq "plan asks for no sudo" "$(< "$SUDO_LOG")" ""

output="$(installer apt gh tmux config)"
status=$?
run_dir="$(echo "$tmp"/state/linux-utils/install/*/)"

assert_eq "a failed component fails the run" "$status" "1"
assert_contains "the run names its log directory" "$output" "logs: ${run_dir%/}"
assert_contains "a converged component reads as already current" \
    "$(grep -F "APT packages" <<<"$output")" "already current"
assert_contains "an installing component names what it installed" \
    "$(grep -F "GitHub CLI" <<<"$output")" "installed"
assert_contains "the installed version is shown" \
    "$(grep -F "GitHub CLI" <<<"$output")" "gh version 2.62.0"
assert_contains "a component warning surfaces" "$output" "⚠ could not update tmux-resurrect"
assert_contains "the failed component is marked" \
    "$(grep -F "Tracked config" <<<"$output")" "failed"
assert_contains "the failure shows its stderr" "$output" "bad TOML in ~/.codex/config.toml"
assert_contains "the failure names its log" "$output" "full log: ${run_dir}config.log"
assert_not_contains "component chatter stays in the log" "$output" "Installing GitHub CLI"
assert_contains "component chatter is in the log" "$(< "${run_dir}gh.log")" \
    "Installing GitHub CLI"
assert_contains "the summary counts the failure" "$output" "1 failed"
assert_not_contains "the runner itself never refreshes apt" "$(< "$SUDO_LOG")" "apt-get"

stub_component config 'echo synced'
: > "$SUDO_LOG"
rm -rf "$tmp/state"
output="$(installer apt config)"
assert_eq "a clean run succeeds" "$?" "0"
assert_contains "a clean run completes" "$output" "Installation complete"
assert_contains "the runner authenticates sudo once up front" "$(< "$SUDO_LOG")" "-v"

test_result
