#!/bin/bash

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
# shellcheck source=../lib/snap_packages.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/snap_packages.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install_snap_packages "$SCRIPT_DIR/snaps.txt"
