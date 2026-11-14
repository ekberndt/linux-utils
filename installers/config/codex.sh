#!/bin/bash
set -euo pipefail

# Merge ~/.codex/config.toml, which Codex rewrites, and link the shared agent
# instructions to ~/.codex/AGENTS.md. Shared skills in ~/.agents/skills/ are
# linked by agents.sh unless CODEX_SKILLS_DIR overrides.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TARGET="${CODEX_CONFIG_DIR:-$HOME/.codex}"

inject_config codex/config.toml "$TARGET/config.toml"
apply_link "$REPO_ROOT/agents/instructions.md" "$TARGET/AGENTS.md"
if [[ -n "${CODEX_SKILLS_DIR:-}" ]]; then
    apply_skill_links "$REPO_ROOT/skills" "$CODEX_SKILLS_DIR"
fi
