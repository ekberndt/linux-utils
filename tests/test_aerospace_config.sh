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

cat > "$tmp/bin/aerospace" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$AEROSPACE_LOG"
exit 0
EOF

chmod +x "$tmp/bin/uname" "$tmp/bin/aerospace"
export PATH="$tmp/bin:$PATH"
export HOME="$tmp/home"
export AEROSPACE_LOG="$tmp/aerospace.log"
export TIMESTAMP=stamp

sync_aerospace() {
    bash "$ROOT/installers/config/aerospace.sh"
}

export AEROSPACE_WORKSPACES="$tmp/absent.cfg"
output="$(sync_aerospace)"
assert_contains "warns when mapping is missing" "$output" "no app-workspace mapping"
assert_eq "live config is a regular file" "$(test -L "$tmp/home/.aerospace.toml" && echo link || echo file)" "file"
assert_contains "writes generic AeroSpace config" "$(< "$tmp/home/.aerospace.toml")" "start-at-login = true"
assert_not_contains "omits on-window-detected without a mapping" "$(< "$tmp/home/.aerospace.toml")" "on-window-detected"
assert_eq "does not rewrite the tracked config" \
    "$(grep -c 'on-window-detected' "$ROOT/macos/.aerospace.toml" || true)" "0"
assert_contains "reloads AeroSpace" "$(< "$AEROSPACE_LOG")" "reload-config"

cat > "$tmp/map.cfg" <<'EOF'
com.apple.Safari = 5
com.todesktop.230313mzl4w4u92 = 1  # Cursor
EOF
export AEROSPACE_WORKSPACES="$tmp/map.cfg"
: > "$AEROSPACE_LOG"

output="$(sync_aerospace)"
assert_contains "reports loaded mappings" "$output" "loaded 2 app-workspace mapping(s)"
live="$(< "$tmp/home/.aerospace.toml")"
assert_contains "assigns Safari" "$live" "if.app-id = 'com.apple.Safari'"
assert_contains "moves Safari to workspace 5" "$live" "move-node-to-workspace 5"
assert_contains "keeps inline comments" "$live" "if.app-id = 'com.todesktop.230313mzl4w4u92'  # Cursor"
assert_contains "keeps generic settings" "$live" "start-at-login = true"
assert_eq "tracked config still has no app map" \
    "$(grep -c 'on-window-detected' "$ROOT/macos/.aerospace.toml" || true)" "0"

ln -sf "$ROOT/macos/.aerospace.toml" "$tmp/home/.aerospace.toml"
output="$(sync_aerospace)"
assert_eq "detaches a previous symlink" "$(test -L "$tmp/home/.aerospace.toml" && echo link || echo file)" "file"
assert_contains "symlink detach still loads mappings" "$(< "$tmp/home/.aerospace.toml")" "if.app-id = 'com.apple.Safari'"
assert_eq "symlink detach does not dirty the repo file" \
    "$(grep -c 'on-window-detected' "$ROOT/macos/.aerospace.toml" || true)" "0"

before_dry="$(< "$tmp/home/.aerospace.toml")"
: > "$AEROSPACE_LOG"
output="$(DRY_RUN=true sync_aerospace)"
assert_contains "dry run would reload" "$output" "would reload AeroSpace config"
assert_eq "dry run leaves the live config unchanged" "$(< "$tmp/home/.aerospace.toml")" "$before_dry"
assert_eq "dry run does not reload" "$(< "$AEROSPACE_LOG")" ""

printf 'not-a-mapping\n' > "$tmp/bad.cfg"
export AEROSPACE_WORKSPACES="$tmp/bad.cfg"
status="$(sync_aerospace >/dev/null 2>&1; echo $?)"
assert_eq "invalid mapping fails config sync" "$status" "1"
assert_eq "invalid mapping leaves the live config unchanged" "$(< "$tmp/home/.aerospace.toml")" "$before_dry"

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
