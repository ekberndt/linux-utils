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

python3 "${args[@]}"

if [[ "$DRY_RUN" == true ]]; then
    print_success "would reload AeroSpace config"
elif ! command -v aerospace >/dev/null 2>&1; then
    print_success "AeroSpace config updated (aerospace not installed; will apply on next start)"
elif aerospace reload-config; then
    print_success "reloaded AeroSpace config"
else
    print_warning "AeroSpace config updated, but reload failed"
fi

# AeroSpace binds window navigation to alt-* (Option). Five consecutive Option
# presses trigger macOS Accessibility's Mouse Keys shortcut, which activates
# NumLockKeyboardUsageMap on compact Apple keyboards and turns 789uiojklm into
# a numeric keypad.
if [[ "$DRY_RUN" == true ]]; then
    print_success "would disable macOS Mouse Keys and 5x-Option shortcut"
else
    defaults write com.apple.universalaccess mouseDriver -int 0
    defaults write com.apple.universalaccess useMouseKeysShortcutKeys -int 0
    if [[ "$(command -v defaults)" == /usr/bin/defaults ]]; then
        python3 -c 'import ctypes; ctypes.cdll.LoadLibrary("/usr/lib/libUniversalAccess.dylib")._UniversalAccessRestoreSystemState()'
    fi
    print_success "disabled macOS Mouse Keys and 5x-Option shortcut"
fi
