#!/bin/bash

# Sync Neovim plugin specs bundled with the lazyvim installer into
# ~/.config/nvim/lua/plugins/ as symlinks, so edits in this repo propagate.
#
# Honors DRY_RUN=true. Usually invoked via the orchestrator
# (`installers/config/install.sh`); also runnable standalone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

TARGET="$HOME/.config/nvim"

apply_link "$REPO_ROOT/installers/lazyvim/plugins/vim-tmux-navigator.lua" \
           "$TARGET/lua/plugins/vim-tmux-navigator.lua"
