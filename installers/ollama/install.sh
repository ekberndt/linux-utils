#!/bin/bash
set -uo pipefail

# https://ollama.com  https://github.com/ollama/ollama

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

install_from_web_script ollama https://ollama.com/install.sh
