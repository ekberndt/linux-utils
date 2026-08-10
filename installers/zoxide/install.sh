#!/bin/bash
set -uo pipefail

# zoxide installer
# Official install script + Bash init from:
# https://github.com/ajeetdsouza/zoxide#installation

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

BASHRC="$HOME/.bashrc"
LOCAL_BIN="$HOME/.local/bin"
# A tmux server started by systemd does not inherit the login shell's PATH.
# Its panes still source .bashrc, so make the binary available there before
# asking it to generate the shell integration.
# shellcheck disable=SC2016 # Expanded when .bashrc is sourced, not here.
PATH_LINE='[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"'
# Written into bashrc literally — expand when the shell sources it.
INIT_LINE="eval \"\$(zoxide init bash)\""

# Official install drops the binary in ~/.local/bin. Login shells get that from
# ~/.profile; non-login installer runs often do not.
case ":$PATH:" in
    *":$LOCAL_BIN:"*) ;;
    *) export PATH="$LOCAL_BIN:$PATH" ;;
esac

if is_installed "zoxide" || [[ -x "$LOCAL_BIN/zoxide" ]]; then
    print_success "Already installed: zoxide ($(zoxide --version 2>/dev/null | head -n1))"
else
    echo "Installing zoxide..."
    if ! curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh; then
        print_error "Failed to install zoxide"
        exit 1
    fi
    if ! is_installed "zoxide" && [[ ! -x "$LOCAL_BIN/zoxide" ]]; then
        print_error "Install finished but zoxide not found in $LOCAL_BIN"
        exit 1
    fi
    print_success "Successfully installed: zoxide"
fi

# README step 2: add init to the end of ~/.bashrc. Existing installs already
# have INIT_LINE, so add the PATH setup independently instead of treating any
# zoxide line as proof that the whole integration is configured.
if [[ -f "$BASHRC" ]] && grep -Fq 'zoxide init bash' "$BASHRC"; then
    if ! grep -Fq "$PATH_LINE" "$BASHRC"; then
        sed -i "/zoxide init bash/i $PATH_LINE" "$BASHRC"
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
