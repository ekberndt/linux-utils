#!/bin/bash
set -uo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/home"

cat > "$tmp/env" <<'EOF'
GIT_USER_NAME="Ada Lovelace"
GIT_USER_EMAIL="1+ada@users.noreply.github.com"
EOF

# sync_git [VAR=value]...: run the git config sync against the scratch HOME.
sync_git() {
    env -i HOME="$tmp/home" PATH="$PATH" LINUX_UTILS_ENV="$tmp/env" "$@" \
        bash "$ROOT/installers/config/git.sh"
}

global() {
    env -i HOME="$tmp/home" PATH="$PATH" git config --global --get "$1"
}

dry_run="$(sync_git DRY_RUN=true)"
assert_contains "dry run reports the identity" "$dry_run" "would set git user.name = Ada Lovelace"
assert_eq "dry run leaves ~/.gitconfig alone" "$([[ -e "$tmp/home/.gitconfig" ]] && echo exists)" ""

sync_git >/dev/null
assert_eq "sets global user.name" "$(global user.name)" "Ada Lovelace"
assert_eq "sets global user.email" "$(global user.email)" "1+ada@users.noreply.github.com"

before="$(< "$tmp/home/.gitconfig")"
assert_contains "second sync is a no-op" "$(sync_git)" "git user.email already"
assert_eq "second sync leaves ~/.gitconfig unchanged" "$(< "$tmp/home/.gitconfig")" "$before"

rm "$tmp/home/.gitconfig"
missing="$(sync_git LINUX_UTILS_ENV="$tmp/missing")"
assert_eq "missing .env exits cleanly" "$?" "0"
assert_contains "missing .env says how to fix it" "$missing" "copy .env.example"
assert_eq "missing .env sets nothing" "$([[ -e "$tmp/home/.gitconfig" ]] && echo exists)" ""

test_result
