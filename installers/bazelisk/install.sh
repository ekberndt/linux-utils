#!/bin/bash

# Bazelisk installer
# Downloads the latest bazelisk binary from GitHub releases and installs it to /usr/local/bin

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

INSTALL_DIR="/usr/local/bin"
INSTALL_NAME="bazelisk"

if command -v bazelisk &>/dev/null; then
    echo -e "${BLUE}✓ Already installed: bazelisk${NC}"
    exit 0
fi

echo "Installing bazelisk..."

# Detect architecture
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  ARCH_SUFFIX="amd64" ;;
    aarch64) ARCH_SUFFIX="arm64" ;;
    *)
        echo -e "${RED}✗ Unsupported architecture: $ARCH${NC}"
        exit 1
        ;;
esac

BINARY="bazelisk-linux-${ARCH_SUFFIX}"

# Fetch the latest release tag from GitHub API
echo "Fetching latest bazelisk release..."
LATEST_TAG="$(curl -fsSL "https://api.github.com/repos/bazelbuild/bazelisk/releases/latest" \
    | grep '"tag_name"' \
    | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')"

if [[ -z "$LATEST_TAG" ]]; then
    echo -e "${RED}✗ Failed to fetch latest bazelisk release tag${NC}"
    exit 1
fi

DOWNLOAD_URL="https://github.com/bazelbuild/bazelisk/releases/download/${LATEST_TAG}/${BINARY}"
echo "Downloading ${BINARY} (${LATEST_TAG})..."

if sudo curl -fsSL "$DOWNLOAD_URL" -o "${INSTALL_DIR}/${INSTALL_NAME}" \
    && sudo chmod +x "${INSTALL_DIR}/${INSTALL_NAME}"; then
    echo -e "${GREEN}✓ Successfully installed: bazelisk ${LATEST_TAG}${NC}"
else
    echo -e "${RED}✗ Failed to install bazelisk${NC}"
    exit 1
fi
