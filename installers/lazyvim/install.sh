#!/bin/bash

# LazyVim installer
# Installs stable Neovim and the runtime dependencies LazyVim expects, then
# clones the LazyVim starter config into ~/.config/nvim.
# https://www.lazyvim.org/

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

NVIM_CONFIG="$HOME/.config/nvim"
NVIM_DATA="$HOME/.local/share/nvim"
NVIM_STATE="$HOME/.local/state/nvim"
NVIM_CACHE="$HOME/.cache/nvim"
LAZYVIM_STARTER_URL="https://github.com/LazyVim/starter"
BACKUP_SUFFIX="$(date +%Y%m%d-%H%M%S).bak"
NERD_FONT_CASK="font-jetbrains-mono-nerd-font"
NERD_FONT_FAMILY="JetBrainsMono Nerd Font Mono"
TERMINAL_FONT_SIZE=13
LAZYVIM_FORMULAE=(
    neovim
    tree-sitter
)
BREW_CANDIDATES=(
    "/home/linuxbrew/.linuxbrew/bin/brew"
    "$HOME/.linuxbrew/bin/brew"
    "/opt/homebrew/bin/brew"
    "/usr/local/bin/brew"
)

# --- 1. Runtime dependencies LazyVim expects --------------------------------
# Skipped intentionally: lazygit (Homebrew formula in homebrew/brew_packages.txt),
# Node.js (LSP-specific; install via the codex installer or NodeSource on demand).

install_deps() {
    echo "Installing LazyVim runtime dependencies via apt..."
    if ! sudo apt-get install -y \
            ripgrep \
            fd-find \
            build-essential \
            unzip \
            curl \
            git \
            fontconfig \
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

font_family_installed() {
    local family="$1"
    fc-list : family |
        tr ',' '\n' |
        sed 's/^[[:space:]]*//; s/[[:space:]]*$//' |
        grep -Fxq "$family"
}

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

# --- 2. Stable editor + parser toolchain -------------------------------------
install_lazyvim_runtime() {
    local brew_path formula
    if ! brew_path="$(find_brew)"; then
        print_error "Homebrew is required to install LazyVim. Run installers/installer.sh --homebrew first."
        return 1
    fi

    for formula in "${LAZYVIM_FORMULAE[@]}"; do
        if "$brew_path" list --formula "$formula" >/dev/null 2>&1; then
            print_success "$formula already installed"
            continue
        fi

        echo "Installing $formula via Homebrew..."
        if ! "$brew_path" install "$formula"; then
            print_error "Failed to install $formula"
            return 1
        fi
    done

    # The distro package is too old for LazyVim and the unstable PPA ships
    # development snapshots. Homebrew's formula tracks Neovim releases.
    eval "$("$brew_path" shellenv)"
    hash -r

    if ! nvim --version | head -n1; then
        print_error "Installed Neovim, but nvim is not available on PATH"
        return 1
    fi
    print_success "Installed stable Neovim and Treesitter CLI"
}

# --- 3. Nerd Font ------------------------------------------------------------
install_nerd_font() {
    local brew_path
    brew_path="$(find_brew)"

    if "$brew_path" list --cask "$NERD_FONT_CASK" >/dev/null 2>&1; then
        print_success "$NERD_FONT_CASK already installed"
    elif font_family_installed "$NERD_FONT_FAMILY"; then
        print_success "$NERD_FONT_FAMILY already available"
    else
        echo "Installing $NERD_FONT_FAMILY via Homebrew..."
        if ! "$brew_path" install --cask "$NERD_FONT_CASK"; then
            print_error "Failed to install $NERD_FONT_CASK"
            return 1
        fi
    fi

    if ! fc-cache -f; then
        print_error "Failed to refresh font cache"
        return 1
    fi

    if ! font_family_installed "$NERD_FONT_FAMILY"; then
        print_error "Installed $NERD_FONT_CASK, but fontconfig cannot find $NERD_FONT_FAMILY"
        return 1
    fi

    print_success "Installed $NERD_FONT_FAMILY via Homebrew"
}

# --- 4. GNOME Terminal font selection ---------------------------------------
configure_gnome_terminal_font() {
    if ! is_installed "gsettings"; then
        return 0
    fi

    local font_setting="$NERD_FONT_FAMILY $TERMINAL_FONT_SIZE"
    if gsettings writable org.gnome.desktop.interface monospace-font-name >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface monospace-font-name "$font_setting"
        print_success "Configured GNOME monospace font"
    fi

    local profiles
    if ! profiles="$(gsettings get org.gnome.Terminal.ProfilesList list 2>/dev/null)"; then
        return 0
    fi

    local profile profile_schema
    for profile in $(echo "$profiles" | tr -d "[]',"); do
        profile_schema="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$profile/"
        gsettings set "$profile_schema" use-system-font false
        gsettings set "$profile_schema" font "$font_setting"
    done

    print_success "Configured GNOME Terminal font"
}

# --- 5. LazyVim starter config ----------------------------------------------
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

    # Symlink any plugin specs bundled with this installer so edits in the
    # repo propagate to ~/.config/nvim/lua/plugins/. The universal config
    # sync (installers/config/install.sh) re-applies the same links idempotently.
    local plugin_src
    plugin_src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/plugins"
    if [ -d "$plugin_src" ]; then
        mkdir -p "$NVIM_CONFIG/lua/plugins"
        for f in "$plugin_src"/*.lua; do
            [ -e "$f" ] || continue
            ln -sf "$f" "$NVIM_CONFIG/lua/plugins/$(basename "$f")"
        done
        print_success "Symlinked bundled plugin specs from $plugin_src"
    fi

    print_success "LazyVim starter cloned to $NVIM_CONFIG"
}

install_deps || exit 1
install_lazyvim_runtime || exit 1
install_nerd_font || exit 1
configure_gnome_terminal_font || exit 1
install_lazyvim_config || exit 1

print_success "LazyVim installation complete."
echo "  Next: run 'nvim'. The first launch syncs plugins; then run :LazyHealth"
echo "  to verify. For local use, open a new GNOME Terminal window so the font"
echo "  setting is applied. SSH clients render with their own local font."
