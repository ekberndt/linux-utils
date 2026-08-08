#!/bin/bash

apt_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

install_apt_packages() {
    local -a packages=("$@")

    # One transaction avoids repeating package-list reads and dependency solves.
    run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
}

install_apt_package_list() {
    local packages_file="$1"
    local line package ppa
    local -a package_lines=()
    local -a ppas=()
    local -a missing=()
    local had_failure=false

    require_file "$packages_file"

    echo "Installing apt packages..."
    # Load once so later processing cannot re-read a mutated file mid-install.
    mapfile -t package_lines < "$packages_file"

    for line in "${package_lines[@]}"; do
        parse_package_line "$line" || continue
        if [[ -n "$ppa" ]]; then
            ppas+=("ppa:$ppa")
        fi
    done

    if ((${#ppas[@]})); then
        echo "Adding ${#ppas[@]} PPAs..."
        for ppa in "${ppas[@]}"; do
            echo "Adding PPA: $ppa"
            run_as_root add-apt-repository -y "$ppa"
        done
        echo "Updating package lists after adding PPAs..."
        run_as_root apt-get update
    fi

    for line in "${package_lines[@]}"; do
        parse_package_line "$line" || continue
        if apt_installed "$package"; then
            print_success "Already installed: $package"
        else
            missing+=("$package")
        fi
    done

    if ((${#missing[@]} == 0)); then
        echo "APT installation complete."
        return 0
    fi

    echo "Installing ${#missing[@]} packages: ${missing[*]}"
    if install_apt_packages "${missing[@]}"; then
        for package in "${missing[@]}"; do
            if apt_installed "$package"; then
                print_success "Successfully installed: $package"
            else
                # Virtual package names may resolve under a different installed name.
                print_success "Installed: $package"
            fi
        done
    else
        print_warning "Batch install failed; retrying packages individually..."
        for package in "${missing[@]}"; do
            if apt_installed "$package"; then
                print_success "Already installed: $package"
                continue
            fi
            echo "Installing: $package"
            if install_apt_packages "$package"; then
                print_success "Successfully installed: $package"
            else
                print_error "Failed to install: $package"
                had_failure=true
            fi
        done
    fi

    if [[ "$had_failure" == true ]]; then
        print_error "APT installation completed with failures."
        return 1
    fi

    echo "APT installation complete."
}
