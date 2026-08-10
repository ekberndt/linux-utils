#!/bin/bash
set -euo pipefail

# Symlink skills into ~/.agents/skills/ and merge ~/.codex/config.toml, which
# Codex rewrites. Honors DRY_RUN, CODEX_CONFIG_DIR, and CODEX_SKILLS_DIR.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TARGET="${CODEX_CONFIG_DIR:-$HOME/.codex}"

inject_config codex/config.toml "$TARGET/config.toml"
apply_skill_links "$REPO_ROOT/skills" "${CODEX_SKILLS_DIR:-$HOME/.agents/skills}"
