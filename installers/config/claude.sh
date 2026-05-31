#!/bin/bash

# Sync Claude Code config and shared skills into ~/.claude/ as symlinks.
# Shared scripts are installed into ~/.agents/ by agents.sh. Listed explicitly
# so private state (sessions, history, credentials) is never touched.
#
# Honors DRY_RUN=true and CLAUDE_CONFIG_DIR. Usually invoked via the
# orchestrator (`installers/config/install.sh`); also runnable standalone.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
TARGET="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
apply_link "$REPO_ROOT/claude/settings.json"                          "$TARGET/settings.json"
apply_link "$REPO_ROOT/skills/new-branch/SKILL.md"                    "$TARGET/skills/new-branch/SKILL.md"
apply_link "$REPO_ROOT/skills/pr/SKILL.md"                            "$TARGET/skills/pr/SKILL.md"
apply_link "$REPO_ROOT/skills/pr/references/move-from-base.md"        "$TARGET/skills/pr/references/move-from-base.md"
