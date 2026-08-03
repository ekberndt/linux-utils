#!/bin/bash

# Sync shared agent scripts into ~/.agents/ as symlinks and remove per-tool
# script directories, and anything since deleted, so agent commands have one
# shared home.
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
GROK_TARGET="${GROK_CONFIG_DIR:-$HOME/.grok}"

# Keep helper scripts executable in this checkout
# (git tracks the +x bit, but a fresh editor write may drop it).
if [ "${DRY_RUN:-false}" = false ]; then
    chmod +x \
             "$REPO_ROOT/scripts/agent-tmux" \
             "$REPO_ROOT/scripts/tmux-paste-clipboard" \
             "$REPO_ROOT/scripts/statusline-worktree" \
             "$REPO_ROOT/scripts/inject-claude-config" \
             "$REPO_ROOT/scripts/inject-codex-config" \
             "$REPO_ROOT/scripts/inject-grok-config" 2>/dev/null || true
fi

apply_link "$REPO_ROOT/scripts/agent-tmux"          "$TARGET/scripts/agent-tmux"
apply_link "$REPO_ROOT/scripts/tmux-paste-clipboard" "$TARGET/scripts/tmux-paste-clipboard"
apply_link "$REPO_ROOT/scripts/statusline-worktree" "$TARGET/scripts/statusline-worktree"

remove_stale_path() {
    local path="$1"
    local dry_run="${DRY_RUN:-false}"

    if [ ! -e "$path" ] && [ ! -L "$path" ]; then
        return 0
    fi

    if [ "$dry_run" = true ]; then
        print_warning "would remove: $path"
    elif [ -L "$path" ] || [ ! -d "$path" ]; then
        rm -- "$path"
        print_success "removed: $path"
    else
        rm -r -- "$path"
        print_success "removed dir: $path"
    fi
}

remove_stale_path "$CLAUDE_TARGET/scripts"
remove_stale_path "$CODEX_TARGET/scripts"
remove_stale_path "$GROK_TARGET/scripts"
# agent-fanout is gone; drop the symlink a previous sync left behind.
remove_stale_path "$TARGET/scripts/agent-fanout"
