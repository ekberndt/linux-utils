#!/bin/bash
set -euo pipefail

# Link hooks into ~/.grok/hooks/ and merge ~/.grok/config.toml, which Grok
# rewrites. Shared skills in ~/.agents/skills/ are linked by agents.sh unless
# GROK_SKILLS_DIR overrides.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TARGET="${GROK_CONFIG_DIR:-$HOME/.grok}"

inject_config grok/config.toml "$TARGET/config.toml"
if [[ -n "${GROK_SKILLS_DIR:-}" ]]; then
    apply_skill_links "$REPO_ROOT/skills" "$GROK_SKILLS_DIR"
fi

# Grok reads hooks from ~/.grok/hooks/*.json rather than config.toml, so this
# links in whole instead of going through the injector.
apply_link "$REPO_ROOT/grok/hooks/agent-tmux.json" "$TARGET/hooks/agent-tmux.json"
