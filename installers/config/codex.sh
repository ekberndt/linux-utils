#!/bin/bash

# Sync Codex config, shared scripts, and shared skills into ~/.codex/ as
# symlinks. Listed explicitly so private state (auth, sessions, history,
# caches) is never touched.
#
# Honors DRY_RUN=true and CODEX_CONFIG_DIR. Usually invoked via the
# orchestrator (`installers/config/install.sh`); also runnable standalone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

TARGET="${CODEX_CONFIG_DIR:-$HOME/.codex}"

# Keep helper scripts executable in this checkout
# (git tracks the +x bit, but a fresh editor write may drop it).
if [ "${DRY_RUN:-false}" = false ]; then
    chmod +x \
             "$REPO_ROOT/scripts/inject-codex-config" \
             "$REPO_ROOT/scripts/agent-fanout" \
             "$REPO_ROOT/scripts/statusline-worktree" 2>/dev/null || true
fi

"$REPO_ROOT/scripts/inject-codex-config" "$REPO_ROOT/codex/config.toml" "$TARGET/config.toml"
apply_link "$REPO_ROOT/scripts/agent-fanout"                    "$TARGET/scripts/codex-fanout"
apply_link "$REPO_ROOT/scripts/statusline-worktree"              "$TARGET/scripts/statusline-worktree"
apply_link "$REPO_ROOT/skills/new-branch/SKILL.md"              "$TARGET/skills/new-branch/SKILL.md"
apply_link "$REPO_ROOT/skills/pr/SKILL.md"                      "$TARGET/skills/pr/SKILL.md"
apply_link "$REPO_ROOT/skills/pr/references/move-from-base.md"  "$TARGET/skills/pr/references/move-from-base.md"
