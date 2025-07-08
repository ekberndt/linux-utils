#!/bin/bash

# Snap package installer
# Reads snaps.txt and installs specified snap packages

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/snaps.txt"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

if [ ! -f "$PACKAGES_FILE" ]; then
    echo "Error: snaps.txt not found in $SCRIPT_DIR"
    exit 1
fi

echo "Installing snap packages..."

while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    
    # Extract package info before comment
    package_info=$(echo "$line" | cut -d'#' -f1 | xargs)
    
    if [[ -n "$package_info" ]]; then
        # Check if package has --classic flag
        if [[ "$package_info" == *"--classic"* ]]; then
            package=$(echo "$package_info" | sed 's/--classic//' | xargs)
            if snap list | grep -q "^$package "; then
                echo -e "${BLUE}✓ Already installed: $package${NC}"
            else
                echo "Installing: $package (classic)"
                if sudo snap install --classic "$package"; then
                    echo -e "${GREEN}✓ Successfully installed: $package${NC}"
                else
                    echo -e "${RED}✗ Failed to install: $package${NC}"
                fi
            fi
        else
            package="$package_info"
            if snap list | grep -q "^$package "; then
                echo -e "${BLUE}✓ Already installed: $package${NC}"
            else
                echo "Installing: $package"
                if sudo snap install "$package"; then
                    echo -e "${GREEN}✓ Successfully installed: $package${NC}"
                else
                    echo -e "${RED}✗ Failed to install: $package${NC}"
                fi
            fi
        fi
    fi
done < "$PACKAGES_FILE"

echo "Snap installation complete."
