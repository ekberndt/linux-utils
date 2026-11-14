#!/bin/bash
set -uo pipefail

# Updates every installed Flatpak. desktop-apps installs the apps and Flatpak
# itself; a machine without Flatpak has nothing to update.

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

is_installed flatpak || exit 0
upgrade_flatpaks
