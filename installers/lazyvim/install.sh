#!/bin/bash

# LazyVim installer
# Installs Neovim (apt) along with the runtime dependencies LazyVim expects,
# and clones the LazyVim starter config into ~/.config/nvim.
# https://www.lazyvim.org/

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

NVIM_CONFIG="$HOME/.config/nvim"
NVIM_DATA="$HOME/.local/share/nvim"
NVIM_STATE="$HOME/.local/state/nvim"
NVIM_CACHE="$HOME/.cache/nvim"
LAZYVIM_STARTER_URL="https://github.com/LazyVim/starter"
BACKUP_SUFFIX="$(date +%Y%m%d-%H%M%S).bak"

# --- 1. Neovim + runtime dependencies LazyVim expects -----------------------
# Skipped intentionally: lazygit (optional, off by default in the starter),
# Node.js (LSP-specific; install via the codex installer or NodeSource on demand),
# a Nerd Font (graphical, install per-machine).
#
# Note: on older Ubuntu LTS releases apt's `neovim` may be older than LazyVim's
# stated >=0.9 requirement. If `nvim --version` reports <0.9 after install,
# install a newer build from https://github.com/neovim/neovim/releases.
install_deps() {
    echo "Installing Neovim and LazyVim runtime dependencies via apt..."
    if ! sudo apt install -y \
            neovim \
            ripgrep \
            fd-find \
            build-essential \
            unzip \
            curl \
            git \
            xclip; then
        print_error "Failed to install dependencies"
        return 1
    fi

    # Debian/Ubuntu ship fd as `fdfind` to avoid clashing with an older
    # package. Telescope and LazyVim look for `fd`, so add a shim if no
    # real `fd` is on PATH.
    if ! is_installed "fd"; then
        sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
    fi

    print_success "Installed runtime dependencies"
}

# --- 2. LazyVim starter config ----------------------------------------------
install_lazyvim_config() {
    # Idempotency: a LazyVim install always has lua/config/lazy.lua.
    if [ -f "$NVIM_CONFIG/lua/config/lazy.lua" ]; then
        print_success "LazyVim config already present at $NVIM_CONFIG"
        return 0
    fi

    for dir in "$NVIM_CONFIG" "$NVIM_DATA" "$NVIM_STATE" "$NVIM_CACHE"; do
        if [ -e "$dir" ]; then
            mv "$dir" "${dir}.${BACKUP_SUFFIX}"
            print_warning "Backed up $dir → ${dir}.${BACKUP_SUFFIX}"
        fi
    done

    echo "Cloning LazyVim starter to $NVIM_CONFIG..."
    mkdir -p "$(dirname "$NVIM_CONFIG")"
    if ! git clone --depth=1 "$LAZYVIM_STARTER_URL" "$NVIM_CONFIG"; then
        print_error "Failed to clone LazyVim starter"
        return 1
    fi
    # Drop the starter's git history so the user can `git init` their own.
    rm -rf "$NVIM_CONFIG/.git"

    # Drop in any plugin specs bundled with this installer.
    local plugin_src
    plugin_src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/plugins"
    if [ -d "$plugin_src" ]; then
        cp "$plugin_src"/*.lua "$NVIM_CONFIG/lua/plugins/"
        print_success "Added bundled plugin specs from $plugin_src"
    fi

    print_success "LazyVim starter cloned to $NVIM_CONFIG"
}

install_deps || exit 1
install_lazyvim_config || exit 1

print_success "LazyVim installation complete."
echo "  Next: run 'nvim'. The first launch syncs plugins; then run :LazyHealth"
echo "  to verify. A Nerd Font (e.g. JetBrainsMono) is recommended for icons."
