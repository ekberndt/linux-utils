#!/bin/bash

# OpenRGB installer (AppImage)
# Distro packages (e.g. Ubuntu PPA 0.81) miss NVIDIA Founders Edition illumination.
# Pins OpenRGB 1.0rc3 x86_64 AppImage by SHA-256 under /usr/local.
# https://openrgb.org/  https://codeberg.org/OpenRGB/OpenRGB

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

OPENRGB_VERSION="1.0rc3"
OPENRGB_APPIMAGE_URL="https://codeberg.org/OpenRGB/OpenRGB/releases/download/release_candidate_1.0rc3/OpenRGB_1.0rc3_x86_64_6fbcf62.AppImage"
OPENRGB_APPIMAGE_SHA256="37f25ecb9c0f52cd3b916d760c1df61a8b372c8b124115555200fe6dfe56f2a0"

SYS_LIB="/usr/local/lib/linux-utils/openrgb"
SYS_APPIMAGE="${SYS_LIB}/OpenRGB.AppImage"
SYS_BIN="/usr/local/bin/openrgb"

sha256_file() {
    local f="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$f" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$f" | awk '{print $1}'
    else
        print_error "need sha256sum or shasum to verify OpenRGB AppImage"
        return 1
    fi
}

openrgb_is_ours() {
    [[ -x "$SYS_BIN" && -x "$SYS_APPIMAGE" ]] || return 1
    # Wrapper must point at our AppImage path.
    grep -qF "$SYS_APPIMAGE" "$SYS_BIN" 2>/dev/null || return 1
    local got
    got="$(sha256_file "$SYS_APPIMAGE")" || return 1
    [[ "$got" == "$OPENRGB_APPIMAGE_SHA256" ]]
}

if [[ "$(uname -m)" != "x86_64" ]]; then
    print_error "OpenRGB AppImage pin is x86_64 only (this host: $(uname -m))"
    exit 1
fi

if openrgb_is_ours; then
    ver="$("$SYS_BIN" --version 2>/dev/null | head -1 || true)"
    print_success "Already installed: openrgb (${ver:-$OPENRGB_VERSION AppImage, checksum OK})"
    exit 0
fi

if [[ "$(id -u)" -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
    print_error "need root or sudo to install OpenRGB under /usr/local"
    exit 1
fi

run_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

tmp_img="${tmpdir}/OpenRGB.AppImage"
echo "Downloading OpenRGB ${OPENRGB_VERSION} AppImage..."
if ! curl -fsSL -o "$tmp_img" "$OPENRGB_APPIMAGE_URL"; then
    print_error "Failed to download OpenRGB AppImage"
    exit 1
fi

echo "Verifying SHA-256..."
got="$(sha256_file "$tmp_img")"
if [[ "$got" != "$OPENRGB_APPIMAGE_SHA256" ]]; then
    print_error "SHA-256 mismatch (got $got, want $OPENRGB_APPIMAGE_SHA256)"
    exit 1
fi

echo "Installing to ${SYS_BIN}..."
run_root install -d -m 755 "$SYS_LIB"
run_root install -m 755 "$tmp_img" "$SYS_APPIMAGE"
# Re-check after copy
got="$(sha256_file "$SYS_APPIMAGE")"
if [[ "$got" != "$OPENRGB_APPIMAGE_SHA256" ]]; then
    run_root rm -f "$SYS_APPIMAGE"
    print_error "SHA-256 mismatch after install"
    exit 1
fi

wrapper="${tmpdir}/openrgb"
cat >"$wrapper" <<EOF
#!/usr/bin/env bash
# linux-utils OpenRGB ${OPENRGB_VERSION} AppImage wrapper
exec ${SYS_APPIMAGE} --appimage-extract-and-run "\$@"
EOF
run_root install -m 755 "$wrapper" "$SYS_BIN"
run_root chown root:root "$SYS_BIN" "$SYS_APPIMAGE"

if ! is_installed "openrgb"; then
    print_error "openrgb not on PATH after install (is /usr/local/bin in PATH?)"
    exit 1
fi

# Prefer /usr/local/bin over distro /usr/bin/openrgb (0.81).
if command -v openrgb >/dev/null 2>&1; then
    resolved="$(command -v openrgb)"
    if [[ "$resolved" != "$SYS_BIN" ]]; then
        print_warning "PATH resolves openrgb to $resolved (expected $SYS_BIN); check PATH order"
    fi
fi

ver="$("$SYS_BIN" --version 2>/dev/null | head -1 || true)"
print_success "Successfully installed: openrgb (${ver:-$OPENRGB_VERSION AppImage})"
