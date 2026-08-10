#!/bin/bash
set -euo pipefail

# Link tmux.conf into tmux's XDG location and reload a running server.
# Honors DRY_RUN.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

DST="$HOME/.config/tmux/tmux.conf"

apply_link "$REPO_ROOT/tmux/tmux.conf" "$DST"

if [[ "$DRY_RUN" == true ]]; then
    print_success "would reload tmux config: tmux source-file $DST"
elif ! command -v tmux >/dev/null 2>&1; then
    print_warning "tmux not installed; skipped reload"
elif ! tmux info >/dev/null 2>&1; then
    print_success "tmux config linked (no server running; will apply on next start)"
elif tmux source-file "$DST"; then
    print_success "reloaded tmux config"
else
    print_warning "tmux config linked, but reload failed"
fi
