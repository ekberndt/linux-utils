#!/bin/bash

# tmux session-persistence plugins
# Clones the two plugins tmux.conf sources directly:
#   https://github.com/tmux-plugins/tmux-resurrect   save/restore the frame
#   https://github.com/tmux-plugins/tmux-continuum   do it on a timer
#
# tpm is deliberately absent. Its job is fetching and updating plugins, which
# is what this script does; re-running it updates them.

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

PLUGIN_DIR="${TMUX_PLUGIN_DIR:-$HOME/.tmux/plugins}"
PLUGINS=(
    "tmux-resurrect|https://github.com/tmux-plugins/tmux-resurrect"
    "tmux-continuum|https://github.com/tmux-plugins/tmux-continuum"
)

# tmux itself comes from apt_packages.txt via the apt installer; fetching two
# git repos does not justify making this step wait on a sudo prompt.
for tool in tmux git; do
    if ! is_installed "$tool"; then
        print_error "$tool is required; install it first (installers/installer.sh -a)"
        exit 1
    fi
done
print_success "Already installed: tmux ($(tmux -V))"

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

# tmux.conf only sources a plugin once it exists on disk, so a config sync that
# ran before this script left the plugins inert until the next reload.
if tmux info >/dev/null 2>&1; then
    if tmux source-file "$HOME/.config/tmux/tmux.conf" 2>/dev/null; then
        print_success "reloaded running tmux server"
    else
        print_warning "plugins installed; reload tmux with: tmux source-file ~/.config/tmux/tmux.conf"
    fi
fi
