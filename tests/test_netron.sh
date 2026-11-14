#!/bin/bash
set -uo pipefail

# Netron is one uv tool on every arch. A first run installs it and reports it;
# a re-run reads uv's receipt, installs nothing, and reports nothing.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/stray"

cat > "$tmp/bin/uname" <<'UNAME'
#!/bin/bash
if [[ "${1:-}" == -m ]]; then
    echo "$FAKE_ARCH"
    exit 0
fi
exec /usr/bin/uname "$@"
UNAME

# Keeps receipts the way uv does: `tool install` records one under $HOME and
# `tool list` reads it back, reporting an empty list on stderr.
cat > "$tmp/uv" <<'UV'
#!/bin/bash
printf '%s\n' "$*" >> "$UV_LOG"
receipt="$HOME/.local/share/uv/tools/netron"
case "$1 $2" in
    "tool list")
        if [[ -d "$receipt" ]]; then
            printf 'netron v9.3.6\n- netron\n'
        else
            echo "No tools installed" >&2
        fi
        ;;
    "tool install")
        mkdir -p "$receipt"
        printf '#!/bin/bash\necho 9.3.6\n' > "$HOME/.local/bin/$3"
        chmod +x "$HOME/.local/bin/$3"
        ;;
esac
UV

# A netron that uv did not install, like the retired snap's /snap/bin/netron.
printf '#!/bin/bash\necho 8.8.0\n' > "$tmp/stray/netron"
chmod +x "$tmp/bin/uname" "$tmp/uv" "$tmp/stray/netron"

# A fresh HOME whose uv sits in ~/.local/bin, where uv's installer puts it and
# where the installer's PATH does not look.
new_home() {
    mkdir -p "$tmp/$1/.local/bin"
    cp "$tmp/uv" "$tmp/$1/.local/bin/uv"
}

run_component() {
    local home="$1" arch="$2" path="$3"
    : > "$tmp/$home.status"
    env -i \
        HOME="$tmp/$home" \
        PATH="$path" \
        FAKE_ARCH="$arch" \
        UV_LOG="$tmp/$home.log" \
        INSTALLER_STATUS_FILE="$tmp/$home.status" \
        bash "$ROOT/installers/netron/install.sh"
}

for arch in x86_64 aarch64; do
    new_home "$arch"

    first="$(run_component "$arch" "$arch" "$tmp/bin:/usr/bin:/bin")"
    assert_contains "$arch: installs netron as a uv tool" \
        "$(< "$tmp/$arch.log")" "tool install netron"
    assert_eq "$arch: reports the install" \
        "$(< "$tmp/$arch.status")" "$(printf 'installed\tnetron (v9.3.6)')"
    assert_not_contains "$arch: hides uv's empty tool list" \
        "$first" "No tools installed"

    repeat="$(run_component "$arch" "$arch" "$tmp/bin:/usr/bin:/bin")"
    assert_contains "$arch: re-run names the installed version" \
        "$repeat" "Already installed: netron (v9.3.6)"
    assert_eq "$arch: re-run reports nothing" "$(< "$tmp/$arch.status")" ""
    assert_eq "$arch: re-run only reads the receipt" \
        "$(grep -c '^tool install' "$tmp/$arch.log")" "1"
done

new_home stray
run_component stray aarch64 "$tmp/stray:$tmp/bin:/usr/bin:/bin" >/dev/null
assert_contains "a netron on PATH without a uv receipt is replaced" \
    "$(< "$tmp/stray.status")" "installed"

mkdir -p "$tmp/no-uv"
run_component no-uv aarch64 "$tmp/bin:/usr/bin:/bin" >/dev/null
assert_eq "fails without uv" "$?" "1"
assert_contains "points at the uv component" \
    "$(< "$tmp/no-uv.status")" "run 'installers/installer.sh uv' first"

test_result
