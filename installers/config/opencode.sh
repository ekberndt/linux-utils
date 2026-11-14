#!/bin/bash
set -euo pipefail

# Merge opencode/config.jsonc into $OPENCODE_CONFIG_DIR/opencode.jsonc. OpenCode
# allows every tool unless a rule says otherwise, so its file carries only the
# deny rules of agents/permissions.json, rewritten in OpenCode's rule format;
# Claude's syntax there would be rejected. Honors DRY_RUN and OPENCODE_CONFIG_DIR.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TARGET="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

inject_config opencode/config.jsonc "$TARGET/opencode.jsonc"
