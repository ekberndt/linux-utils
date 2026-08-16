#!/bin/bash
set -uo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"

cat > "$tmp/bin/uname" <<'EOF'
#!/bin/bash
echo Darwin
EOF

cat > "$tmp/bin/brew" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$BREW_LOG"
[[ "$1" == list ]] && exit 1
exit 0
EOF

chmod +x "$tmp/bin/uname" "$tmp/bin/brew"
export BREW_LOG="$tmp/brew.log"
echo "local config" > "$tmp/home/.aerospace.toml"

output="$(HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" bash "$ROOT/macos/install.sh")"
backup="$(find "$tmp/home" -name '.aerospace.toml.bak.*' -type f)"

assert_contains "installs formula" "$(< "$BREW_LOG")" "install git"
assert_contains "installs cask" "$(< "$BREW_LOG")" "install --cask scroll-reverser"
assert_eq "backs up existing config" "$(< "$backup")" "local config"
assert_contains "reports linked config" "$output" "Linked: $tmp/home/.aerospace.toml"
assert_eq \
    "links tracked AeroSpace config" \
    "$(readlink "$tmp/home/.aerospace.toml")" \
    "$ROOT/macos/.aerospace.toml"

output="$(HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" bash "$ROOT/macos/install.sh")"
assert_contains "keeps current config link" "$output" "Already linked: $tmp/home/.aerospace.toml"

test_result
