#!/bin/bash
set -euo pipefail

# Write ~/.aerospace.toml from the tracked generic config plus the untracked
# app-to-workspace mapping. Honors DRY_RUN, AEROSPACE_TOML, and
# AEROSPACE_WORKSPACES. No-op off macOS.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

if [[ "$(uname -s)" != Darwin ]]; then
    print_warning "skipping AeroSpace config (not macOS)"
    exit 0
fi

target="${AEROSPACE_TOML:-$HOME/.aerospace.toml}"
source_toml="$REPO_ROOT/macos/.aerospace.toml"
mapping="${AEROSPACE_WORKSPACES:-$REPO_ROOT/macos/app-workspaces.cfg}"

args=("$REPO_ROOT/scripts/aerospace-workspaces" "$source_toml" "$target")
if [[ -f "$mapping" ]]; then
    args+=("$mapping")
else
    print_warning "no app-workspace mapping at $mapping (copy macos/app-workspaces.cfg.example)"
fi

result="$(python3 "${args[@]}")"
echo "$result"
if [[ "$DRY_RUN" == false && "$result" != *"already current: "* ]]; then
    record_status updated "$target"
fi

if [[ "$DRY_RUN" == true ]]; then
    print_success "would reload AeroSpace config"
elif ! command -v aerospace >/dev/null 2>&1; then
    print_success "AeroSpace config updated (aerospace not installed; will apply on next start)"
elif aerospace reload-config; then
    print_success "reloaded AeroSpace config"
else
    print_warning "AeroSpace config updated, but reload failed"
fi

disable_mouse_keys() {
    local domain=com.apple.universalaccess key

    # Five Option presses toggle Mouse Keys (numpad mode), colliding with alt-* chords.
    for key in mouseDriver useMouseKeysShortcutKeys; do
        [[ "$(defaults read "$domain" "$key" 2>/dev/null)" == 0 ]] && continue
        if ! defaults write "$domain" "$key" -int 0; then
            print_warning "could not disable macOS Mouse Keys"
            return
        fi
    done
}

configure_aerospace_defaults() {
    local animations
    animations="$(defaults read NSGlobalDomain NSAutomaticWindowAnimationsEnabled 2>/dev/null || true)"
    if [[ "$animations" != 0 && "$animations" != false ]]; then
        if ! defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false; then
            print_warning "could not disable macOS window-open animations"
        fi
    fi

    if [[ "$(defaults read bobko.aerospace displayStyle 2>/dev/null || true)" != i3Ordered ]]; then
        if ! defaults write bobko.aerospace displayStyle -string i3Ordered; then
            print_warning "could not set AeroSpace menu bar style"
        fi
    fi
}

if [[ "$DRY_RUN" != true ]]; then
    disable_mouse_keys
    configure_aerospace_defaults
fi
