#!/bin/bash

# Tailscale installer
# Installs Tailscale via the official install script

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

if command -v tailscale &>/dev/null; then
    echo -e "${BLUE}✓ Already installed: tailscale ($(tailscale version | head -n1))${NC}"
    exit 0
fi

echo "Installing tailscale..."
if curl -fsSL https://tailscale.com/install.sh | sh; then
    echo -e "${GREEN}✓ Successfully installed: tailscale${NC}"
    echo -e "${BLUE}Next: run 'sudo tailscale up' to authenticate and connect.${NC}"
else
    echo -e "${RED}✗ Failed to install tailscale${NC}"
    exit 1
fi
