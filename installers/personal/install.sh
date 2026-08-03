#!/bin/bash

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
# shellcheck source=../lib/package_list.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/package_list.sh"
# shellcheck source=../lib/apt_packages.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/apt_packages.sh"
# shellcheck source=../lib/flatpak_packages.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/flatpak_packages.sh"
# shellcheck source=../lib/snap_packages.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/snap_packages.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
had_failure=false

install_apt_package_list "$SCRIPT_DIR/apt_packages.txt" || had_failure=true
install_flatpak_packages "$SCRIPT_DIR/flatpaks.txt" || had_failure=true
install_snap_packages "$SCRIPT_DIR/snaps.txt" || had_failure=true

[[ "$had_failure" == false ]]
