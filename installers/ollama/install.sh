#!/bin/bash
set -uo pipefail

# https://ollama.com  https://github.com/ollama/ollama

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

# Ollama has no updater; its install script is also the upgrade.
INSTALL_URL="https://ollama.com/install.sh"
install_or_update ollama "$INSTALL_URL" sh \
    update_if_released ollama ollama/ollama run_vendor_script "$INSTALL_URL" sh
