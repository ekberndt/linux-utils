#!/bin/bash
set -uo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"

cat > "$tmp/bin/curl" <<'CURL'
#!/bin/bash
printf '%s\n' "$*" >> "$CURL_LOG"
cat <<'INSTALL'
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/agy" <<'BIN'
#!/bin/bash
echo "agy 1.4.0"
BIN
chmod +x "$HOME/.local/bin/agy"
INSTALL
CURL
chmod +x "$tmp/bin/curl"

run_installer() {
    env -i \
        HOME="$tmp/home" \
        PATH="$tmp/bin:/usr/bin:/bin" \
        CURL_LOG="$tmp/curl.log" \
        bash "$ROOT/installers/agy/install.sh"
}

output="$(run_installer)"
assert_contains "downloads the official Antigravity CLI installer" \
    "$(< "$tmp/curl.log")" "https://antigravity.google/cli/install.sh"
assert_contains "reports installed Antigravity CLI version" \
    "$output" "Successfully installed: agy (agy 1.4.0)"

curl_count="$(wc -l < "$tmp/curl.log" | tr -d ' ')"
repeat="$(run_installer)"
assert_contains "skips reinstall when agy is present" \
    "$repeat" "Already installed: agy (agy 1.4.0)"
assert_eq "does not re-fetch installer when agy is installed" \
    "$(wc -l < "$tmp/curl.log" | tr -d ' ')" "$curl_count"

# Config sync: preserves machine-local keys and custom hooks while injecting repo defaults.
mkdir -p "$tmp/home/.gemini/antigravity-cli" "$tmp/home/.gemini/config"
cat > "$tmp/home/.gemini/antigravity-cli/settings.json" <<'JSON'
{
  "colorScheme": "tokyo night",
  "editor": "vim"
}
JSON
cat > "$tmp/home/.gemini/config/hooks.json" <<'JSON'
{
  "custom-lint": {
    "PostToolUse": []
  }
}
JSON

DRY_RUN=true HOME="$tmp/home" bash "$ROOT/installers/config/agy.sh" >/dev/null
assert_contains "dry-run leaves existing settings untouched" \
    "$(< "$tmp/home/.gemini/antigravity-cli/settings.json")" '"editor": "vim"'
assert_eq "dry-run does not create skill links" \
    "$(test -e "$tmp/home/.gemini/config/skills/pr" && echo exists || echo missing)" \
    "missing"

HOME="$tmp/home" bash "$ROOT/installers/config/agy.sh" >/dev/null
settings="$(< "$tmp/home/.gemini/antigravity-cli/settings.json")"
hooks="$(< "$tmp/home/.gemini/config/hooks.json")"

assert_contains "preserves user-only settings keys" \
    "$settings" '"colorScheme": "tokyo night"'
assert_contains "overrides tracked settings keys" \
    "$settings" '"editor": "nvim"'
assert_contains "injects statusLine command" \
    "$settings" '"command": "~/.agents/scripts/statusline-worktree"'
assert_contains "preserves user-defined hooks" \
    "$hooks" '"custom-lint"'
assert_contains "injects agent-tmux hook" \
    "$hooks" '"agent-tmux"'
assert_contains "maps ask_question to waiting state" \
    "$hooks" '"matcher": "ask_question"'
assert_eq "links global Antigravity skills" \
    "$(readlink "$tmp/home/.gemini/config/skills/pr")" "$ROOT/skills/pr"
assert_eq "links shared agent skills" \
    "$(readlink "$tmp/home/.agents/skills/pr")" "$ROOT/skills/pr"

test_result
