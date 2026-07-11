#!/bin/bash

# APT package installer
# Reads apt_packages.txt and installs specified apt packages

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/apt_packages.txt"

require_file "$PACKAGES_FILE"

# Parse one packages-file line. Optional lines start with "? ".
# PPA lines use "package | ppa:repo". Sets: package, optional, ppa.
parse_package_line() {
    local line="$1"
    optional=false
    package=""
    ppa=""

    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && return 1

    if [[ "$line" =~ ^\?[[:space:]]+(.*) ]]; then
        optional=true
        line="${BASH_REMATCH[1]}"
    fi

    if [[ "$line" =~ ^([^|#]+)\|[[:space:]]*ppa:([^#]+) ]]; then
        package=$(echo "${BASH_REMATCH[1]}" | xargs)
        ppa=$(echo "${BASH_REMATCH[2]}" | xargs)
    else
        package=$(echo "$line" | awk '{print $1}')
    fi

    [[ -n "$package" ]]
}

apt_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

install_apt_packages() {
    local -a pkgs=("$@")
    # One transaction: avoids N× "Reading package lists" / dep solves.
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -y "${pkgs[@]}"
}

echo "Installing apt packages..."

# Load once so interactive optional prompts never steal package lines from stdin.
mapfile -t package_lines < "$PACKAGES_FILE"

# Collect PPAs first
ppas=()
for line in "${package_lines[@]}"; do
    parse_package_line "$line" || continue
    if [[ -n "$ppa" ]]; then
        ppas+=("ppa:$ppa")
    fi
done

# Add PPAs if any exist
if [[ ${#ppas[@]} -gt 0 ]]; then
    echo "Adding ${#ppas[@]} PPAs..."
    for ppa in "${ppas[@]}"; do
        echo "Adding PPA: $ppa"
        sudo add-apt-repository -y "$ppa"
    done
    echo "Updating package lists after adding PPAs..."
    sudo apt-get update
fi

# Prompt only when stdout is a real terminal. Under the dashboard (and any
# piped run), stdout is a pipe: the prompt is invisible and read </dev/tty
# hangs forever after the last non-optional package (e.g. after "tree").
can_prompt_optional() {
    [[ -t 1 && -r /dev/tty && -w /dev/tty ]]
}

missing=()
for line in "${package_lines[@]}"; do
    parse_package_line "$line" || continue

    if $optional; then
        if ! can_prompt_optional; then
            echo "Skipping optional package (non-interactive): $package"
            continue
        fi
        # Prompt on the controlling terminal so package-list stdin cannot be stolen.
        read -r -p "Install optional package '$package'? [y/N] " response </dev/tty || response=n
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Skipping: $package"
            continue
        fi
    fi

    if apt_installed "$package"; then
        print_success "Already installed: $package"
    else
        missing+=("$package")
    fi
done

if ((${#missing[@]} == 0)); then
    echo "APT installation complete."
    exit 0
fi

echo "Installing ${#missing[@]} packages: ${missing[*]}"
if install_apt_packages "${missing[@]}"; then
    for package in "${missing[@]}"; do
        if apt_installed "$package"; then
            print_success "Successfully installed: $package"
        else
            # Virtual package names (e.g. libfuse2 → libfuse2t64) may not show under the requested name.
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
        fi
    done
fi

echo "APT installation complete."
