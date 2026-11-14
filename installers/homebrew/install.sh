#!/bin/bash
set -uo pipefail

# Homebrew plus the formulae and casks in brew_packages.txt (same role as
# apt_packages.txt / cargo_packages.txt).

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/brew_packages.txt"
BREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
BREW_DEPS=(build-essential procps curl file git)
BREW_PATH=""

install_dependencies() {
    if ! command -v apt-get >/dev/null 2>&1; then
        print_warning "apt-get not found; skipping Homebrew dependency installation"
        return 0
    fi
    echo "Installing Homebrew build dependencies..."
    if ! apt_install "${BREW_DEPS[@]}"; then
        print_error "Failed to install Homebrew build dependencies"
        exit 1
    fi
}

configure_shellenv() {
    local brew_path="$1"

    configure_shell_rcs "$brew_path shellenv" "# Homebrew" \
        "eval \"\$($brew_path shellenv)\""

    # Make brew available to this process (package install + PATH for children).
    eval "$("$brew_path" shellenv)"
}

# Sets BREW_PATH to a runnable brew binary, installing Homebrew if needed.
ensure_homebrew() {
    local brew_path

    if brew_path="$(find_brew)"; then
        configure_shellenv "$brew_path"
        print_success "Already installed: homebrew$(version_suffix "$brew_path")"
        BREW_PATH="$brew_path"
        return 0
    fi

    install_dependencies

    echo "Installing Homebrew..."
    if ! NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL "$BREW_INSTALL_URL")"; then
        print_error "Failed to install Homebrew"
        exit 1
    fi

    if ! brew_path="$(find_brew)"; then
        print_error "Homebrew installer finished, but no runnable brew binary was found"
        exit 1
    fi

    configure_shellenv "$brew_path"
    print_installed "homebrew$(version_suffix "$brew_path")"
    BREW_PATH="$brew_path"
}

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    print_error "Do not run the Homebrew installer as root. Run as your normal user; it uses sudo when needed."
    exit 1
fi

ensure_homebrew
install_brew_package_list "$BREW_PATH" "$PACKAGES_FILE"
