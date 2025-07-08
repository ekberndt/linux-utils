#!/bin/bash

# APT package installer
# Reads apt_packages.txt and installs specified apt packages

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/apt_packages.txt"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

if [ ! -f "$PACKAGES_FILE" ]; then
    echo "Error: apt_packages.txt not found in $SCRIPT_DIR"
    exit 1
fi

echo "Installing apt packages..."

# Collect PPAs first
ppas=()
while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    
    # Check if line contains PPA notation (package | ppa:repository)
    if [[ "$line" =~ ^([^|#]+)\|[[:space:]]*ppa:([^#]+) ]]; then
        # Extract PPA
        ppa=$(echo "${BASH_REMATCH[2]}" | xargs)
        
        if [[ -n "$ppa" ]]; then
            ppas+=("ppa:$ppa")
        fi
    fi
done < "$PACKAGES_FILE"

# Add PPAs if any exist
if [[ ${#ppas[@]} -gt 0 ]]; then
    echo "Adding ${#ppas[@]} PPAs..."
    for ppa in "${ppas[@]}"; do
        echo "Adding PPA: $ppa"
        sudo add-apt-repository -y "$ppa"
    done
    echo "Updating package lists after adding PPAs..."
    sudo apt update
fi

# Install packages one by one
while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    
    # Check if line contains PPA notation (package | ppa:repository)
    if [[ "$line" =~ ^([^|#]+)\|[[:space:]]*ppa:([^#]+) ]]; then
        # Extract package name
        package=$(echo "${BASH_REMATCH[1]}" | xargs)
    else
        # Extract regular package name (first word before any comment)
        package=$(echo "$line" | awk '{print $1}')
    fi
    
    if [[ -n "$package" ]]; then
        if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"; then
            echo -e "${BLUE}✓ Already installed: $package${NC}"
        else
            echo "Installing: $package"
            if sudo apt install -y "$package"; then
                echo -e "${GREEN}✓ Successfully installed: $package${NC}"
            else
                echo -e "${RED}✗ Failed to install: $package${NC}"
            fi
        fi
    fi
done < "$PACKAGES_FILE"

echo "APT installation complete."
