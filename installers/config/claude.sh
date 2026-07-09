#!/bin/bash

# Symlink skills into ~/.claude/skills/; inject ~/.claude/settings.json, which Claude rewrites.
#
# Honors DRY_RUN=true and CLAUDE_CONFIG_DIR. Usually invoked via the
# orchestrator (`installers/config/install.sh`); also runnable standalone.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
TARGET="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# Keep the injector executable in this checkout
# (git tracks the +x bit, but a fresh editor write may drop it).
if [ "${DRY_RUN:-false}" = false ]; then
    chmod +x "$REPO_ROOT/scripts/inject-claude-config" 2>/dev/null || true
fi
"$REPO_ROOT/scripts/inject-claude-config" "$REPO_ROOT/claude/settings.json" "$TARGET/settings.json"
apply_skill_links "$REPO_ROOT/skills" "$TARGET/skills"
