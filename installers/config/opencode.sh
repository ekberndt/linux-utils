#!/bin/bash

# Sync opencode config from repo to $OPENCODE_CONFIG_DIR (default ~/.config/opencode).
# Based on the claude config pattern; scopes model to ~/src/personal.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
TARGET="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

mkdir -p "$TARGET"
cp "$REPO_ROOT/opencode/config.jsonc" "$TARGET/opencode.jsonc"
print_success "Synced opencode config ($TARGET/opencode.jsonc)"
