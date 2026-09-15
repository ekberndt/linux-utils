#!/bin/bash
set -uo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"

cat > "$tmp/bin/uname" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == -s ]]; then
    echo Darwin
    exit 0
fi
exec /usr/bin/uname "$@"
EOF

cat > "$tmp/bin/brew" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$BREW_LOG"
[[ "$1" == list ]] && exit 1
exit 0
EOF

# A real tmux server must not pick up the scratch HOME's tmux.conf.
cat > "$tmp/bin/tmux" <<'EOF'
#!/bin/bash
exit 1
EOF

# A real AeroSpace must not reload against this scratch HOME.
cat > "$tmp/bin/aerospace" <<'EOF'
#!/bin/bash
exit 0
EOF

chmod +x "$tmp/bin/uname" "$tmp/bin/brew" "$tmp/bin/tmux" "$tmp/bin/aerospace"
export PATH="$tmp/bin:$PATH"
export HOME="$tmp/home"
export BREW_LOG="$tmp/brew.log"
# Isolate from a checkout-local mapping; this test covers the generic config path.
export AEROSPACE_WORKSPACES="$tmp/absent-app-workspaces.cfg"

installer() { bash "$ROOT/installers/installer.sh" "$@"; }

echo "local config" > "$tmp/home/.aerospace.toml"

output="$(installer workstation)"
backup="$(find "$tmp/home" -name '.aerospace.toml.bak.*' -type f)"

assert_contains "installs formula" "$(< "$BREW_LOG")" "install git"
assert_contains "installs cask" "$(< "$BREW_LOG")" "install --cask scroll-reverser"
assert_eq "backs up existing config" "$(< "$backup")" "local config"
assert_contains "reports backed-up AeroSpace" "$output" "backed up existing config: $backup"
assert_eq "writes a real AeroSpace config" "$(test -L "$tmp/home/.aerospace.toml" && echo link || echo file)" "file"
assert_contains "writes tracked AeroSpace settings" "$(< "$tmp/home/.aerospace.toml")" "start-at-login = true"
assert_not_contains "does not load a missing app map" "$(< "$tmp/home/.aerospace.toml")" "on-window-detected"
assert_eq \
    "links Claude skill" \
    "$(readlink "$tmp/home/.claude/skills/pr")" \
    "$ROOT/skills/pr"
assert_eq \
    "links shared agent skill" \
    "$(readlink "$tmp/home/.agents/skills/babysit-pr")" \
    "$ROOT/skills/babysit-pr"
assert_eq \
    "links agent-tmux" \
    "$(readlink "$tmp/home/.agents/scripts/agent-tmux")" \
    "$ROOT/scripts/agent-tmux"

output="$(installer workstation)"
assert_contains "keeps current AeroSpace config" "$output" "already current: $tmp/home/.aerospace.toml"

: > "$BREW_LOG"
output="$(installer config)"
assert_eq "config skips Homebrew" "$(< "$BREW_LOG")" ""
assert_contains "config keeps AeroSpace config" "$output" "already current: $tmp/home/.aerospace.toml"
assert_contains "config keeps skill link" "$output" "already linked: $tmp/home/.claude/skills/pr"

: > "$BREW_LOG"
plan="$(installer plan workstation)"
assert_eq "plan does not install" "$(< "$BREW_LOG")" ""
assert_contains "plan names Homebrew" "$plan" "Homebrew packages"
assert_contains "plan names agent config" "$plan" "Agent config"

plan_config="$(installer plan config)"
assert_not_contains "config plan omits Homebrew" "$plan_config" "Homebrew packages"
assert_contains "config plan names agent config" "$plan_config" "Agent config"

nobrew="$tmp/nobrew"
mkdir -p "$nobrew/bin" "$nobrew/home"
cp "$tmp/bin/uname" "$tmp/bin/tmux" "$nobrew/bin/"
ln -s "$(command -v python3)" "$nobrew/bin/python3"
nobrew_status="$(
    HOME="$nobrew/home" PATH="$nobrew/bin:/usr/bin:/bin" \
        installer workstation >/dev/null 2>&1
    echo $?
)"
assert_eq "missing Homebrew still fails the run" "$nobrew_status" "1"
assert_eq \
    "just install still links agent skills without Homebrew" \
    "$(readlink "$nobrew/home/.claude/skills/pr")" \
    "$ROOT/skills/pr"
assert_eq \
    "just install still links shared skills without Homebrew" \
    "$(readlink "$nobrew/home/.agents/skills/pr")" \
    "$ROOT/skills/pr"

assert_eq "an unknown Linux target fails" \
    "$(installer datacenter >/dev/null 2>&1; echo $?)" "1"

targets="$(installer list)"
assert_contains "list names macOS install" "$targets" "install"
assert_contains "list names macOS config" "$targets" "config"

mkdir -p "$tmp/linux/bin"
cat > "$tmp/linux/bin/uname" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == -s ]]; then
    echo Linux
    exit 0
fi
exec /usr/bin/uname "$@"
EOF
chmod +x "$tmp/linux/bin/uname"
skip="$(PATH="$tmp/linux/bin:$PATH" bash "$ROOT/installers/config/aerospace.sh")"
assert_contains "AeroSpace is a no-op on Linux" "$skip" "skipping AeroSpace config"

test_result
