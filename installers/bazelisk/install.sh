#!/bin/bash

# Bazelisk installer
# Downloads the latest bazelisk binary from GitHub releases and installs it to /usr/local/bin

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

INSTALL_DIR="/usr/local/bin"
INSTALL_NAME="bazelisk"

if is_installed "bazelisk"; then
    print_success "Already installed: bazelisk"
    exit 0
fi

echo "Installing bazelisk..."

ARCH_SUFFIX="$(detect_arch)" || exit 1
BINARY="bazelisk-linux-${ARCH_SUFFIX}"

# Fetch the latest release tag from GitHub API
echo "Fetching latest bazelisk release..."
LATEST_TAG="$(curl -fsSL "https://api.github.com/repos/bazelbuild/bazelisk/releases/latest" \
    | grep '"tag_name"' \
    | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')"

if [[ -z "$LATEST_TAG" ]]; then
    print_error "Failed to fetch latest bazelisk release tag"
    exit 1
fi

DOWNLOAD_URL="https://github.com/bazelbuild/bazelisk/releases/download/${LATEST_TAG}/${BINARY}"
echo "Downloading ${BINARY} (${LATEST_TAG})..."

if sudo curl -fsSL "$DOWNLOAD_URL" -o "${INSTALL_DIR}/${INSTALL_NAME}" \
    && sudo chmod +x "${INSTALL_DIR}/${INSTALL_NAME}"; then
    print_success "Successfully installed: bazelisk ${LATEST_TAG}"
else
    print_error "Failed to install bazelisk"
    exit 1
fi
