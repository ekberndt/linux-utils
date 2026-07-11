#!/bin/bash

# zoxide installer
# Official install script + Bash init from:
# https://github.com/ajeetdsouza/zoxide#installation

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

BASHRC="$HOME/.bashrc"
# Written into bashrc literally — expand when the shell sources it.
INIT_LINE="eval \"\$(zoxide init bash)\""

if ! is_installed "zoxide"; then
    echo "Installing zoxide..."
    if ! curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh; then
        print_error "Failed to install zoxide"
        exit 1
    fi
    print_success "Successfully installed: zoxide"
else
    print_success "Already installed: zoxide ($(zoxide --version 2>/dev/null | head -n1))"
fi

# README step 2: add init to the end of ~/.bashrc
if [[ -f "$BASHRC" ]] && grep -Fq 'zoxide init bash' "$BASHRC"; then
    print_success "already configured: $BASHRC"
    exit 0
fi

{
    echo ""
    echo "# zoxide"
    echo "$INIT_LINE"
} >> "$BASHRC"
print_success "added zoxide init: $BASHRC"
