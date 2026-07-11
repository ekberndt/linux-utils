#!/bin/bash

# Grok Build installer
# Installs the xAI Grok Build CLI via the official install script
# https://x.ai/cli  https://docs.x.ai/build/overview

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

if is_installed "grok"; then
    print_success "Already installed: grok ($(grok --version 2>/dev/null | head -n1))"
    exit 0
fi

echo "Installing Grok Build..."
if curl -fsSL https://x.ai/cli/install.sh | bash; then
    export PATH="$HOME/.local/bin:$PATH"
    if is_installed "grok"; then
        print_success "Successfully installed: grok ($(grok --version 2>/dev/null | head -n1))"
        exit 0
    fi
    if [[ -x "$HOME/.local/bin/grok" ]]; then
        print_success "Successfully installed: grok ($HOME/.local/bin/grok)"
        exit 0
    fi
    print_error "Install script finished but grok not found on PATH"
    exit 1
else
    print_error "Failed to install grok"
    exit 1
fi
