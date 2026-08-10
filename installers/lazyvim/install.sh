#!/bin/bash
set -uo pipefail

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
    tree-sitter-cli
)

install_deps() {
    local packages=(
        ripgrep
        fd-find
        build-essential
        unzip
        curl
        git
    )
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        packages+=(fontconfig xclip)
    fi

    echo "Installing LazyVim runtime dependencies via apt..."
    if ! apt_install "${packages[@]}"; then
        print_error "Failed to install dependencies"
        return 1
    fi

    # Debian names this binary fdfind; LazyVim expects fd.
    if ! is_installed "fd"; then
        run_as_root ln -sf "$(command -v fdfind)" /usr/local/bin/fd
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

install_homebrew_runtime() {
    local brew_path formula
    if ! brew_path="$(find_brew)"; then
        print_error "Homebrew is required to install LazyVim. Run 'installers/installer.sh homebrew' first."
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

    eval "$("$brew_path" shellenv)"
    hash -r

    if ! nvim --version | head -n1; then
        print_error "Installed Neovim, but nvim is not available on PATH"
        return 1
    fi
    print_success "Installed stable Neovim and Treesitter CLI"
}

install_root_runtime() {
    local asset_arch install_dir archive url
    case "$(uname -m)" in
        x86_64) asset_arch="x86_64" ;;
        aarch64|arm64) asset_arch="arm64" ;;
        *)
            print_error "Unsupported architecture: $(uname -m)"
            return 1
            ;;
    esac

    install_dir="/opt/nvim-linux-$asset_arch"
    url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-$asset_arch.tar.gz"

    if [[ ! -x "$install_dir/bin/nvim" ]]; then
        archive="$(mktemp)"
        echo "Installing the latest stable Neovim release..."
        if ! curl -fsSL "$url" -o "$archive" || \
           ! run_as_root tar -xzf "$archive" -C /opt; then
            rm -f -- "$archive"
            print_error "Failed to install Neovim"
            return 1
        fi
        rm -f -- "$archive"
    fi
    run_as_root ln -sf "$install_dir/bin/nvim" /usr/local/bin/nvim

    if ! is_installed tree-sitter; then
        if ! is_installed npm; then
            print_error "npm is required; run 'installers/installer.sh codex' first"
            return 1
        fi
        echo "Installing tree-sitter-cli via npm..."
        run_as_root npm install -g tree-sitter-cli || return 1
    fi

    if ! nvim --version | head -n1; then
        print_error "Installed Neovim, but nvim is not available on PATH"
        return 1
    fi
    print_success "Installed stable Neovim and Treesitter CLI"
}

install_lazyvim_runtime() {
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        install_root_runtime
    else
        install_homebrew_runtime
    fi
}

remove_shadowed_treesitter_cli() {
    local mason_root="$NVIM_DATA/mason"
    local removed=false

    if [ -L "$mason_root/bin/tree-sitter" ]; then
        rm "$mason_root/bin/tree-sitter"
        removed=true
    fi
    if [ -d "$mason_root/packages/tree-sitter-cli" ]; then
        rm -rf -- "$mason_root/packages/tree-sitter-cli"
        removed=true
    fi

    if [ "$removed" = true ]; then
        print_success "Removed the Mason Treesitter CLI that shadowed the system CLI"
    fi
}

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

configure_gnome_terminal_font() {
    if ! is_installed "gsettings"; then
        return 0
    fi

    local font_setting="$NERD_FONT_FAMILY $TERMINAL_FONT_SIZE"
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

install_lazyvim_config() {
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
    rm -rf "$NVIM_CONFIG/.git"

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
remove_shadowed_treesitter_cli
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    install_nerd_font || exit 1
    configure_gnome_terminal_font || exit 1
fi
install_lazyvim_config || exit 1

print_success "LazyVim installation complete."
echo "  Next: run 'nvim'. The first launch syncs plugins; then run :LazyHealth"
echo "  to verify. SSH clients render with their own local font."
