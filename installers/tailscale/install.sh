#!/bin/bash

# Tailscale installer
# Installs Tailscale via the official install script

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

if is_installed "tailscale"; then
    print_success "Already installed: tailscale ($(tailscale version | head -n1))"
    exit 0
fi

echo "Installing tailscale..."
if curl -fsSL https://tailscale.com/install.sh | sh; then
    print_success "Successfully installed: tailscale"
    echo -e "${BLUE}Next: run 'sudo tailscale up' to authenticate and connect.${NC}"
else
    print_error "Failed to install tailscale"
    exit 1
fi
