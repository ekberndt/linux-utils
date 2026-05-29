#!/bin/bash

# Sync tmux config into ~/.cache only:
#   ~/.cache/tmux/tmux.conf
# to keep user-visible dotfiles in one place.
#
# Honors DRY_RUN=true. Usually invoked via the orchestrator
# (`installers/config/install.sh`); also runnable standalone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

SRC="$REPO_ROOT/tmux/tmux.conf"
DST="$HOME/.cache/tmux/tmux.conf"

apply_link "$SRC" "$DST"
