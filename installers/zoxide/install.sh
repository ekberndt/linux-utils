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

install_from_web_script zoxide https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh sh || exit 1

# README step 2: add init to the end of ~/.bashrc. Existing installs already
# have INIT_LINE, so add the PATH setup independently instead of treating any
# zoxide line as proof that the whole integration is configured.
if [[ -f "$BASHRC" ]] && grep -Fq 'zoxide init bash' "$BASHRC"; then
    if ! grep -Fq "$PATH_LINE" "$BASHRC"; then
        tmp="$(mktemp)"
        PATH_LINE="$PATH_LINE" awk '/zoxide init bash/ && !done { print ENVIRON["PATH_LINE"]; done=1 } { print }' "$BASHRC" > "$tmp"
        mv "$tmp" "$BASHRC"
        print_success "added zoxide PATH setup: $BASHRC"
    fi
    print_success "already configured: $BASHRC"
    exit 0
fi

{
    echo ""
    echo "# zoxide"
    echo "$PATH_LINE"
    echo "$INIT_LINE"
} >> "$BASHRC"
print_success "added zoxide init: $BASHRC"
