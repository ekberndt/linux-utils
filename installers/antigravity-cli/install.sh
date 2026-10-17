#!/bin/bash
set -uo pipefail

# Google Antigravity CLI
# https://antigravity.google/product/antigravity-cli

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

INSTALL_URL="https://antigravity.google/cli/install.sh"
LOCAL_BIN="$HOME/.local/bin"

install_macos() {
    local brew_path

    if ! brew_path="$(find_brew)"; then
        print_error "Homebrew is required: https://brew.sh"
        return 1
    fi

    if "$brew_path" list --cask antigravity-cli >/dev/null 2>&1; then
        print_success "Already installed: Antigravity CLI"
        return 0
    fi

    echo "Installing Antigravity CLI via Homebrew..."
    if ! "$brew_path" install --cask antigravity-cli; then
        print_error "Failed to install Antigravity CLI"
        return 1
    fi
    print_success "Successfully installed: Antigravity CLI"
}

install_linux() {
    case ":$PATH:" in
        *":$LOCAL_BIN:"*) ;;
        *) export PATH="$LOCAL_BIN:$PATH" ;;
    esac

    install_from_web_script agy "$INSTALL_URL" bash
}

case "$(uname -s)" in
    Darwin) install_macos ;;
    Linux) install_linux ;;
    *)
        print_error "Unsupported operating system: $(uname -s)"
        exit 1
        ;;
esac
