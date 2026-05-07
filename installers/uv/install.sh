#!/bin/bash

# uv installer
# Installs uv (Python package manager) via the official install script

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

if command -v uv &>/dev/null; then
    echo -e "${BLUE}✓ Already installed: uv ($(uv --version))${NC}"
    exit 0
fi

echo "Installing uv..."
if curl -LsSf https://astral.sh/uv/install.sh | sh; then
    echo -e "${GREEN}✓ Successfully installed: uv${NC}"
else
    echo -e "${RED}✗ Failed to install uv${NC}"
    exit 1
fi
