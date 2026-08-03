#!/bin/bash

install_snap_packages() {
    local packages_file="$1"
    local line package package_info
    local -a installed_snaps=()
    local -a regular=()
    local -a classic=()
    local had_failure=false

    require_file "$packages_file"

    echo "Installing snap packages..."
    mapfile -t installed_snaps < <(snap list 2>/dev/null | awk 'NR > 1 { print $1 }')

    while IFS= read -r line; do
        package_info=$(echo "$line" | cut -d'#' -f1 | xargs)
        [[ -z "$package_info" ]] && continue

        if [[ "$package_info" == *"--classic"* ]]; then
            package=$(echo "$package_info" | sed 's/--classic//' | xargs)
            if contains_item "$package" "${installed_snaps[@]}"; then
                print_success "Already installed: $package"
            else
                classic+=("$package")
            fi
        else
            package="$package_info"
            if contains_item "$package" "${installed_snaps[@]}"; then
                print_success "Already installed: $package"
            else
                regular+=("$package")
            fi
        fi
    done < <(read_package_list "$packages_file")

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
                if contains_item "$package" "${installed_snaps[@]}"; then
                    print_success "Already installed: $package"
                    continue
                fi
                echo "Installing: $package"
                if sudo snap install "$package"; then
                    print_success "Successfully installed: $package"
                    installed_snaps+=("$package")
                else
                    print_error "Failed to install: $package"
                    had_failure=true
                fi
            done
        fi
    fi

    # Classic confinement cannot share an install transaction with regular snaps.
    for package in "${classic[@]}"; do
        echo "Installing: $package (classic)"
        if sudo snap install --classic "$package"; then
            print_success "Successfully installed: $package"
            installed_snaps+=("$package")
        else
            print_error "Failed to install: $package"
            had_failure=true
        fi
    done

    if [[ "$had_failure" == true ]]; then
        print_error "Snap installation completed with failures."
        return 1
    fi

    echo "Snap installation complete."
}
