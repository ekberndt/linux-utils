#!/bin/bash
set -uo pipefail

# https://x.ai/cli  https://docs.x.ai/build/overview

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

export PATH="$HOME/.grok/bin:$PATH"
install_or_update grok https://x.ai/cli/install.sh bash grok update
