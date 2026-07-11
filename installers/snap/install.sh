#!/bin/bash

# Snap package installer
# Reads snaps.txt and installs specified snap packages

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/snaps.txt"

require_file "$PACKAGES_FILE"

echo "Installing snap packages..."

# One list call for the whole run (was once per package).
mapfile -t installed_snaps < <(snap list 2>/dev/null | awk 'NR > 1 { print $1 }')

is_snap_installed() {
    local package="$1"
    local installed
    for installed in "${installed_snaps[@]}"; do
        [[ "$installed" == "$package" ]] && return 0
    done
    return 1
}

regular=()
classic=()
while IFS= read -r line; do
    package_info=$(echo "$line" | cut -d'#' -f1 | xargs)
    [[ -z "$package_info" ]] && continue

    if [[ "$package_info" == *"--classic"* ]]; then
        package=$(echo "$package_info" | sed 's/--classic//' | xargs)
        if is_snap_installed "$package"; then
            print_success "Already installed: $package"
        else
            classic+=("$package")
        fi
    else
        package="$package_info"
        if is_snap_installed "$package"; then
            print_success "Already installed: $package"
        else
            regular+=("$package")
        fi
    fi
done < <(read_package_list "$PACKAGES_FILE")

if ((${#regular[@]})); then
    echo "Installing ${#regular[@]} snaps: ${regular[*]}"
    if sudo snap install "${regular[@]}"; then
        for package in "${regular[@]}"; do
            print_success "Successfully installed: $package"
            installed_snaps+=("$package")
        done
    else
        print_warning "Batch snap install failed; retrying individually..."
        for package in "${regular[@]}"; do
            if is_snap_installed "$package"; then
                print_success "Already installed: $package"
                continue
            fi
            echo "Installing: $package"
            if sudo snap install "$package"; then
                print_success "Successfully installed: $package"
                installed_snaps+=("$package")
            else
                print_error "Failed to install: $package"
            fi
        done
    fi
fi

# Classic confinement cannot be mixed into the same snap install transaction.
for package in "${classic[@]}"; do
    echo "Installing: $package (classic)"
    if sudo snap install --classic "$package"; then
        print_success "Successfully installed: $package"
        installed_snaps+=("$package")
    else
        print_error "Failed to install: $package"
    fi
done

echo "Snap installation complete."
