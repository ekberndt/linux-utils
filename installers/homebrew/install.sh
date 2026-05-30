#!/bin/bash

# Homebrew installer
# Installs Homebrew (the missing package manager) on Linux via the official
# install script, then prints the shellenv line needed to put brew on PATH.
# https://docs.brew.sh/Homebrew-on-Linux

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

# Standard Homebrew-on-Linux prefixes, in the order the installer prefers them.
BREW_PREFIXES=("/home/linuxbrew/.linuxbrew" "$HOME/.linuxbrew")

# Locate an existing brew binary, whether or not it is on PATH. New shells won't
# have brew on PATH until shellenv is sourced, so checking the prefixes catches
# an install that the current shell simply can't see yet.
find_brew() {
    if command -v brew >/dev/null 2>&1; then
        command -v brew
        return 0
    fi
    local prefix
    for prefix in "${BREW_PREFIXES[@]}"; do
        if [ -x "$prefix/bin/brew" ]; then
            echo "$prefix/bin/brew"
            return 0
        fi
    done
    return 1
}

if BREW_BIN="$(find_brew)"; then
    print_success "Already installed: brew ($("$BREW_BIN" --version | head -n1))"
    exit 0
fi

# Homebrew refuses to run as root and emits a confusing error if you try; fail early.
if [ "$(id -u)" -eq 0 ]; then
    print_error "Do not run the Homebrew installer as root. Run as your normal user; it uses sudo when needed."
    exit 1
fi

# Build dependencies Homebrew needs on Debian/Ubuntu before it can bottle or build formulae.
# https://docs.brew.sh/Homebrew-on-Linux#requirements
if command -v apt-get >/dev/null 2>&1; then
    echo "Installing Homebrew build dependencies..."
    if ! sudo apt-get install -y build-essential procps curl file git; then
        print_error "Failed to install Homebrew build dependencies"
        exit 1
    fi
fi

echo "Installing Homebrew..."
# NONINTERACTIVE=1 lets the official installer run without prompting, which the
# dashboard/non-tty runs driven by installer.sh require.
if ! NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
    print_error "Failed to install Homebrew"
    exit 1
fi

BREW_BIN="$(find_brew)"
if [ -z "$BREW_BIN" ]; then
    print_error "Homebrew install script finished but no brew binary was found"
    exit 1
fi

# Load brew into this shell so the version check below can find it.
eval "$("$BREW_BIN" shellenv)"
print_success "Successfully installed: brew ($(brew --version | head -n1))"

# brew is not on PATH for future shells until shellenv is sourced. We don't edit
# your shell profile (this repo keeps shell config user-managed) — add this line
# to ~/.bashrc (or ~/.profile) to make brew available in new shells.
BREW_PREFIX="$("$BREW_BIN" --prefix)"
echo -e "${BLUE}Next: add brew to your PATH for new shells by appending this to ~/.bashrc:${NC}"
echo "    eval \"\$(${BREW_PREFIX}/bin/brew shellenv)\""
