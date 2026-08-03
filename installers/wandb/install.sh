#!/bin/bash

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

find_uv() {
    local candidate
    if command -v uv >/dev/null 2>&1; then
        command -v uv
        return
    fi

    for candidate in "$HOME/.local/bin/uv" "$HOME/.cargo/bin/uv"; do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return
        fi
    done
    return 1
}

if command -v wandb >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/wandb" ]]; then
    print_success "Already installed: wandb"
    exit 0
fi

if ! uv_bin="$(find_uv)"; then
    print_error "uv is required; run 'installers/installer.sh uv' first"
    exit 1
fi

echo "Installing W&B via uv..."
if "$uv_bin" tool install wandb && "$uv_bin" tool update-shell; then
    print_success "Successfully installed: wandb"
else
    print_error "Failed to install wandb"
    exit 1
fi
