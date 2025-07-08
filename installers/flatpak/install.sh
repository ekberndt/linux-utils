#!/bin/bash

# Flatpak package installer
# Reads flatpaks.txt and installs specified flatpak packages from Flathub

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/flatpaks.txt"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

if [ ! -f "$PACKAGES_FILE" ]; then
    echo "Error: flatpaks.txt not found in $SCRIPT_DIR"
    exit 1
fi

# Check if flatpak is installed
if ! command -v flatpak >/dev/null 2>&1; then
    echo "Flatpak not found. Installing flatpak..."
    if sudo apt update >/dev/null 2>&1 && sudo apt install -y flatpak >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Successfully installed flatpak${NC}"
    else
        echo -e "${RED}✗ Failed to install flatpak${NC}"
        exit 1
    fi
fi

# Add Flathub repository if not already added
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "Installing flatpak packages..."

while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    
    # Parse format: APP_ID # DESCRIPTION
    app_id=$(echo "$line" | cut -d'#' -f1 | xargs)
    
    if [[ -n "$app_id" ]]; then
        if flatpak list | grep -q "$app_id"; then
            echo -e "${BLUE}✓ Already installed: $app_id${NC}"
        else
            echo "Installing: $app_id"
            if flatpak install -y flathub "$app_id"; then
                echo -e "${GREEN}✓ Successfully installed: $app_id${NC}"
            else
                echo -e "${RED}✗ Failed to install: $app_id${NC}"
            fi
        fi
    fi
done < "$PACKAGES_FILE"

echo "Flatpak installation complete."
