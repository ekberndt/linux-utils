#!/bin/bash
set -uo pipefail

# https://docs.astral.sh/uv/getting-started/installation/

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

install_from_web_script uv https://astral.sh/uv/install.sh
