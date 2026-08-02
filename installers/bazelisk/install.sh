#!/bin/bash

# Bazelisk installer
# Downloads the latest bazelisk binary from GitHub releases into /usr/local/bin.
# Upstream package managers expose both names; the README tip for manual install
# is to put it on PATH as `bazel`. We install as bazelisk and symlink bazel.

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

INSTALL_DIR="/usr/local/bin"
BAZELISK_BIN="${INSTALL_DIR}/bazelisk"
BAZEL_BIN="${INSTALL_DIR}/bazel"

# Point `bazel` at our bazelisk, matching brew/winget/choco (both names on PATH).
link_bazel() {
    if [[ ! -x "$BAZELISK_BIN" ]]; then
        return 0
    fi
    if [[ -e "$BAZEL_BIN" && ! -L "$BAZEL_BIN" ]]; then
        print_warning "Leaving existing non-symlink ${BAZEL_BIN} in place"
        return 0
    fi
    if [[ -L "$BAZEL_BIN" ]] && [[ "$(readlink -f "$BAZEL_BIN")" == "$(readlink -f "$BAZELISK_BIN")" ]]; then
        return 0
    fi
    sudo ln -sfn bazelisk "$BAZEL_BIN"
    print_success "Linked bazel -> bazelisk"
}

if [[ -x "$BAZELISK_BIN" ]]; then
    print_success "Already installed: bazelisk"
    link_bazel
    exit 0
fi

echo "Installing bazelisk..."

ARCH_SUFFIX="$(detect_arch)" || exit 1
BINARY="bazelisk-linux-${ARCH_SUFFIX}"

# /releases/latest/download/ follows redirects without hitting the GitHub REST API
# (unauthenticated API is rate-limited and fails install with 403).
DOWNLOAD_URL="https://github.com/bazelbuild/bazelisk/releases/latest/download/${BINARY}"
echo "Downloading ${BINARY} (latest)..."

if sudo curl -fsSL "$DOWNLOAD_URL" -o "$BAZELISK_BIN" \
    && sudo chmod +x "$BAZELISK_BIN"; then
    print_success "Successfully installed: bazelisk"
    link_bazel
else
    print_error "Failed to install bazelisk"
    exit 1
fi
