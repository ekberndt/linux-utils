#!/bin/bash
set -uo pipefail

# https://opencode.ai

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

install_from_web_script opencode https://opencode.ai/install bash
