#!/bin/bash
set -uo pipefail

# https://antigravity.google/docs/getting-started

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

install_or_update agy https://antigravity.google/cli/install.sh bash agy update
