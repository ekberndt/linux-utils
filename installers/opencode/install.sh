#!/bin/bash

# OpenCode installer
# Installs the open source AI coding agent CLI
# https://opencode.ai

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

if is_installed "opencode"; then
    print_success "Already installed: opencode ($(opencode --version 2>/dev/null | head -n1))"
    exit 0
fi

echo "Installing OpenCode..."
if curl -fsSL https://opencode.ai/install | bash; then
    print_success "Successfully installed: opencode"
else
    print_error "Failed to install opencode"
    exit 1
fi
