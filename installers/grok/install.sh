#!/bin/bash
set -uo pipefail

# https://x.ai/cli  https://docs.x.ai/build/overview

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

install_or_update grok "$HOME/.grok/bin" https://x.ai/cli/install.sh bash grok update
