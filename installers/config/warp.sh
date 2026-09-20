#!/bin/bash
set -euo pipefail

# Merge OSC 52 clipboard access into Warp's settings.toml. Honors DRY_RUN.
# No-op off macOS: the setting lives on the machine running Warp, not the
# Linux host that tmux emits OSC 52 from.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

if [[ "$(uname -s)" != Darwin ]]; then
    print_warning "skipping Warp config (not macOS)"
    exit 0
fi

inject_config macos/warp-settings.toml "$HOME/.warp/settings.toml"
