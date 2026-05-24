#!/bin/bash

# Claude Code installer
# Installs Claude Code CLI via the official Anthropic install script
# https://docs.claude.com/en/docs/claude-code/setup

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

if is_installed "claude"; then
    print_success "Already installed: claude ($(claude --version 2>/dev/null | head -n1))"
    exit 0
fi

echo "Installing Claude Code..."
if curl -fsSL https://claude.ai/install.sh | bash; then
    print_success "Successfully installed: claude"
else
    print_error "Failed to install claude"
    exit 1
fi
