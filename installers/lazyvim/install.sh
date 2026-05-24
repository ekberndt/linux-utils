#!/bin/bash

# LazyVim installer
# Installs Neovim (from the official prebuilt tarball), the runtime
# dependencies LazyVim expects, and clones the LazyVim starter config
# into ~/.config/nvim.
# https://www.lazyvim.org/

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

NVIM_INSTALL_DIR="/opt/nvim"
NVIM_BIN_LINK="/usr/local/bin/nvim"
NVIM_CONFIG="$HOME/.config/nvim"
NVIM_DATA="$HOME/.local/share/nvim"
NVIM_STATE="$HOME/.local/state/nvim"
NVIM_CACHE="$HOME/.cache/nvim"
LAZYVIM_STARTER_URL="https://github.com/LazyVim/starter"
BACKUP_SUFFIX="$(date +%Y%m%d-%H%M%S).bak"

# --- 1. Neovim from official tarball ----------------------------------------
# Ubuntu's apt nvim lags behind LazyVim's >=0.9 requirement on most LTS releases.
install_neovim() {
    if is_installed "nvim"; then
        print_success "Already installed: $(nvim --version | head -n1)"
        return 0
    fi

    local nvim_arch
    case "$(uname -m)" in
        x86_64) nvim_arch="x86_64" ;;
        aarch64|arm64) nvim_arch="arm64" ;;
        *) print_error "Unsupported architecture: $(uname -m)"; return 1 ;;
    esac

    local tarball="nvim-linux-${nvim_arch}.tar.gz"
    local url="https://github.com/neovim/neovim/releases/latest/download/${tarball}"
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN

    echo "Downloading Neovim (${nvim_arch}) from ${url}..."
    if ! curl -fsSL "$url" -o "${tmp}/${tarball}"; then
        print_error "Failed to download Neovim"
        return 1
    fi

    echo "Extracting to ${NVIM_INSTALL_DIR}..."
    sudo rm -rf "$NVIM_INSTALL_DIR"
    sudo mkdir -p "$NVIM_INSTALL_DIR"
    if ! sudo tar -xzf "${tmp}/${tarball}" -C "$NVIM_INSTALL_DIR" --strip-components=1; then
        print_error "Failed to extract Neovim"
        return 1
    fi

    sudo ln -sf "${NVIM_INSTALL_DIR}/bin/nvim" "$NVIM_BIN_LINK"
    print_success "Installed $(nvim --version | head -n1)"
}

# --- 2. Runtime dependencies LazyVim expects --------------------------------
# Skipped intentionally: lazygit (optional, off by default in the starter),
# Node.js (LSP-specific; install via the codex installer or NodeSource on demand),
# a Nerd Font (graphical, install per-machine).
install_runtime_deps() {
    echo "Installing LazyVim runtime dependencies via apt..."
    if ! sudo apt install -y \
            ripgrep \
            fd-find \
            build-essential \
            unzip \
            curl \
            git \
            xclip; then
        print_error "Failed to install runtime dependencies"
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

# --- 3. LazyVim starter config ----------------------------------------------
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

install_neovim || exit 1
install_runtime_deps || exit 1
install_lazyvim_config || exit 1

print_success "LazyVim installation complete."
echo "  Next: run 'nvim'. The first launch syncs plugins; then run :LazyHealth"
echo "  to verify. A Nerd Font (e.g. JetBrainsMono) is recommended for icons."
