#!/bin/bash

# Ollama installer
# Installs Ollama via the official install script
# https://ollama.com  https://github.com/ollama/ollama

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

if is_installed "ollama"; then
    print_success "Already installed: ollama ($(ollama --version 2>/dev/null | head -n1))"
    exit 0
fi

echo "Installing Ollama..."
if curl -fsSL https://ollama.com/install.sh | sh; then
    if is_installed "ollama"; then
        print_success "Successfully installed: ollama ($(ollama --version 2>/dev/null | head -n1))"
        exit 0
    fi
    print_error "Install script finished but ollama not found on PATH"
    exit 1
else
    print_error "Failed to install ollama"
    exit 1
fi
