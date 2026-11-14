#!/bin/bash
set -uo pipefail

# https://ollama.com  https://github.com/ollama/ollama

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

# Ollama has no updater; its install script is also the upgrade.
INSTALL_URL="https://ollama.com/install.sh"
install_or_update ollama "$INSTALL_URL" sh \
    reinstall_if_outdated ollama ollama/ollama "$INSTALL_URL" sh
