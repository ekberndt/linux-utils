#!/bin/bash

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
# shellcheck source=../lib/flatpak_packages.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/flatpak_packages.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install_flatpak_packages "$SCRIPT_DIR/flatpaks.txt"
