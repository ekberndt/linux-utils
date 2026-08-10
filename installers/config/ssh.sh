#!/bin/bash
set -euo pipefail

# Install the SSH daemon's key-only authentication policy. Honors DRY_RUN.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

source_config="$CONFIG_DIR/sshd.conf"
target_config="/etc/ssh/sshd_config.d/00-linux-utils.conf"

if [[ "$(uname -s)" != Linux ]] || [[ ! -x /usr/sbin/sshd ]]; then
    print_warning "skipping SSH server config (OpenSSH server unavailable)"
    exit 0
fi

if cmp -s "$source_config" "$target_config"; then
    print_success "SSH server already requires public keys"
elif [[ "$DRY_RUN" == true ]]; then
    print_warning "would install key-only SSH policy: $target_config"
else
    run_as_root install -D -m 0644 "$source_config" "$target_config"
    print_success "SSH server requires public keys; password login disabled"
fi

if [[ "$DRY_RUN" == true ]]; then
    print_warning "would enable and start ssh.service"
    exit 0
fi

run_as_root /usr/sbin/sshd -t
run_as_root systemctl enable --now ssh.service
run_as_root systemctl reload ssh.service
run_as_root systemctl status ssh.service --no-pager
