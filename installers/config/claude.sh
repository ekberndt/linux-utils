#!/bin/bash

# Sync Claude Code config (settings, shared scripts, shared skills) into
# ~/.claude/ as symlinks. Listed explicitly so private state (sessions,
# history, credentials) is never touched.
#
# Honors DRY_RUN=true and CLAUDE_CONFIG_DIR. Usually invoked via the
# orchestrator (`installers/config/install.sh`); also runnable standalone.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
TARGET="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# Keep helper scripts executable in this checkout
# (git tracks the +x bit, but a fresh editor write may drop it).
if [ "${DRY_RUN:-false}" = false ]; then
    chmod +x \
             "$REPO_ROOT/scripts/agent-fanout" \
             "$REPO_ROOT/scripts/statusline-worktree" 2>/dev/null || true
fi
apply_link "$REPO_ROOT/claude/settings.json"                          "$TARGET/settings.json"
apply_link "$REPO_ROOT/scripts/agent-fanout"                          "$TARGET/scripts/cc-fanout"
apply_link "$REPO_ROOT/scripts/statusline-worktree"                    "$TARGET/scripts/statusline-worktree"
apply_link "$REPO_ROOT/skills/new-branch/SKILL.md"                    "$TARGET/skills/new-branch/SKILL.md"
apply_link "$REPO_ROOT/skills/pr/SKILL.md"                            "$TARGET/skills/pr/SKILL.md"
apply_link "$REPO_ROOT/skills/pr/references/move-from-base.md"        "$TARGET/skills/pr/references/move-from-base.md"
