#!/bin/bash
set -euo pipefail

# Symlink the Neovim plugin specs bundled with the lazyvim installer so edits
# in this repo propagate. Honors DRY_RUN.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

apply_link "$REPO_ROOT/installers/lazyvim/plugins/vim-tmux-navigator.lua" \
           "$HOME/.config/nvim/lua/plugins/vim-tmux-navigator.lua"
