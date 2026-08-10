#!/bin/bash
set -euo pipefail

# Give agent commands one shared home under ~/.agents/scripts/, and drop the
# per-tool script directories earlier syncs created.
# Honors DRY_RUN and AGENTS_CONFIG_DIR.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TARGET="${AGENTS_CONFIG_DIR:-$HOME/.agents}"
SCRIPTS=(
    agent-tmux
    tmux-paste-clipboard
    tmux-align-path
    statusline-worktree
)

for script in "${SCRIPTS[@]}"; do
    # tmux runs these through the symlink, so the bit has to be set on the
    # checkout; git tracks it but a fresh editor write can drop it.
    [[ "$DRY_RUN" == false ]] && chmod +x "$REPO_ROOT/scripts/$script" 2>/dev/null
    apply_link "$REPO_ROOT/scripts/$script" "$TARGET/scripts/$script"
done

remove_stale_path "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts"
remove_stale_path "${CODEX_CONFIG_DIR:-$HOME/.codex}/scripts"
remove_stale_path "${GROK_CONFIG_DIR:-$HOME/.grok}/scripts"
