#!/bin/bash

# Symlink skills into ~/.agents/skills/; inject ~/.grok/config.toml, which Grok rewrites.
#
# Honors DRY_RUN=true, GROK_CONFIG_DIR, and GROK_SKILLS_DIR. Usually invoked
# via the orchestrator (`installers/config/install.sh`); also runnable
# standalone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

GROK_TARGET="${GROK_CONFIG_DIR:-$HOME/.grok}"
SKILLS_TARGET="${GROK_SKILLS_DIR:-$HOME/.agents/skills}"

# Keep helper scripts executable in this checkout
# (git tracks the +x bit, but a fresh editor write may drop it).
if [ "${DRY_RUN:-false}" = false ]; then
    chmod +x "$REPO_ROOT/scripts/inject-grok-config" 2>/dev/null || true
fi

"$REPO_ROOT/scripts/inject-grok-config" "$REPO_ROOT/grok/config.toml" "$GROK_TARGET/config.toml"
apply_skill_links "$REPO_ROOT/skills" "$SKILLS_TARGET"
