#!/bin/bash
set -euo pipefail

# Point macOS screencapture at ~/Pictures/screenshots. Honors DRY_RUN.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

if [[ "$(uname -s)" != Darwin ]]; then
    print_warning "Not on macOS; skipping screenshot location config"
    exit 0
fi

TARGET="$HOME/Pictures/screenshots"

if [[ "$DRY_RUN" == true ]]; then
    print_warning "would set screenshot location: $TARGET"
    exit 0
fi

if [[ -d "$TARGET" &&
    "$(defaults read com.apple.screencapture location 2>/dev/null)" == "$TARGET" ]]; then
    print_success "Screenshots already saved to $TARGET"
elif mkdir -p "$TARGET" &&
    defaults write com.apple.screencapture location -string "$TARGET"; then
    print_updated "screenshots saved to $TARGET"
else
    print_error "Screenshot location setup failed"
    exit 1
fi
