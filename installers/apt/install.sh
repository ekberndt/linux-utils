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
    sudo apt update
fi

# Prompt only when stdout is a real terminal. Under the dashboard (and any
# piped run), stdout is a pipe: the prompt is invisible and read </dev/tty
# hangs forever after the last non-optional package (e.g. after "tree").
can_prompt_optional() {
    [[ -t 1 && -r /dev/tty && -w /dev/tty ]]
}

# Install packages one by one
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
done

echo "APT installation complete."
