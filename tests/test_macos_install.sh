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
case "$1" in
    list) exit 1 ;;
    --repository) echo "$BREW_REPO" ;;
    outdated) cat "$BREW_OUTDATED" ;;
    upgrade) : > "$BREW_OUTDATED" ;;
esac
exit 0
EOF

# The host's own package managers must not answer for the scratch Mac. claude,
# off PATH where its own script installs it, stands in for an installed
# cross-platform component.
mkdir -p "$tmp/home/.local/bin"
for manager in "$tmp/bin/npm" "$tmp/bin/pnpm" "$tmp/bin/pipx" "$tmp/home/.local/bin/claude"; do
    cat > "$manager" <<'EOF'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "$MANAGER_LOG"
EOF
    chmod +x "$manager"
done

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

# defaults can reach the real preference service even with a scratch HOME, so
# its values live in files the test owns.
cat > "$tmp/bin/defaults" <<'EOF'
#!/bin/bash
store="$DEFAULTS_STORE/$2.$3"
case "$1" in
    read) cat "$store" 2>/dev/null ;;
    write) printf '%s\n' "${!#}" > "$store" ;;
esac
EOF

chmod +x "$tmp/bin/uname" "$tmp/bin/brew" "$tmp/bin/tmux" "$tmp/bin/aerospace" "$tmp/bin/defaults"
# A plain run upgrades every component whose command it finds, so the host's
# own tools (~/.cargo/bin, /usr/local/bin, Homebrew) stay off PATH.
export PATH="$tmp/bin:/usr/bin:/bin"
export HOME="$tmp/home"
export BREW_LOG="$tmp/brew.log"
export BREW_REPO="$tmp/brew-repo"
export BREW_OUTDATED="$tmp/brew-outdated"
export MANAGER_LOG="$tmp/managers.log"
mkdir -p "$BREW_REPO/.git"
: > "$BREW_OUTDATED"
export DEFAULTS_STORE="$tmp/defaults"
mkdir -p "$DEFAULTS_STORE"
# Isolate from a checkout-local mapping; this test covers the generic config path.
export AEROSPACE_WORKSPACES="$tmp/absent-app-workspaces.cfg"

# A fresh state dir per run, so config_log reads only that run's step log.
installer() {
    rm -rf "$tmp/state"
    XDG_STATE_HOME="$tmp/state" bash "$ROOT/installers/installer.sh" "$@"
}
config_log() { cat "$tmp"/state/linux-utils/install/*/config.log; }

echo "local config" > "$tmp/home/.aerospace.toml"

output="$(installer workstation)"
backup="$(find "$tmp/home" -name '.aerospace.toml.bak.*' -type f)"

assert_contains "installs formula" "$(< "$BREW_LOG")" "install git"
assert_contains "installs cask" "$(< "$BREW_LOG")" "install --cask scroll-reverser"
assert_contains "a stale Homebrew index is refreshed" "$(< "$BREW_LOG")" "update"
assert_contains "a plain run checks global npm packages" "$(< "$MANAGER_LOG")" "npm outdated -g"
assert_contains "a plain run checks global pnpm packages" "$(< "$MANAGER_LOG")" "pnpm outdated -g"
assert_contains "a plain run checks pipx apps" "$(< "$MANAGER_LOG")" "pipx list --short"
assert_contains "a plain run upgrades an installed agent CLI" "$(< "$MANAGER_LOG")" "claude update"
assert_eq "backs up existing config" "$(< "$backup")" "local config"
assert_contains "reports backed-up AeroSpace" "$(config_log)" "backed up existing config: $backup"
assert_eq "writes a real AeroSpace config" "$(test -L "$tmp/home/.aerospace.toml" && echo link || echo file)" "file"
assert_contains "writes tracked AeroSpace settings" "$(< "$tmp/home/.aerospace.toml")" "start-at-login = true"
assert_not_contains "does not load a missing app map" "$(< "$tmp/home/.aerospace.toml")" "on-window-detected"
assert_eq \
    "links Claude skill" \
    "$(readlink "$tmp/home/.claude/skills/pr")" \
    "$ROOT/skills/pr"
assert_eq \
    "links agent instructions for Claude" \
    "$(readlink "$tmp/home/.claude/CLAUDE.md")" \
    "$ROOT/agents/instructions.md"
assert_eq \
    "links agent instructions for Codex" \
    "$(readlink "$tmp/home/.codex/AGENTS.md")" \
    "$ROOT/agents/instructions.md"
assert_eq \
    "links Antigravity skill" \
    "$(readlink "$tmp/home/.gemini/config/skills/pr")" \
    "$ROOT/skills/pr"
assert_contains \
    "injects Antigravity CLI settings" \
    "$(< "$tmp/home/.gemini/antigravity-cli/settings.json")" \
    '"toolPermission": "always-proceed"'
assert_contains \
    "injects Antigravity agent-tmux hooks" \
    "$(< "$tmp/home/.gemini/config/hooks.json")" \
    '"agent-tmux"'
assert_eq \
    "links shared agent skill" \
    "$(readlink "$tmp/home/.agents/skills/land")" \
    "$ROOT/skills/land"
assert_eq \
    "links agent-tmux" \
    "$(readlink "$tmp/home/.agents/scripts/agent-tmux")" \
    "$ROOT/scripts/agent-tmux"
assert_contains \
    "injects Warp OSC 52 clipboard access" \
    "$(< "$tmp/home/.warp/settings.toml")" \
    'osc52_clipboard_access = "read_write"'
assert_contains \
    "disables Warp CLI agent toolbar git polling" \
    "$(< "$tmp/home/.warp/settings.toml")" \
    'should_render_cli_agent_toolbar = false'
assert_contains \
    "injects SSH AddKeysToAgent" \
    "$(< "$tmp/home/.ssh/config")" \
    "AddKeysToAgent yes"

touch "$BREW_REPO/.git/FETCH_HEAD"
printf 'tmux (3.4) < 3.5a\n' > "$BREW_OUTDATED"
: > "$BREW_LOG"
installer workstation >/dev/null
assert_contains "keeps current AeroSpace config" "$(config_log)" "already current: $tmp/home/.aerospace.toml"
assert_not_contains "a Homebrew index fetched within the hour is not refreshed" \
    "$(< "$BREW_LOG")" "update"
assert_contains "an outdated formula is upgraded" "$(< "$BREW_LOG")" "upgrade"
assert_contains "the Homebrew upgrade names old -> new" \
    "$(cat "$tmp"/state/linux-utils/install/*/packages.log)" "Updated: tmux 3.4 -> 3.5a"
: > "$BREW_OUTDATED"

: > "$BREW_LOG"
output="$(installer config)"
assert_eq "config skips Homebrew" "$(< "$BREW_LOG")" ""
assert_contains "config keeps AeroSpace config" "$(config_log)" "already current: $tmp/home/.aerospace.toml"
assert_contains "config keeps skill link" "$(config_log)" "already linked: $tmp/home/.claude/skills/pr"
assert_contains "a converged config sync reads as one current step" "$output" "Tracked config"
assert_contains "a converged config sync is already current" "$output" "already current"

: > "$BREW_LOG"
# Off PATH, in the one directory OpenCode's script installs to.
mkdir -p "$tmp/home/.opencode/bin"
printf '#!/bin/bash\n' > "$tmp/home/.opencode/bin/opencode"
chmod +x "$tmp/home/.opencode/bin/opencode"
# cargo is installed when rustup is, not when a cargo binary is.
mkdir -p "$tmp/home/.cargo/bin"
printf '#!/bin/bash\n' > "$tmp/home/.cargo/bin/rustup"
chmod +x "$tmp/home/.cargo/bin/rustup"
plan="$(installer plan workstation)"
assert_eq "plan does not install" "$(< "$BREW_LOG")" ""
assert_contains "plan names Homebrew" "$plan" "Homebrew packages"
assert_contains "plan names the global package upgrades" "$plan" "npm global packages"
assert_contains "plan names an installed component" "$plan" "Claude Code"
assert_not_contains "plan leaves out a component that is not installed" "$plan" "Grok Build"
assert_contains "plan finds OpenCode in its own directory" "$plan" "OpenCode"
assert_contains "plan finds cargo by its rustup" "$plan" "Rust and Cargo packages"
assert_contains "plan names agent config" "$plan" "Agent config"

plan_config="$(installer plan config)"
assert_not_contains "config plan omits Homebrew" "$plan_config" "Homebrew packages"
assert_not_contains "config plan omits package upgrades" "$plan_config" "npm global packages"
assert_contains "config plan names agent config" "$plan_config" "Agent config"

nobrew="$tmp/nobrew"
mkdir -p "$nobrew/bin" "$nobrew/home"
cp "$tmp/bin/uname" "$tmp/bin/tmux" "$tmp/bin/defaults" "$tmp/bin/npm" "$tmp/bin/pnpm" \
    "$tmp/bin/pipx" "$nobrew/bin/"
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
# plan, so a regression prints Docker's step instead of running it.
assert_eq "a Linux-only component fails" \
    "$(installer plan docker >/dev/null 2>&1; echo $?)" "1"

targets="$(installer list)"
assert_contains "list names macOS install" "$targets" "install"
assert_contains "list names macOS config" "$targets" "config"
assert_contains "list names cross-platform agy component" "$targets" "agy"
assert_contains "list names cross-platform lazyvim component" "$targets" "lazyvim"
assert_not_contains "list leaves out Linux-only components" "$targets" "Docker Engine"

plan_agy="$(installer plan agy)"
assert_contains "component plan names Antigravity CLI" "$plan_agy" "Antigravity CLI"
assert_not_contains "component plan omits Homebrew" "$plan_agy" "Homebrew packages"

plan_lazyvim="$(installer plan lazyvim)"
assert_contains "component plan names Neovim and LazyVim" "$plan_lazyvim" "Neovim and LazyVim"

assert_contains     "injects shared permissions into Claude settings"     "$(< "$tmp/home/.claude/settings.json")"     '"Bash(git status *)"'
assert_contains     "gives OpenCode deny rules in its own format"     "$(< "$tmp/home/.config/opencode/opencode.jsonc")"     '"resource": "rm *"'
assert_not_contains "keeps Claude rule syntax out of OpenCode config"     "$(< "$tmp/home/.config/opencode/opencode.jsonc")"     'Bash('

# With an app map the generator reports "loaded N mapping(s)", not "wrote".
printf 'com.apple.Terminal = 3\n' > "$tmp/app-workspaces.cfg"
sync_aerospace() {
    : > "$tmp/aerospace.status"
    AEROSPACE_WORKSPACES="$tmp/app-workspaces.cfg" INSTALLER_STATUS_FILE="$tmp/aerospace.status" \
        bash "$ROOT/installers/config/aerospace.sh" >/dev/null
}
sync_aerospace
assert_contains "a mapped AeroSpace rewrite is reported" "$(< "$tmp/aerospace.status")" \
    "$(printf 'updated\t%s' "$tmp/home/.aerospace.toml")"
sync_aerospace
assert_eq "a current mapped AeroSpace config reports nothing" "$(< "$tmp/aerospace.status")" ""

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
skip="$(PATH="$tmp/linux/bin:$PATH" bash "$ROOT/installers/config/warp.sh")"
assert_contains "Warp config is a no-op on Linux" "$skip" "skipping Warp config"

test_result
