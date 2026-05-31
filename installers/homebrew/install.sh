#!/bin/bash

# Homebrew installer for Linux
# Installs Homebrew using the official installer and makes brew available to
# future shells.

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

BREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
BREW_DEPS=(build-essential procps curl file git)
BREW_CANDIDATES=(
    "/home/linuxbrew/.linuxbrew/bin/brew"
    "$HOME/.linuxbrew/bin/brew"
    "/opt/homebrew/bin/brew"
    "/usr/local/bin/brew"
)

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
}

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    print_error "Do not run the Homebrew installer as root. Run as your normal user; it uses sudo when needed."
    exit 1
fi

if brew_path="$(find_brew)"; then
    configure_shellenv "$brew_path"
    print_success "Already installed: homebrew ($("$brew_path" --version | head -n1))"
    exit 0
fi

install_dependencies

echo "Installing Homebrew..."
if NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL "$BREW_INSTALL_URL")"; then
    if brew_path="$(find_brew)"; then
        configure_shellenv "$brew_path"
        eval "$("$brew_path" shellenv)"
        print_success "Successfully installed: homebrew ($(brew --version | head -n1))"
    else
        print_error "Homebrew installer finished, but no runnable brew binary was found"
        exit 1
    fi
else
    print_error "Failed to install Homebrew"
    exit 1
fi
