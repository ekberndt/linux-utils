#!/bin/bash
set -uo pipefail

# https://ollama.com  https://github.com/ollama/ollama

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

# Ollama has no updater; its install script is also the upgrade. The script
# links the binary into the first of /usr/local/bin, /usr/bin, and /bin on
# PATH. INSTALLER_BIN_DIR lets tests stand in for /usr/local/bin.
INSTALL_URL="https://ollama.com/install.sh"
install_or_update ollama "${INSTALLER_BIN_DIR:-/usr/local/bin}" "$INSTALL_URL" sh \
    update_if_released ollama ollama/ollama run_vendor_script "$INSTALL_URL" sh
