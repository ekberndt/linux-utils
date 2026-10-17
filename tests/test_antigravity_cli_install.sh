#!/bin/bash
set -uo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/linux-home" "$tmp/mac-home"

cat > "$tmp/bin/uname" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == -s ]]; then
    echo "${FAKE_OS:-Linux}"
    exit 0
fi
exec /usr/bin/uname "$@"
EOF

cat > "$tmp/bin/curl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$CURL_LOG"
cat <<'INSTALLER'
#!/bin/bash
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/agy" <<'BINARY'
#!/bin/bash
[[ "${1:-}" == --version ]] && echo 'agy 9.8.7'
BINARY
chmod +x "$HOME/.local/bin/agy"
INSTALLER
EOF

cat > "$tmp/bin/brew" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$BREW_LOG"
case "${1:-}" in
    --version) echo 'Homebrew fixture' ;;
    list) exit 1 ;;
    install) exit 0 ;;
esac
EOF
chmod +x "$tmp/bin/uname" "$tmp/bin/curl" "$tmp/bin/brew"

run_installer() {
    env -i \
        HOME="$1" \
        PATH="$tmp/bin:/usr/bin:/bin" \
        FAKE_OS="${2:-Linux}" \
        CURL_LOG="$tmp/curl.log" \
        BREW_LOG="$tmp/brew.log" \
        bash "$ROOT/installers/antigravity-cli/install.sh"
}

output="$(run_installer "$tmp/linux-home")"
assert_contains "uses Google's CLI installer" "$(< "$tmp/curl.log")" \
    "https://antigravity.google/cli/install.sh"
assert_contains "reports the installed CLI" "$output" "Successfully installed: agy"
assert_eq "installs the agy command" \
    "$("$tmp/linux-home/.local/bin/agy" --version)" "agy 9.8.7"
assert_eq "does not install the desktop App" \
    "$(test -e "$tmp/linux-home/.local/opt/antigravity" && echo yes || echo no)" "no"

curl_count="$(wc -l < "$tmp/curl.log" | tr -d ' ')"
repeat="$(run_installer "$tmp/linux-home")"
assert_contains "keeps an existing CLI install" "$repeat" "Already installed: agy"
assert_eq "does not redownload an existing CLI" \
    "$(wc -l < "$tmp/curl.log" | tr -d ' ')" "$curl_count"

: > "$tmp/brew.log"
mac_output="$(run_installer "$tmp/mac-home" Darwin)"
assert_contains "installs the macOS CLI cask" "$(< "$tmp/brew.log")" \
    "install --cask antigravity-cli"
assert_contains "reports the macOS CLI install" "$mac_output" \
    "Successfully installed: Antigravity CLI"

test_result
