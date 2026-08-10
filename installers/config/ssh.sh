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

policy_changed=false

if cmp -s "$source_config" "$target_config"; then
    print_success "SSH server already requires public keys"
elif [[ "$DRY_RUN" == true ]]; then
    print_warning "would install key-only SSH policy: $target_config"
else
    run_as_root install -D -m 0644 "$source_config" "$target_config"
    policy_changed=true
    print_success "SSH server requires public keys; password login disabled"
fi

# Validating and reloading unconditionally is what made a converged machine ask
# for a password, and this is the last component of a long install — exactly
# where the initial sudo credential is most likely to have aged out. Reading
# unit state needs no privilege, so only real work escalates.
if [[ "$policy_changed" == true ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        print_warning "would validate and reload ssh.service"
    else
        run_as_root /usr/sbin/sshd -t
        run_as_root systemctl reload ssh.service
        print_success "reloaded ssh.service"
    fi
fi

if systemctl is-enabled --quiet ssh.service 2>/dev/null; then
    print_success "ssh.service enabled and $(systemctl is-active ssh.service)"
elif [[ "$DRY_RUN" == true ]]; then
    print_warning "would enable and start ssh.service"
else
    run_as_root systemctl enable --now ssh.service
    print_success "enabled ssh.service"
fi
