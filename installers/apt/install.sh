#!/bin/bash

# APT package installer
# Reads apt_packages.txt and installs specified apt packages

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/apt_packages.txt"

require_file "$PACKAGES_FILE"

echo "Installing apt packages..."

# Collect PPAs first
ppas=()
while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    # Strip optional prefix for PPA check
    if [[ "$line" =~ ^\?[[:space:]]+(.*) ]]; then
        line="${BASH_REMATCH[1]}"
    fi

    # Check if line contains PPA notation (package | ppa:repository)
    if [[ "$line" =~ ^([^|#]+)\|[[:space:]]*ppa:([^#]+) ]]; then
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
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    # Check if line is optional (prefixed with ?)
    optional=false
    if [[ "$line" =~ ^\?[[:space:]]+(.*) ]]; then
        optional=true
        line="${BASH_REMATCH[1]}"
    fi

    # Check if line contains PPA notation (package | ppa:repository)
    if [[ "$line" =~ ^([^|#]+)\|[[:space:]]*ppa:([^#]+) ]]; then
        package=$(echo "${BASH_REMATCH[1]}" | xargs)
    else
        package=$(echo "$line" | awk '{print $1}')
    fi

    if [[ -n "$package" ]]; then
        if $optional; then
            read -r -p "Install optional package '$package'? [y/N] " response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                echo "Skipping: $package"
                continue
            fi
        fi

        if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"; then
            print_success "Already installed: $package"
        else
            echo "Installing: $package"
            if sudo apt install -y "$package"; then
                print_success "Successfully installed: $package"
            else
                print_error "Failed to install: $package"
            fi
        fi
    fi
done < "$PACKAGES_FILE"

echo "APT installation complete."
