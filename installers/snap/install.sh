#!/bin/bash

# Snap package installer
# Reads snaps.txt and installs specified snap packages

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/snaps.txt"

require_file "$PACKAGES_FILE"

echo "Installing snap packages..."

read_package_list "$PACKAGES_FILE" | while IFS= read -r line; do
    # Extract package info before comment
    package_info=$(echo "$line" | cut -d'#' -f1 | xargs)

    if [[ -n "$package_info" ]]; then
        # Check if package has --classic flag
        if [[ "$package_info" == *"--classic"* ]]; then
            package=$(echo "$package_info" | sed 's/--classic//' | xargs)
            classic_flag="--classic"
            label="$package (classic)"
        else
            package="$package_info"
            classic_flag=""
            label="$package"
        fi

        if snap list | grep -q "^$package "; then
            print_success "Already installed: $package"
        else
            echo "Installing: $label"
            # shellcheck disable=SC2086
            if sudo snap install $classic_flag "$package"; then
                print_success "Successfully installed: $package"
            else
                print_error "Failed to install: $package"
            fi
        fi
    fi
done

echo "Snap installation complete."
