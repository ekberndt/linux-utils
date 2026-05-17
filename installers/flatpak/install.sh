#!/bin/bash

# Flatpak package installer
# Reads flatpaks.txt and installs specified flatpak packages from Flathub

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/flatpaks.txt"

require_file "$PACKAGES_FILE"

# Check if flatpak is installed
if ! is_installed "flatpak"; then
    echo "Flatpak not found. Installing flatpak..."
    if sudo apt update >/dev/null 2>&1 && sudo apt install -y flatpak >/dev/null 2>&1; then
        print_success "Successfully installed flatpak"
    else
        print_error "Failed to install flatpak"
        exit 1
    fi
fi

# Add Flathub repository if not already added
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "Installing flatpak packages..."

read_package_list "$PACKAGES_FILE" | while IFS= read -r line; do
    # Parse format: APP_ID # DESCRIPTION
    app_id=$(echo "$line" | cut -d'#' -f1 | xargs)

    if [[ -n "$app_id" ]]; then
        if flatpak list | grep -q "$app_id"; then
            print_success "Already installed: $app_id"
        else
            echo "Installing: $app_id"
            if flatpak install -y flathub "$app_id"; then
                print_success "Successfully installed: $app_id"
            else
                print_error "Failed to install: $app_id"
            fi
        fi
    fi
done

echo "Flatpak installation complete."
