#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/brew.txt"
AEROSPACE_SOURCE="$SCRIPT_DIR/.aerospace.toml"
AEROSPACE_TARGET="$HOME/.aerospace.toml"

print_success() { echo "✓ $1"; }
print_error() { echo "✗ $1" >&2; }

install_formula() {
    local package="$1"

    if brew list --formula "$package" >/dev/null 2>&1; then
        print_success "Already installed: $package"
    elif brew install "$package"; then
        print_success "Successfully installed: $package"
    else
        print_error "Failed to install: $package"
        return 1
    fi
}

install_cask() {
    local package="$1"

    if brew list --cask "$package" >/dev/null 2>&1; then
        print_success "Already installed: $package"
    elif brew install --cask "$package"; then
        print_success "Successfully installed: $package"
    else
        print_error "Failed to install: $package"
        return 1
    fi
}

install_packages() {
    local line entry package had_failure=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        entry="$(printf '%s' "${line%%#*}" | xargs)"
        [[ -z "$entry" ]] && continue

        if [[ "$entry" == *" --cask" ]]; then
            package="${entry% --cask}"
            install_cask "$package" || had_failure=true
        else
            install_formula "$entry" || had_failure=true
        fi
    done < "$PACKAGES_FILE"

    [[ "$had_failure" == false ]]
}

install_aerospace_config() {
    local backup

    if [[ -L "$AEROSPACE_TARGET" ]] &&
        [[ "$(readlink "$AEROSPACE_TARGET")" == "$AEROSPACE_SOURCE" ]]; then
        print_success "Already linked: $AEROSPACE_TARGET"
        return
    fi

    if [[ -e "$AEROSPACE_TARGET" || -L "$AEROSPACE_TARGET" ]]; then
        backup="$AEROSPACE_TARGET.bak.$(date +%Y%m%d-%H%M%S)"
        mv "$AEROSPACE_TARGET" "$backup"
        echo "Backed up existing config: $backup"
    fi

    ln -s "$AEROSPACE_SOURCE" "$AEROSPACE_TARGET"
    print_success "Linked: $AEROSPACE_TARGET"
}

if [[ "$(uname -s)" != Darwin ]]; then
    print_error "The macOS installer must run on macOS."
    exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
    print_error "Homebrew is required: https://brew.sh"
    exit 1
fi

if ! install_packages; then
    print_error "Package installation completed with failures."
    exit 1
fi

install_aerospace_config
