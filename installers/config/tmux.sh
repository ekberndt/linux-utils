#!/bin/bash

# Sync tmux config into both paths tmux commonly reads:
#   ~/.tmux.conf
#   ~/.config/tmux/tmux.conf
# so edits in either location stay in sync.
#
# Honors DRY_RUN=true. Usually invoked via the orchestrator
# (`installers/config/install.sh`); also runnable standalone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

SRC="$REPO_ROOT/tmux/tmux.conf"

apply_link "$SRC" "$HOME/.tmux.conf"
apply_link "$SRC" "$HOME/.config/tmux/tmux.conf"
