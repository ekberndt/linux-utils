#!/bin/bash

# Stable tmux and session-persistence plugins.
# Installs tmux from Homebrew, then clones the two plugins tmux.conf sources:
#   https://github.com/tmux-plugins/tmux-resurrect   save/restore the frame
#   https://github.com/tmux-plugins/tmux-continuum   do it on a timer
#
# tpm is deliberately absent. Its job is fetching and updating plugins, which
# is what this script does; re-running it updates them.

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

PLUGIN_DIR="${TMUX_PLUGIN_DIR:-$HOME/.tmux/plugins}"
BREW_CANDIDATES=(
    "/home/linuxbrew/.linuxbrew/bin/brew"
    "$HOME/.linuxbrew/bin/brew"
    "/opt/homebrew/bin/brew"
    "/usr/local/bin/brew"
)
PLUGINS=(
    "tmux-resurrect|https://github.com/tmux-plugins/tmux-resurrect"
    "tmux-continuum|https://github.com/tmux-plugins/tmux-continuum"
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

install_tmux() {
    local brew_path
    if ! brew_path="$(find_brew)"; then
        print_error "Homebrew is required to install tmux. Run installers/installer.sh --homebrew first."
        return 1
    fi

    if "$brew_path" list --formula tmux >/dev/null 2>&1; then
        print_success "tmux already installed via Homebrew"
    elif ! "$brew_path" install tmux; then
        print_error "Failed to install tmux"
        return 1
    fi

    eval "$("$brew_path" shellenv)"
    hash -r
    print_success "Installed stable tmux ($(tmux -V))"
}

refresh_boot_unit() {
    local unit="$HOME/.config/systemd/user/tmux.service"
    local generator="$PLUGIN_DIR/tmux-continuum/scripts/handle_tmux_automatic_start/systemd_enable.sh"
    local tmux_path backup

    [ -f "$unit" ] || return 0
    tmux_path="$(command -v tmux)"
    grep -Fq "ExecStart=$tmux_path " "$unit" && return 0

    backup="${unit}.bak.$(date +%Y%m%d-%H%M%S)"
    mv "$unit" "$backup"
    if "$generator" && systemctl --user daemon-reload; then
        print_success "updated tmux boot service to use $tmux_path"
        return 0
    fi

    mv "$backup" "$unit"
    systemctl --user daemon-reload
    print_error "Could not update $unit; restored the previous service"
    return 1
}

install_tmux || exit 1

if ! is_installed git; then
    print_error "git is required; install it first (installers/installer.sh -a)"
    exit 1
fi

# continuum's boot support is a systemd --user unit, which dies with the user
# manager unless this user lingers. Without it the last logout would run the
# unit's `ExecStop=tmux kill-server` and drop every detached session, so
# tmux.conf refuses to enable boot support until lingering is on.
if command -v loginctl >/dev/null 2>&1; then
    if [ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" = yes ]; then
        print_success "already lingering: $USER (tmux survives logout)"
    elif sudo loginctl enable-linger "$USER"; then
        print_success "enabled lingering: $USER (tmux survives logout)"
    else
        print_warning "could not enable lingering; tmux boot support stays off"
    fi
fi

mkdir -p "$PLUGIN_DIR"

failures=0
for entry in "${PLUGINS[@]}"; do
    IFS='|' read -r name url <<< "$entry"
    dest="$PLUGIN_DIR/$name"

    if [ -d "$dest/.git" ]; then
        # --ff-only so a plugin someone has patched locally fails loudly
        # instead of being silently merged.
        if git -C "$dest" pull --ff-only --quiet; then
            print_success "up to date: $name"
        else
            print_warning "could not update $name (local changes?)"
        fi
        continue
    fi

    if [ -e "$dest" ]; then
        print_error "$dest exists but is not a git checkout; remove it and re-run"
        failures=$((failures + 1))
        continue
    fi

    echo "Cloning $name..."
    if git clone --depth 1 --quiet "$url" "$dest"; then
        print_success "Successfully installed: $name"
    else
        print_error "Failed to clone $name"
        failures=$((failures + 1))
    fi
done

if (( failures > 0 )); then
    exit 1
fi

refresh_boot_unit || exit 1

# tmux.conf only sources a plugin once it exists on disk, so a config sync that
# ran before this script left the plugins inert until the next reload.
if tmux info >/dev/null 2>&1; then
    if tmux source-file "$HOME/.config/tmux/tmux.conf" 2>/dev/null; then
        print_success "reloaded running tmux server"
    else
        print_warning "plugins installed; reload tmux with: tmux source-file ~/.config/tmux/tmux.conf"
    fi
fi
