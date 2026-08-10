#!/bin/bash
set -uo pipefail

# Grok Build installer
# Installs the xAI Grok Build CLI via the official install script
# https://x.ai/cli  https://docs.x.ai/build/overview
#
# The official script links the binary into ~/.grok/bin and appends that
# directory to ~/.bashrc. Non-login installer runs do not re-source bashrc,
# so verification must look at known install locations directly.

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

GROK_BIN_DIRS=(
    "$HOME/.grok/bin"
    "$HOME/.local/bin"
)

# Prepend known install dirs for this process (bashrc is only for future shells).
export_grok_path() {
    local dir
    for dir in "${GROK_BIN_DIRS[@]}"; do
        case ":$PATH:" in
            *":$dir:"*) ;;
            *) export PATH="$dir:$PATH" ;;
        esac
    done
}

find_grok_bin() {
    local dir
    if command -v grok >/dev/null 2>&1; then
        command -v grok
        return 0
    fi
    for dir in "${GROK_BIN_DIRS[@]}"; do
        if [[ -x "$dir/grok" ]]; then
            echo "$dir/grok"
            return 0
        fi
    done
    return 1
}

export_grok_path

if grok_bin="$(find_grok_bin)"; then
    print_success "Already installed: grok ($("$grok_bin" --version 2>/dev/null | head -n1))"
    exit 0
fi

echo "Installing Grok Build..."
if ! curl -fsSL https://x.ai/cli/install.sh | bash; then
    print_error "Failed to install grok"
    exit 1
fi

export_grok_path

if grok_bin="$(find_grok_bin)"; then
    print_success "Successfully installed: grok ($("$grok_bin" --version 2>/dev/null | head -n1))"
    exit 0
fi

print_error "Install script finished but grok not found under ${GROK_BIN_DIRS[*]}"
exit 1
