#!/bin/bash
set -uo pipefail

# https://opencode.ai

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

install_or_update opencode https://opencode.ai/install bash opencode upgrade
