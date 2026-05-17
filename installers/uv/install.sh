#!/bin/bash

# uv installer
# Installs uv (Python package manager) via the official install script

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

if is_installed "uv"; then
    print_success "Already installed: uv ($(uv --version))"
    exit 0
fi

echo "Installing uv..."
if curl -LsSf https://astral.sh/uv/install.sh | sh; then
    print_success "Successfully installed: uv"
else
    print_error "Failed to install uv"
    exit 1
fi
