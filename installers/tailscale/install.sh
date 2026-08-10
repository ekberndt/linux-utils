#!/bin/bash
set -uo pipefail

# https://tailscale.com/kb/1031/install-linux

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

install_from_web_script tailscale https://tailscale.com/install.sh || exit 1

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo "${BLUE}Next: run 'tailscale up' to authenticate and connect.${NC}"
else
    echo "${BLUE}Next: run 'sudo tailscale up' to authenticate and connect.${NC}"
fi
