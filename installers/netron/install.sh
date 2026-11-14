#!/bin/bash
set -uo pipefail

# Netron model viewer from PyPI as a uv tool: `netron model.onnx` serves it on
# localhost:8080 and `-b` opens a browser. Upstream's Linux desktop builds are
# amd64-only, and it has discontinued its Snap and AppImage; the wheel is the
# same viewer in pure Python, so one install works on every arch.
# https://github.com/lutzroeder/netron/issues/1500

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

# The uv installer and `uv tool` both use ~/.local/bin, which a non-login
# installer run does not always have on PATH.
PATH="$HOME/.local/bin:$PATH"

if ! is_installed uv; then
    print_error "uv is required; run 'installers/installer.sh uv' first"
    exit 1
fi

# uv's receipt, not PATH, proves this install: a retired snap or a pip copy also
# answers to `netron`. Reading it stays offline; the uv component upgrades it
# with every other uv tool.
netron_version() {
    uv tool list 2>/dev/null | awk '$1 == "netron" { print $2 }'
}

version="$(netron_version)"
if [[ -n "$version" ]]; then
    print_success "Already installed: netron ($version)"
    exit 0
fi

echo "Installing netron via uv..."
if ! uv tool install netron; then
    print_error "Failed to install netron"
    exit 1
fi
print_installed "netron ($(netron_version))"
