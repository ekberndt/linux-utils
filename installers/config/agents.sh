#!/bin/bash

# Sync shared agent scripts into ~/.agents/ as symlinks and remove per-tool
# script directories so agent commands have one shared home.
#
# Honors DRY_RUN=true and AGENTS_CONFIG_DIR. Usually invoked via the
# orchestrator (`installers/config/install.sh`); also runnable standalone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

TARGET="${AGENTS_CONFIG_DIR:-$HOME/.agents}"
CLAUDE_TARGET="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CODEX_TARGET="${CODEX_CONFIG_DIR:-$HOME/.codex}"

# Keep helper scripts executable in this checkout
# (git tracks the +x bit, but a fresh editor write may drop it).
if [ "${DRY_RUN:-false}" = false ]; then
    chmod +x \
             "$REPO_ROOT/scripts/agent-fanout" \
             "$REPO_ROOT/scripts/statusline-worktree" 2>/dev/null || true
fi

apply_link "$REPO_ROOT/scripts/agent-fanout"              "$TARGET/scripts/agent-fanout"
apply_link "$REPO_ROOT/scripts/statusline-worktree"        "$TARGET/scripts/statusline-worktree"

remove_script_dir() {
    local dir="$1"
    local dry_run="${DRY_RUN:-false}"

    if [ ! -e "$dir" ] && [ ! -L "$dir" ]; then
        return 0
    fi

    if [ "$dry_run" = true ]; then
        print_warning "would remove script dir: $dir"
    elif [ -L "$dir" ] || [ ! -d "$dir" ]; then
        rm -- "$dir"
        print_success "removed script path: $dir"
    else
        rm -r -- "$dir"
        print_success "removed script dir: $dir"
    fi
}

remove_script_dir "$CLAUDE_TARGET/scripts"
remove_script_dir "$CODEX_TARGET/scripts"
