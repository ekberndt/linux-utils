#!/bin/bash

# zoxide installer
# Installs zoxide via the official install script and configures Bash init.
# https://github.com/ajeetdsouza/zoxide#installation

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

ZOXIDE_INSTALL_URL="https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh"
ZOXIDE_BIN_DIR="$HOME/.local/bin"
# Official install script default; keep PATH in sync for future shells.
# Literals written into profile files — expand at shell-read time, not here.
PATH_LINE="export PATH=\"\$HOME/.local/bin:\$PATH\""
BASHRC="$HOME/.bashrc"
# Must match README: eval "$(zoxide init bash)" at the end of the shell config.
INIT_LINE="eval \"\$(zoxide init bash)\""

find_zoxide() {
    local path

    if path="$(command -v zoxide 2>/dev/null)" && [[ -x "$path" ]]; then
        echo "$path"
        return 0
    fi

    if [[ -x "$ZOXIDE_BIN_DIR/zoxide" ]]; then
        echo "$ZOXIDE_BIN_DIR/zoxide"
        return 0
    fi

    return 1
}

ensure_local_bin_path() {
    local profile="$1"

    if ! touch "$profile"; then
        print_warning "Could not update $profile with ~/.local/bin PATH"
        return 1
    fi

    if grep -Fq '.local/bin' "$profile"; then
        return 0
    fi

    if ! {
        echo ""
        echo "# zoxide binary path (~/.local/bin)"
        echo "$PATH_LINE"
    } >> "$profile"; then
        print_warning "Could not update $profile with ~/.local/bin PATH"
        return 1
    fi
}

configure_path() {
    ensure_local_bin_path "$HOME/.profile"
    ensure_local_bin_path "$BASHRC"

    case ":$PATH:" in
        *":$ZOXIDE_BIN_DIR:"*) ;;
        *) export PATH="$ZOXIDE_BIN_DIR:$PATH" ;;
    esac
}

# Append README-recommended Bash init at the end of ~/.bashrc (idempotent).
configure_bash() {
    if ! touch "$BASHRC"; then
        print_error "Could not update $BASHRC with zoxide init"
        return 1
    fi

    if grep -Fq 'zoxide init bash' "$BASHRC"; then
        print_success "already configured: $BASHRC"
        return 0
    fi

    if ! {
        echo ""
        echo "# zoxide (https://github.com/ajeetdsouza/zoxide)"
        echo "$INIT_LINE"
    } >> "$BASHRC"; then
        print_error "Could not update $BASHRC with zoxide init"
        return 1
    fi

    print_success "added zoxide init: $BASHRC"
}

install_zoxide() {
    echo "Installing zoxide..."
    if ! curl -sSfL "$ZOXIDE_INSTALL_URL" | sh; then
        print_error "Failed to install zoxide"
        return 1
    fi
}

if zoxide_path="$(find_zoxide)"; then
    configure_path
    configure_bash || exit 1
    print_success "Already installed: zoxide ($("$zoxide_path" --version 2>/dev/null | head -n1))"
    exit 0
fi

install_zoxide || exit 1
configure_path

if ! zoxide_path="$(find_zoxide)"; then
    print_error "Install script finished but zoxide not found on PATH"
    exit 1
fi

configure_bash || exit 1
print_success "Successfully installed: zoxide ($("$zoxide_path" --version 2>/dev/null | head -n1))"
