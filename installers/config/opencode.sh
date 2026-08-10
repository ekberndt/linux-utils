#!/bin/bash
set -euo pipefail

# Copy opencode config to $OPENCODE_CONFIG_DIR (default ~/.config/opencode).
# opencode does not rewrite this file, so it needs no merge.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TARGET="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

if [[ "$DRY_RUN" == true ]]; then
    print_warning "would sync opencode config: $TARGET/opencode.jsonc"
    exit 0
fi

mkdir -p "$TARGET"
cp "$REPO_ROOT/opencode/config.jsonc" "$TARGET/opencode.jsonc"
print_success "Synced opencode config ($TARGET/opencode.jsonc)"
