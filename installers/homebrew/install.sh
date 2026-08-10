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

require_file "$PACKAGES_FILE"

brew_install_formula() { "$BREW_PATH" install "$@"; }
brew_install_cask() { "$BREW_PATH" install --cask "$@"; }
brew_formula_installed() { "$BREW_PATH" list --formula "$1" >/dev/null 2>&1; }
brew_cask_installed() { "$BREW_PATH" list --cask "$1" >/dev/null 2>&1; }

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
    print_success "Successfully installed: homebrew$(version_suffix "$brew_path")"
    BREW_PATH="$brew_path"
}

# Manifest extra: "--cask" installs a cask rather than a formula.
install_brew_packages() {
    local line entry package
    local -a installed_formulae=() installed_casks=() formulae=() casks=()
    local had_failure=false

    mapfile -t installed_formulae < <("$BREW_PATH" list --formula 2>/dev/null)
    mapfile -t installed_casks < <("$BREW_PATH" list --cask 2>/dev/null)

    echo "Installing Homebrew packages..."

    while IFS= read -r line; do
        entry="$(package_entry "$line")"
        [[ -z "$entry" ]] && continue

        package="${entry/--cask/}"
        package="$(echo "$package" | xargs)"

        if [[ "$entry" == *"--cask"* ]]; then
            if contains_item "$package" "${installed_casks[@]}"; then
                print_success "Already installed: $package"
            else
                casks+=("$package")
            fi
        elif contains_item "$package" "${installed_formulae[@]}"; then
            print_success "Already installed: $package"
        else
            formulae+=("$package")
        fi
    done < <(read_package_list "$PACKAGES_FILE")

    install_batch "formulae" brew_install_formula brew_formula_installed \
        "${formulae[@]}" || had_failure=true
    install_batch "casks" brew_install_cask brew_cask_installed \
        "${casks[@]}" || had_failure=true

    if [[ "$had_failure" == true ]]; then
        print_error "Homebrew package installation completed with failures."
        exit 1
    fi
    echo "Homebrew package installation complete."
}

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    print_error "Do not run the Homebrew installer as root. Run as your normal user; it uses sudo when needed."
    exit 1
fi

ensure_homebrew
install_brew_packages
