#!/bin/bash
set -uo pipefail

# https://docs.astral.sh/uv/getting-started/installation/

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

uv_tool_versions() {
    uv tool list 2>/dev/null | awk '/^[^- ]/ { print $1, $2 }'
}

# Every uv tool, wandb among them. The report compares versions rather than
# trusting the outdated list: a tool installed with a version constraint is
# listed but stays put.
upgrade_uv_tools() {
    local outdated before
    if ! outdated="$(uv tool list --outdated)"; then
        print_error "Could not check uv tools for upgrades"
        return 1
    fi
    [[ -n "$outdated" ]] || return 0

    before="$(uv_tool_versions)"
    if ! uv tool upgrade --all; then
        print_error "uv tool upgrade --all failed"
        return 1
    fi
    report_version_changes "$before" "$(uv_tool_versions)"
}

use_local_bin
if ! is_installed uv; then
    install_from_web_script uv https://astral.sh/uv/install.sh
    exit
fi

had_failure=false
# Only the standalone installer leaves a receipt, and only that install can
# update itself; a Homebrew or pip uv upgrades with its manager.
if [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/uv/uv-receipt.json" ]]; then
    update_cli uv uv self update || had_failure=true
fi
upgrade_uv_tools || had_failure=true

[[ "$had_failure" == false ]]
