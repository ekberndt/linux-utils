#!/bin/bash
set -uo pipefail

# Refreshes every installed snap. desktop-apps installs the snaps; a machine
# without snapd has nothing to refresh.

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

is_installed snap || exit 0
upgrade_snaps
