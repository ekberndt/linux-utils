#!/bin/bash
set -euo pipefail

# Give agent commands one shared home under ~/.agents/scripts/.
# Honors DRY_RUN and AGENTS_CONFIG_DIR.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TARGET="${AGENTS_CONFIG_DIR:-$HOME/.agents}"
SCRIPTS=(
    agent-tmux
    tmux-paste-clipboard
    tmux-align-path
    statusline-worktree
    agent-session
)

for script in "${SCRIPTS[@]}"; do
    # tmux runs these through the symlink, so the bit has to be set on the
    # checkout; git tracks it but a fresh editor write can drop it.
    [[ "$DRY_RUN" == false ]] && chmod +x "$REPO_ROOT/scripts/$script" 2>/dev/null
    apply_link "$REPO_ROOT/scripts/$script" "$TARGET/scripts/$script"
done

apply_skill_links "$REPO_ROOT/skills" "$TARGET/skills"
