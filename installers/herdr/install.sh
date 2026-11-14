#!/bin/bash
set -uo pipefail

# Herdr, the desktop app for terminals and coding agents, plus herdr-core (hc)
# when no core is installed yet. The app needs a desktop session (on Linux, a
# Vulkan driver too) and keeps itself and the core current after this.
# https://github.com/herdrdev/herdr-app#install

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

install_from_web_script herdr-app https://releases.herdr.dev/app/install.sh sh
