#!/bin/bash

# Sync Codex config into ~/.codex/ and every shared skill directory into
# ~/.agents/skills/ as symlinks. Only these two paths are touched, so private
# state (auth, sessions, history, caches) is left alone.
# Shared scripts are installed into ~/.agents/ by agents.sh.
#
# Honors DRY_RUN=true, CODEX_CONFIG_DIR, and CODEX_SKILLS_DIR. Usually invoked
# via the orchestrator (`installers/config/install.sh`); also runnable
# standalone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

CODEX_TARGET="${CODEX_CONFIG_DIR:-$HOME/.codex}"
SKILLS_TARGET="${CODEX_SKILLS_DIR:-$HOME/.agents/skills}"

# Keep helper scripts executable in this checkout
# (git tracks the +x bit, but a fresh editor write may drop it).
if [ "${DRY_RUN:-false}" = false ]; then
    chmod +x "$REPO_ROOT/scripts/inject-codex-config" 2>/dev/null || true
fi

"$REPO_ROOT/scripts/inject-codex-config" "$REPO_ROOT/codex/config.toml" "$CODEX_TARGET/config.toml"
apply_skill_links "$REPO_ROOT/skills" "$SKILLS_TARGET"
