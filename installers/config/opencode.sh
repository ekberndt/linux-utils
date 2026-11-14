#!/bin/bash
set -euo pipefail

# Merge opencode/config.jsonc into $OPENCODE_CONFIG_DIR/opencode.jsonc. OpenCode
# allows every tool unless a rule says otherwise and rejects Claude's rule
# syntax, so its file carries the deny rules of agents/permissions.json,
# rewritten by hand in OpenCode's format, plus its own `gh pr` denies.
# Honors DRY_RUN and OPENCODE_CONFIG_DIR.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TARGET="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

inject_config opencode/config.jsonc "$TARGET/opencode.jsonc"
