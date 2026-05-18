#!/bin/bash

# Bazel buildtools installer
# Downloads the latest buildifier, buildozer, and unused-deps binaries from GitHub releases
# and installs them to /usr/local/bin

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

INSTALL_DIR="/usr/local/bin"
TOOLS=("buildifier" "buildozer" "unused-deps")

# Check if all tools are already installed
all_installed=true
for tool in "${TOOLS[@]}"; do
    if ! is_installed "$tool"; then
        all_installed=false
        break
    fi
done

if [[ "$all_installed" == true ]]; then
    print_success "Already installed: buildtools (buildifier, buildozer, unused-deps)"
    exit 0
fi

echo "Installing buildtools..."

ARCH_SUFFIX="$(detect_arch)" || exit 1

# Fetch the latest release tag from GitHub API
echo "Fetching latest buildtools release..."
LATEST_TAG="$(curl -fsSL "https://api.github.com/repos/bazelbuild/buildtools/releases/latest" \
    | grep '"tag_name"' \
    | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')"

if [[ -z "$LATEST_TAG" ]]; then
    print_error "Failed to fetch latest buildtools release tag"
    exit 1
fi

for tool in "${TOOLS[@]}"; do
    if is_installed "$tool"; then
        print_success "Already installed: ${tool}"
        continue
    fi

    BINARY="${tool}-linux-${ARCH_SUFFIX}"
    DOWNLOAD_URL="https://github.com/bazelbuild/buildtools/releases/download/${LATEST_TAG}/${BINARY}"
    echo "Downloading ${BINARY} (${LATEST_TAG})..."

    if sudo curl -fsSL "$DOWNLOAD_URL" -o "${INSTALL_DIR}/${tool}" \
        && sudo chmod +x "${INSTALL_DIR}/${tool}"; then
        print_success "Successfully installed: ${tool} ${LATEST_TAG}"
    else
        print_error "Failed to install ${tool}"
        exit 1
    fi
done
