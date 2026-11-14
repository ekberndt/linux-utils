#!/bin/bash
set -uo pipefail

# Bazel buildtools installer
# Installs the latest buildifier, buildozer, and unused-deps from GitHub
# releases into /usr/local/bin, or replaces older ones.

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

# INSTALLER_BIN_DIR lets tests stand in for /usr/local/bin.
INSTALL_DIR="${INSTALLER_BIN_DIR:-/usr/local/bin}"
TOOLS=("buildifier" "buildozer" "unused-deps")

ARCH_SUFFIX="$(detect_arch)" || exit 1
if ! LATEST="$(latest_release bazel-contrib/buildtools)"; then
    print_error "Failed to fetch latest buildtools release tag"
    exit 1
fi

for tool in "${TOOLS[@]}"; do
    bin="${INSTALL_DIR}/${tool}"
    installed=""
    if [[ -x "$bin" ]]; then
        installed="$(cli_version "$bin")"
        if [[ -z "$installed" ]]; then
            print_error "Could not read the installed ${tool} version"
            exit 1
        fi
        version_newer "$LATEST" "$installed" || continue
    fi

    echo "Downloading ${tool} ${LATEST}..."
    if ! install_release_binary bazel-contrib/buildtools "$LATEST" \
        "${tool}-linux-${ARCH_SUFFIX}" "$bin"; then
        print_error "Failed to install ${tool} ${LATEST}"
        exit 1
    fi
    if [[ -n "$installed" ]]; then
        print_updated "${tool} $installed -> ${LATEST#v}"
    else
        print_installed "${tool} ${LATEST#v}"
    fi
done
