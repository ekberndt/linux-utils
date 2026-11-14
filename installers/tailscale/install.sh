#!/bin/bash
set -uo pipefail

# https://tailscale.com/kb/1031/install-linux

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

install_from_web_script tailscale https://tailscale.com/install.sh || exit 1

if ! tailscale status >/dev/null 2>&1; then
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        print_warning "Tailscale is not connected; run 'tailscale up' to authenticate."
    else
        print_warning "Tailscale is not connected; run 'sudo tailscale up' to authenticate."
    fi
fi
