#!/bin/bash

# Install the SSH daemon's key-only authentication policy.
# Honors DRY_RUN=true. Usually invoked via installers/config/install.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

source_config="$SCRIPT_DIR/sshd.conf"
target_config="/etc/ssh/sshd_config.d/00-linux-utils.conf"

if [[ "$(uname -s)" != Linux ]] || [[ ! -x /usr/sbin/sshd ]]; then
    print_warning "skipping SSH server config (OpenSSH server unavailable)"
    exit 0
fi

if cmp -s "$source_config" "$target_config"; then
    print_success "SSH server already requires public keys"
elif [[ "${DRY_RUN:-false}" == true ]]; then
    print_warning "would install key-only SSH policy: $target_config"
else
    run_as_root install -D -m 0644 "$source_config" "$target_config"
    print_success "SSH server requires public keys; password login disabled"
fi

if [[ "${DRY_RUN:-false}" == true ]]; then
    print_warning "would enable and start ssh.service"
    exit 0
fi

run_as_root /usr/sbin/sshd -t
run_as_root systemctl enable --now ssh.service
run_as_root systemctl reload ssh.service
run_as_root systemctl status ssh.service --no-pager
