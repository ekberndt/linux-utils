#!/bin/bash

install_flatpak_packages() {
    local packages_file="$1"
    local app_id line
    local -a installed_apps=()
    local -a missing=()
    local had_failure=false

    require_file "$packages_file"

    if ! is_installed "flatpak"; then
        echo "Flatpak not found. Installing flatpak..."
        if run_as_root apt-get install -y flatpak; then
            print_success "Successfully installed flatpak"
        else
            print_error "Failed to install flatpak"
            return 1
        fi
    fi

    # User-scope installs avoid polkit. System installs still count as present.
    flatpak remote-add --user --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo

    echo "Installing flatpak packages (user scope)..."
    mapfile -t installed_apps < <(flatpak list --app --columns=application 2>/dev/null)

    while IFS= read -r line; do
        app_id=$(echo "$line" | cut -d'#' -f1 | xargs)
        [[ -z "$app_id" ]] && continue

        if contains_item "$app_id" "${installed_apps[@]}"; then
            print_success "Already installed: $app_id"
        else
            missing+=("$app_id")
        fi
    done < <(read_package_list "$packages_file")

    if ((${#missing[@]} == 0)); then
        echo "Flatpak installation complete."
        return 0
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
            if contains_item "$app_id" "${installed_apps[@]}"; then
                print_success "Already installed: $app_id"
                continue
            fi
            echo "Installing: $app_id"
            if flatpak install --user -y flathub "$app_id"; then
                print_success "Successfully installed: $app_id"
                installed_apps+=("$app_id")
            else
                print_error "Failed to install: $app_id"
                had_failure=true
            fi
        done
    fi

    if [[ "$had_failure" == true ]]; then
        print_error "Flatpak installation completed with failures."
        return 1
    fi

    echo "Flatpak installation complete."
}
