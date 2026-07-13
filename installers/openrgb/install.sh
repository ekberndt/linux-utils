#!/bin/bash

# OpenRGB installer (AppImage)
# Distro packages (e.g. Ubuntu PPA 0.81) miss NVIDIA Founders Edition illumination.
# Places the AppImage in ~/Applications (AppImage-native) and installs a thin
# /usr/local/bin/openrgb wrapper that points at that file (absolute path so root
# boot jobs still work). SHA-256 pinned.
# https://openrgb.org/  https://codeberg.org/OpenRGB/OpenRGB

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

OPENRGB_VERSION="1.0rc3"
OPENRGB_APPIMAGE_URL="https://codeberg.org/OpenRGB/OpenRGB/releases/download/release_candidate_1.0rc3/OpenRGB_1.0rc3_x86_64_6fbcf62.AppImage"
OPENRGB_APPIMAGE_SHA256="37f25ecb9c0f52cd3b916d760c1df61a8b372c8b124115555200fe6dfe56f2a0"

SYS_BIN="/usr/local/bin/openrgb"
# Legacy system payload from earlier install layout (removed on upgrade).
LEGACY_SYS_LIB="/usr/local/lib/linux-utils/openrgb"

# Resolve the interactive user when this script is run via sudo/root.
install_user() {
    if [[ -n "${OPENRGB_USER:-}" ]]; then
        echo "$OPENRGB_USER"
        return
    fi
    if [[ "$(id -u)" -eq 0 ]]; then
        if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != root ]]; then
            echo "$SUDO_USER"
            return
        fi
        print_error "running as root without SUDO_USER — set OPENRGB_USER=alice or run via: sudo -u alice …" >&2
        return 1
    fi
    id -un
}
INSTALL_USER="$(install_user)" || exit 1
USER_HOME="$(getent passwd "$INSTALL_USER" | cut -d: -f6)"
APPDIR="${USER_HOME}/Applications"
USER_APPIMAGE="${APPDIR}/OpenRGB.AppImage"

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

run_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# True if wrapper points at our AppImage and checksum matches.
openrgb_is_ours() {
    [[ -x "$SYS_BIN" && -x "$USER_APPIMAGE" ]] || return 1
    grep -qF "$USER_APPIMAGE" "$SYS_BIN" 2>/dev/null || return 1
    local got
    got="$(sha256_file "$USER_APPIMAGE")" || return 1
    [[ "$got" == "$OPENRGB_APPIMAGE_SHA256" ]]
}

if [[ "$(uname -m)" != "x86_64" ]]; then
    print_error "OpenRGB AppImage pin is x86_64 only (this host: $(uname -m))"
    exit 1
fi

if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
    print_error "could not resolve home for install user $(install_user)"
    exit 1
fi

if openrgb_is_ours; then
    ver="$("$SYS_BIN" --version 2>/dev/null | head -1 || true)"
    print_success "Already installed: openrgb (${ver:-$OPENRGB_VERSION}; AppImage at $USER_APPIMAGE)"
    exit 0
fi

# Wrapper install needs root/sudo; AppImage itself is user-owned.
if [[ "$(id -u)" -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
    print_error "need sudo to install /usr/local/bin/openrgb wrapper"
    exit 1
fi

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

echo "Installing AppImage to ${USER_APPIMAGE}..."
# Ensure Applications dir exists and is owned by the install user.
if [[ "$(id -u)" -eq 0 ]]; then
    install -d -o "$INSTALL_USER" -g "$(id -gn "$INSTALL_USER")" -m 755 "$APPDIR"
    install -o "$INSTALL_USER" -g "$(id -gn "$INSTALL_USER")" -m 755 "$tmp_img" "$USER_APPIMAGE"
else
    mkdir -p "$APPDIR"
    install -m 755 "$tmp_img" "$USER_APPIMAGE"
fi
got="$(sha256_file "$USER_APPIMAGE")"
if [[ "$got" != "$OPENRGB_APPIMAGE_SHA256" ]]; then
    rm -f "$USER_APPIMAGE"
    print_error "SHA-256 mismatch after install to Applications"
    exit 1
fi

echo "Installing PATH wrapper at ${SYS_BIN} → ${USER_APPIMAGE}..."
wrapper="${tmpdir}/openrgb"
# Absolute path so root (boot) and any user resolve the same file.
cat >"$wrapper" <<EOF
#!/usr/bin/env bash
# linux-utils OpenRGB ${OPENRGB_VERSION} — launches user AppImage
exec $(printf %q "$USER_APPIMAGE") --appimage-extract-and-run "\$@"
EOF
run_root install -m 755 "$wrapper" "$SYS_BIN"
run_root chown root:root "$SYS_BIN"

# Drop legacy system AppImage tree if present.
if [[ -d "$LEGACY_SYS_LIB" ]]; then
    echo "Removing legacy system AppImage at ${LEGACY_SYS_LIB}..."
    run_root rm -rf "$LEGACY_SYS_LIB"
fi

if ! is_installed "openrgb"; then
    print_error "openrgb not on PATH after install (is /usr/local/bin in PATH?)"
    exit 1
fi

if command -v openrgb >/dev/null 2>&1; then
    resolved="$(command -v openrgb)"
    if [[ "$resolved" != "$SYS_BIN" ]]; then
        print_warning "PATH resolves openrgb to $resolved (expected $SYS_BIN); check PATH order"
    fi
fi

ver="$("$SYS_BIN" --version 2>/dev/null | head -1 || true)"
print_success "Successfully installed: openrgb (${ver:-$OPENRGB_VERSION})"
print_success "AppImage: $USER_APPIMAGE"
print_success "Wrapper:  $SYS_BIN"
