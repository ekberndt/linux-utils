#!/bin/bash
set -euo pipefail

# Merge shared permissions and opencode config into $OPENCODE_CONFIG_DIR/opencode.jsonc.
# Honors DRY_RUN and OPENCODE_CONFIG_DIR.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TARGET="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

inject_config agents/permissions.json opencode/config.jsonc "$TARGET/opencode.jsonc"
