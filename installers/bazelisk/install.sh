#!/bin/bash
set -uo pipefail

# Bazelisk installer
# Installs the latest bazelisk binary from GitHub releases into /usr/local/bin,
# or replaces an older one. Upstream package managers expose both names; the
# README tip for manual install is to put it on PATH as `bazel`. We install as
# bazelisk and symlink bazel.

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

# INSTALLER_BIN_DIR lets tests stand in for /usr/local/bin.
INSTALL_DIR="${INSTALLER_BIN_DIR:-/usr/local/bin}"
BAZELISK_BIN="${INSTALL_DIR}/bazelisk"
BAZEL_BIN="${INSTALL_DIR}/bazel"

# Point `bazel` at our bazelisk, matching brew/winget/choco (both names on PATH).
link_bazel() {
    if [[ -e "$BAZEL_BIN" && ! -L "$BAZEL_BIN" ]]; then
        echo "Leaving existing non-symlink ${BAZEL_BIN} in place"
        return 0
    fi
    if [[ -L "$BAZEL_BIN" ]] && [[ "$(readlink -f "$BAZEL_BIN")" == "$(readlink -f "$BAZELISK_BIN")" ]]; then
        return 0
    fi
    run_as_root ln -sfn bazelisk "$BAZEL_BIN"
    print_updated "bazel -> bazelisk"
}

# `bazelisk --version` answers with Bazel's version. `bazelisk version` prints
# its own first, then hands off to Bazel; an absolute USE_BAZEL_VERSION makes
# that Bazel `true`, so nothing downloads and no server starts.
bazelisk_version() {
    USE_BAZEL_VERSION=/usr/bin/true "$BAZELISK_BIN" version 2>/dev/null | last_version
}

ARCH_SUFFIX="$(detect_arch)" || exit 1
if ! LATEST="$(latest_release bazelbuild/bazelisk)"; then
    print_error "Could not find the latest bazelisk release"
    exit 1
fi

installed=""
if [[ -x "$BAZELISK_BIN" ]]; then
    installed="$(bazelisk_version)"
    if [[ -z "$installed" ]]; then
        print_error "Could not read the installed bazelisk version"
        exit 1
    fi
fi

if [[ -z "$installed" ]] || version_newer "$LATEST" "$installed"; then
    echo "Downloading bazelisk ${LATEST}..."
    if ! install_release_binary bazelbuild/bazelisk "$LATEST" \
        "bazelisk-linux-${ARCH_SUFFIX}" "$BAZELISK_BIN"; then
        print_error "Failed to install bazelisk ${LATEST}"
        exit 1
    fi
    if [[ -n "$installed" ]]; then
        print_updated "bazelisk $installed -> ${LATEST#v}"
    else
        print_installed "bazelisk ${LATEST#v}"
    fi
fi
link_bazel
