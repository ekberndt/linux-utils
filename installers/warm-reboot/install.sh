#!/bin/bash

set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMAND_PATH="/usr/local/sbin/warm-reboot"

if [[ -f "$COMMAND_PATH" ]] && cmp -s "$SCRIPT_DIR/warm-reboot" "$COMMAND_PATH"; then
    print_success "Already installed: $COMMAND_PATH"
    exit 0
fi

run_as_root install -D -m 0755 "$SCRIPT_DIR/warm-reboot" "$COMMAND_PATH"
print_success "Installed: $COMMAND_PATH"
