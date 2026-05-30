#!/bin/bash

# Sync tmux config into tmux's XDG config location:
#   ~/.config/tmux/tmux.conf
#
# Honors DRY_RUN=true. Usually invoked via the orchestrator
# (`installers/config/install.sh`); also runnable standalone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

SRC="$REPO_ROOT/tmux/tmux.conf"
DST="$HOME/.config/tmux/tmux.conf"

apply_link "$SRC" "$DST"

if [ "${DRY_RUN:-false}" = true ]; then
    print_success "would reload tmux config: tmux source-file $DST"
elif command -v tmux >/dev/null 2>&1; then
    if tmux source-file "$DST"; then
        print_success "reloaded tmux config"
    else
        print_warning "tmux config linked, but reload failed"
    fi
else
    print_warning "tmux not installed; skipped reload"
fi
