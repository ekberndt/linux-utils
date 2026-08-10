#!/bin/bash
set -euo pipefail

# Symlink skills into ~/.claude/skills/ and merge ~/.claude/settings.json,
# which Claude rewrites. Honors DRY_RUN and CLAUDE_CONFIG_DIR.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TARGET="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

inject_config claude/settings.json "$TARGET/settings.json"
apply_skill_links "$REPO_ROOT/skills" "$TARGET/skills"
