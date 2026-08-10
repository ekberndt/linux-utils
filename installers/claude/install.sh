#!/bin/bash
set -uo pipefail

# https://docs.claude.com/en/docs/claude-code/setup

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

install_from_web_script claude https://claude.ai/install.sh bash
