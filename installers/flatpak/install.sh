#!/bin/bash

# Flatpak package installer
# Reads flatpaks.txt and installs specified flatpak packages from Flathub
# into the per-user installation (no polkit/system-helper required).

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/flatpaks.txt"

require_file "$PACKAGES_FILE"

# Check if flatpak is installed
if ! is_installed "flatpak"; then
    echo "Flatpak not found. Installing flatpak..."
    if sudo apt-get install -y flatpak; then
        print_success "Successfully installed flatpak"
    else
        print_error "Failed to install flatpak"
        exit 1
    fi
fi

# User-scope installs write under ~/.local/share/flatpak and do not need the
# system helper. System-wide `flatpak install` (the default) goes through
# polkit and fails under the dashboard with:
#   "Flatpak system operation Deploy not allowed for user"
flatpak remote-add --user --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo

echo "Installing flatpak packages (user scope)..."

# One list call for the whole run; user or system installs both count as present.
mapfile -t installed_apps < <(flatpak list --app --columns=application 2>/dev/null)

is_flatpak_installed() {
    local app_id="$1"
    local installed
    for installed in "${installed_apps[@]}"; do
        [[ "$installed" == "$app_id" ]] && return 0
    done
    return 1
}

missing=()
while IFS= read -r line; do
    app_id=$(echo "$line" | cut -d'#' -f1 | xargs)
    [[ -z "$app_id" ]] && continue

    if is_flatpak_installed "$app_id"; then
        print_success "Already installed: $app_id"
    else
        missing+=("$app_id")
    fi
done < <(read_package_list "$PACKAGES_FILE")

if ((${#missing[@]} == 0)); then
    echo "Flatpak installation complete."
    exit 0
fi

echo "Installing ${#missing[@]} flatpaks: ${missing[*]}"
if flatpak install --user -y flathub "${missing[@]}"; then
    for app_id in "${missing[@]}"; do
        print_success "Successfully installed: $app_id"
        installed_apps+=("$app_id")
    done
else
    print_warning "Batch flatpak install failed; retrying individually..."
    for app_id in "${missing[@]}"; do
        if is_flatpak_installed "$app_id"; then
            print_success "Already installed: $app_id"
            continue
        fi
        echo "Installing: $app_id"
        if flatpak install --user -y flathub "$app_id"; then
            print_success "Successfully installed: $app_id"
            installed_apps+=("$app_id")
        else
            print_error "Failed to install: $app_id"
        fi
    done
fi

echo "Flatpak installation complete."
