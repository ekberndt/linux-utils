#!/bin/bash

# Codex installer
# Installs OpenAI Codex CLI globally via npm
# https://github.com/openai/codex

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

if is_installed "codex"; then
    print_success "Already installed: codex ($(codex --version 2>/dev/null | head -n1))"
    exit 0
fi

# Codex requires npm. Install Node.js (which provides npm) from NodeSource
# if it's not already available, since Ubuntu's default node package is often outdated.
if ! is_installed "npm"; then
    echo "npm not found. Installing Node.js LTS from NodeSource..."
    if curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && \
       sudo apt install -y nodejs; then
        print_success "Installed Node.js $(node --version) / npm $(npm --version)"
    else
        print_error "Failed to install Node.js / npm (required for codex)"
        exit 1
    fi
fi

echo "Installing @openai/codex globally via npm..."
if sudo npm install -g @openai/codex; then
    print_success "Successfully installed: codex $(codex --version 2>/dev/null | head -n1)"
else
    print_error "Failed to install codex"
    exit 1
fi
