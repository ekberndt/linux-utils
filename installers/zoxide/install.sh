#!/bin/bash
set -uo pipefail

# zoxide installer
# Official install script + Bash init from:
# https://github.com/ajeetdsouza/zoxide#installation

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

BASHRC="$HOME/.bashrc"
# A tmux server started by systemd does not inherit the login shell's PATH.
# Its panes still source .bashrc, so make the binary available there before
# asking it to generate the shell integration.
# shellcheck disable=SC2016 # Expanded when .bashrc is sourced, not here.
PATH_LINE='[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"'
# shellcheck disable=SC2016 # Expanded when .bashrc is sourced, not here.
INIT_LINE='eval "$(zoxide init bash)"'

# zoxide has no updater; its install script is also the upgrade.
INSTALL_URL="https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh"
install_or_update zoxide "$HOME/.local/bin" "$INSTALL_URL" sh \
    reinstall_if_outdated zoxide ajeetdsouza/zoxide "$INSTALL_URL" sh || exit 1

# README step 2: add init to the end of ~/.bashrc.
if [[ -f "$BASHRC" ]] && grep -Fq 'zoxide init bash' "$BASHRC"; then
    print_success "already configured: $BASHRC"
    exit 0
fi

{
    echo ""
    echo "# zoxide"
    echo "$PATH_LINE"
    echo "$INIT_LINE"
} >> "$BASHRC"
print_updated "$BASHRC (zoxide init)"
