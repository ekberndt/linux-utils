#!/bin/bash

# tmux config installer
# Symlinks this repo's tmux.conf to ~/.config/tmux/tmux.conf so edits in
# either location stay in sync.

# shellcheck source=../installers/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../installers/lib" && pwd)/common.sh"

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tmux.conf"
DEST_DIR="$HOME/.config/tmux"
DEST="$DEST_DIR/tmux.conf"
BACKUP_SUFFIX="$(date +%Y%m%d-%H%M%S).bak"

require_file "$SRC"
mkdir -p "$DEST_DIR"

if [ -e "$DEST" ] || [ -L "$DEST" ]; then
    if [ -L "$DEST" ] && [ "$(readlink "$DEST")" = "$SRC" ]; then
        print_success "$DEST already symlinked to $SRC"
        exit 0
    fi
    mv "$DEST" "${DEST}.${BACKUP_SUFFIX}"
    print_warning "Backed up existing $DEST → ${DEST}.${BACKUP_SUFFIX}"
fi

if ! ln -s "$SRC" "$DEST"; then
    print_error "Failed to symlink $SRC → $DEST"
    exit 1
fi

print_success "Symlinked $DEST → $SRC"
