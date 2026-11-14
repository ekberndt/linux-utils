#!/bin/bash
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
had_failure=false

install_apt_package_list \
    "${INSTALLER_APT_PACKAGES_FILE:-$SCRIPT_DIR/apt_packages.txt}" || had_failure=true
upgrade_apt_packages || had_failure=true

[[ "$had_failure" == false ]]
