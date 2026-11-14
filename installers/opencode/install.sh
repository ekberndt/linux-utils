#!/bin/bash
set -uo pipefail

# https://opencode.ai

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

# The script installs only to ~/.opencode/bin and adds it to PATH in shell rc
# files, which this run never re-reads.
export PATH="$HOME/.opencode/bin:$PATH"
install_or_update opencode https://opencode.ai/install bash opencode upgrade
