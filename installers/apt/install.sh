#!/bin/bash

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
# shellcheck source=../lib/package_list.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/package_list.sh"
# shellcheck source=../lib/apt_packages.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/apt_packages.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="${INSTALLER_APT_PACKAGES_FILE:-$SCRIPT_DIR/apt_packages.txt}"

install_apt_package_list "$PACKAGES_FILE"
