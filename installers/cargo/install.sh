#!/bin/bash

# Cargo package installer
# Reads cargo_packages.txt and installs packages via Cargo.

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/cargo_packages.txt"
RUSTUP_INSTALL_URL="https://sh.rustup.rs"
CARGO_BIN_DIR="$HOME/.cargo/bin"
CARGO_PATH_LINE="export PATH=\"\$HOME/.cargo/bin:\$PATH\""
RUSTUP_BIN="$CARGO_BIN_DIR/rustup"
BUILD_DEPS=(build-essential curl)
RUSTUP_PATH=""

require_file "$PACKAGES_FILE"

find_rustup() {
    local path

    if path="$(command -v rustup 2>/dev/null)" && [[ -x "$path" ]]; then
        echo "$path"
        return 0
    fi

    if [[ -x "$RUSTUP_BIN" ]]; then
        echo "$RUSTUP_BIN"
        return 0
    fi

    return 1
}

ensure_profile_path() {
    local profile="$1"

    if ! touch "$profile"; then
        print_warning "Could not update $profile with Cargo bin path"
        return 1
    fi

    if grep -Fq ".cargo/bin" "$profile"; then
        return 0
    fi

    if ! {
        echo ""
        echo "# Cargo"
        echo "$CARGO_PATH_LINE"
    } >> "$profile"; then
        print_warning "Could not update $profile with Cargo bin path"
        return 1
    fi
}

configure_cargo_path() {
    ensure_profile_path "$HOME/.profile"
    ensure_profile_path "$HOME/.bashrc"

    if [[ "${SHELL:-}" == */zsh ]]; then
        ensure_profile_path "$HOME/.zprofile"
    fi

    case ":$PATH:" in
        *":$CARGO_BIN_DIR:"*) ;;
        *) export PATH="$CARGO_BIN_DIR:$PATH" ;;
    esac
}

install_build_deps() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "Installing Rust build dependencies..."
        if ! sudo apt-get install -y "${BUILD_DEPS[@]}"; then
            print_error "Failed to install Rust build dependencies"
            return 1
        fi
    elif ! command -v curl >/dev/null 2>&1; then
        print_error "curl is required to install Rustup"
        return 1
    fi
}

install_rustup() {
    install_build_deps || return 1

    echo "Installing Rustup..."
    if ! curl --proto '=https' --tlsv1.2 -sSf "$RUSTUP_INSTALL_URL" | sh -s -- -y --profile minimal --no-modify-path; then
        print_error "Failed to install Rustup"
        return 1
    fi
}

ensure_rust_toolchain() {
    if ! RUSTUP_PATH="$(find_rustup)"; then
        install_rustup || return 1
        RUSTUP_PATH="$RUSTUP_BIN"
    fi

    echo "Installing Rust stable toolchain..."
    if ! "$RUSTUP_PATH" toolchain install stable --profile minimal; then
        print_error "Failed to install Rust stable toolchain"
        return 1
    fi

    configure_cargo_path
}

# Parse "crate" or "crate:bin" from a package-list entry (comment already stripped).
# Sets globals: crate, bin.
parse_cargo_entry() {
    local entry="$1"
    crate=""
    bin=""

    if [[ "$entry" == *:* ]]; then
        crate="${entry%%:*}"
        bin="${entry#*:}"
    else
        crate="$entry"
        bin="$entry"
    fi

    [[ -n "$crate" && -n "$bin" ]]
}

cargo_binary_installed() {
    local bin="$1"

    is_installed "$bin" || [[ -x "$CARGO_BIN_DIR/$bin" ]]
}

install_cargo_package() {
    local crate="$1"
    local bin="$2"

    if cargo_binary_installed "$bin"; then
        print_success "Already installed: $bin"
        return 0
    fi

    echo "Installing: $crate"
    if "$RUSTUP_PATH" run stable cargo install "$crate"; then
        if cargo_binary_installed "$bin"; then
            print_success "Successfully installed: $bin"
            return 0
        fi
        print_error "cargo install $crate finished but binary '$bin' not found"
        return 1
    fi

    print_error "Failed to install: $crate"
    return 1
}

ensure_rust_toolchain || exit 1

echo "Installing Cargo packages..."

failures=()
while IFS= read -r line; do
    entry="$(echo "$line" | cut -d'#' -f1 | xargs)"
    [[ -z "$entry" ]] && continue

    parse_cargo_entry "$entry" || continue
    install_cargo_package "$crate" "$bin" || failures+=("$crate")
done < <(read_package_list "$PACKAGES_FILE")

if ((${#failures[@]})); then
    print_error "Failed Cargo packages: ${failures[*]}"
    exit 1
fi

echo "Cargo package installation complete."
