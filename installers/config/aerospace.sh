#!/bin/bash
set -euo pipefail

# Link ~/.aerospace.toml. Honors DRY_RUN. No-op off macOS.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

if [[ "$(uname -s)" != Darwin ]]; then
    print_warning "skipping AeroSpace config (not macOS)"
    exit 0
fi

apply_link "$REPO_ROOT/macos/.aerospace.toml" "$HOME/.aerospace.toml"
