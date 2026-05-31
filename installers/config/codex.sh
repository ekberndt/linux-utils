#!/bin/bash

# Sync Codex config into ~/.codex/ and shared skills into ~/.agents/skills/ as
# symlinks. Shared scripts are installed into ~/.agents/ by agents.sh. Listed
# explicitly so private state (auth, sessions, history, caches) is never
# touched.
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
apply_link "$REPO_ROOT/skills/new-branch/SKILL.md"              "$SKILLS_TARGET/new-branch/SKILL.md"
apply_link "$REPO_ROOT/skills/pr/SKILL.md"                      "$SKILLS_TARGET/pr/SKILL.md"
apply_link "$REPO_ROOT/skills/pr/references/move-from-base.md"  "$SKILLS_TARGET/pr/references/move-from-base.md"
