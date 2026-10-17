#!/bin/bash
set -uo pipefail

# https://antigravity.google/docs/getting-started

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

export PATH="$HOME/.local/bin:$PATH"
install_from_web_script agy https://antigravity.google/cli/install.sh bash
