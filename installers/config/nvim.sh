#!/bin/bash
set -euo pipefail

# Symlink every Neovim plugin spec bundled with the lazyvim installer so edits
# in this repo propagate. Honors DRY_RUN.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

plugin_src="$REPO_ROOT/installers/lazyvim/plugins"
for f in "$plugin_src"/*.lua; do
    [ -e "$f" ] || continue
    apply_link "$f" "$HOME/.config/nvim/lua/plugins/$(basename "$f")"
done
