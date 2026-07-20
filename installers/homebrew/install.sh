#!/bin/bash

# Homebrew installer for Linux
# Installs Homebrew via the official installer, then formulae/casks listed in
# brew_packages.txt (same role as apt_packages.txt / cargo_packages.txt).

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/brew_packages.txt"
BREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
BREW_DEPS=(build-essential procps curl file git)
BREW_CANDIDATES=(
    "/home/linuxbrew/.linuxbrew/bin/brew"
    "$HOME/.linuxbrew/bin/brew"
    "/opt/homebrew/bin/brew"
    "/usr/local/bin/brew"
)

require_file "$PACKAGES_FILE"

find_brew() {
    local candidate path

    if path="$(command -v brew 2>/dev/null)" && [[ -x "$path" ]] && "$path" --version >/dev/null 2>&1; then
        echo "$path"
        return 0
    fi

    for candidate in "${BREW_CANDIDATES[@]}"; do
        if [[ -x "$candidate" ]] && "$candidate" --version >/dev/null 2>&1; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

install_dependencies() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "Installing Homebrew build dependencies..."
        if ! sudo apt-get install -y "${BREW_DEPS[@]}"; then
            print_error "Failed to install Homebrew build dependencies"
            exit 1
        fi
    else
        print_warning "apt-get not found; skipping Homebrew dependency installation"
    fi
}

ensure_shellenv_line() {
    local profile="$1"
    local brew_path="$2"
    local line="eval \"\$($brew_path shellenv)\""

    if ! touch "$profile"; then
        print_warning "Could not update $profile with Homebrew shellenv"
        return 1
    fi

    if grep -Fq "$brew_path shellenv" "$profile"; then
        return 0
    fi

    if ! {
        echo ""
        echo "# Homebrew"
        echo "$line"
    } >> "$profile"; then
        print_warning "Could not update $profile with Homebrew shellenv"
        return 1
    fi
}

configure_shellenv() {
    local brew_path="$1"

    ensure_shellenv_line "$HOME/.profile" "$brew_path"
    ensure_shellenv_line "$HOME/.bashrc" "$brew_path"

    if [[ "${SHELL:-}" == */zsh ]]; then
        ensure_shellenv_line "$HOME/.zprofile" "$brew_path"
    fi

    # Make brew available to this process (package install + PATH for children).
    eval "$("$brew_path" shellenv)"
}

# Sets BREW_PATH to a runnable brew binary (installs Homebrew if needed).
ensure_homebrew() {
    local brew_path

    if brew_path="$(find_brew)"; then
        configure_shellenv "$brew_path"
        print_success "Already installed: homebrew ($("$brew_path" --version | head -n1))"
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
    print_success "Successfully installed: homebrew ($(brew --version | head -n1))"
    BREW_PATH="$brew_path"
}

# Parse one package-list line into PACKAGE / IS_CASK (true|false).
# Strips trailing comments; supports optional --cask (snap-style flag).
parse_brew_line() {
    local raw="$1"
    local package_info

    package_info="$(echo "$raw" | cut -d'#' -f1 | xargs)"
    [[ -z "$package_info" ]] && return 1

    if [[ "$package_info" == *"--cask"* ]]; then
        PACKAGE="$(echo "$package_info" | sed 's/--cask//' | xargs)"
        IS_CASK=true
    else
        PACKAGE="$package_info"
        IS_CASK=false
    fi
    [[ -n "$PACKAGE" ]]
}

is_brew_pkg_installed() {
    local brew_path="$1"
    local package="$2"
    local is_cask="$3"
    local installed

    if [[ "$is_cask" == true ]]; then
        for installed in "${installed_casks[@]}"; do
            [[ "$installed" == "$package" ]] && return 0
        done
    else
        for installed in "${installed_formulae[@]}"; do
            [[ "$installed" == "$package" ]] && return 0
        done
    fi
    return 1
}

install_brew_packages() {
    local brew_path="$1"
    local package is_cask
    local -a formulae=()
    local -a casks=()
    local had_failure=false

    mapfile -t installed_formulae < <("$brew_path" list --formula 2>/dev/null)
    mapfile -t installed_casks < <("$brew_path" list --cask 2>/dev/null)

    echo "Installing Homebrew packages..."

    while IFS= read -r line; do
        PACKAGE=""
        IS_CASK=false
        parse_brew_line "$line" || continue
        package="$PACKAGE"
        is_cask="$IS_CASK"

        if is_brew_pkg_installed "$brew_path" "$package" "$is_cask"; then
            print_success "Already installed: $package"
            continue
        fi

        if [[ "$is_cask" == true ]]; then
            casks+=("$package")
        else
            formulae+=("$package")
        fi
    done < <(read_package_list "$PACKAGES_FILE")

    if ((${#formulae[@]})); then
        echo "Installing ${#formulae[@]} formulae: ${formulae[*]}"
        if "$brew_path" install "${formulae[@]}"; then
            for package in "${formulae[@]}"; do
                print_success "Successfully installed: $package"
                installed_formulae+=("$package")
            done
        else
            print_warning "Batch brew formula install failed; retrying individually..."
            for package in "${formulae[@]}"; do
                if is_brew_pkg_installed "$brew_path" "$package" false; then
                    print_success "Already installed: $package"
                    continue
                fi
                echo "Installing: $package"
                if "$brew_path" install "$package"; then
                    print_success "Successfully installed: $package"
                    installed_formulae+=("$package")
                else
                    print_error "Failed to install: $package"
                    had_failure=true
                fi
            done
        fi
    fi

    if ((${#casks[@]})); then
        echo "Installing ${#casks[@]} casks: ${casks[*]}"
        if "$brew_path" install --cask "${casks[@]}"; then
            for package in "${casks[@]}"; do
                print_success "Successfully installed: $package"
                installed_casks+=("$package")
            done
        else
            print_warning "Batch brew cask install failed; retrying individually..."
            for package in "${casks[@]}"; do
                if is_brew_pkg_installed "$brew_path" "$package" true; then
                    print_success "Already installed: $package"
                    continue
                fi
                echo "Installing: $package (cask)"
                if "$brew_path" install --cask "$package"; then
                    print_success "Successfully installed: $package"
                    installed_casks+=("$package")
                else
                    print_error "Failed to install: $package"
                    had_failure=true
                fi
            done
        fi
    fi

    if $had_failure; then
        print_error "Homebrew package installation completed with failures."
        exit 1
    fi

    echo "Homebrew package installation complete."
}

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    print_error "Do not run the Homebrew installer as root. Run as your normal user; it uses sudo when needed."
    exit 1
fi

BREW_PATH=""
ensure_homebrew
install_brew_packages "$BREW_PATH"
