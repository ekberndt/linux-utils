#!/bin/bash
set -euo pipefail

# Symlink skills into ~/.gemini/config/skills/ and ~/.agents/skills/, and merge
# ~/.gemini/antigravity-cli/settings.json and ~/.gemini/config/hooks.json,
# which Antigravity rewrites. Honors DRY_RUN, AGY_CONFIG_DIR, AGY_CUSTOM_DIR,
# and AGY_SKILLS_DIR.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TARGET="${AGY_CONFIG_DIR:-$HOME/.gemini/antigravity-cli}"
CUSTOM_DIR="${AGY_CUSTOM_DIR:-$HOME/.gemini/config}"

inject_config agy/settings.json "$TARGET/settings.json"
inject_config agy/hooks.json "$CUSTOM_DIR/hooks.json"
apply_skill_links "$REPO_ROOT/skills" "$CUSTOM_DIR/skills"
apply_skill_links "$REPO_ROOT/skills" "${AGY_SKILLS_DIR:-$HOME/.agents/skills}"
