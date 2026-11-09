#!/bin/bash
set -euo pipefail

# Install the kernel sysctl drop-in and apply live settings on Linux. Honors
# DRY_RUN, SYSCTL_TARGET_CONFIG, and PROC_SYS_DIR.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

source_config="$CONFIG_DIR/sysctl.conf"
target_config="${SYSCTL_TARGET_CONFIG:-/etc/sysctl.d/99-linux-utils.conf}"
proc_sys_dir="${PROC_SYS_DIR:-/proc/sys}"

if [[ "$(uname -s)" != Linux ]]; then
    print_warning "skipping kernel config (not Linux)"
    exit 0
fi

# Reading /proc/sys and comparing the drop-in file need no privilege, so a
# converged machine never prompts for sudo.
live_sysctls_converged() {
    local line key value proc_path
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_.-]+)[[:space:]]*=[[:space:]]*([^[:space:]]+)[[:space:]]*$ ]] || continue
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        proc_path="$proc_sys_dir/${key//./\/}"
        [[ -f "$proc_path" && "$(< "$proc_path")" == "$value" ]] || return 1
    done < "$source_config"
}

config_changed=false
if cmp -s "$source_config" "$target_config"; then
    print_success "Kernel sysctl config already installed: $target_config"
elif [[ "$DRY_RUN" == true ]]; then
    print_warning "would install kernel sysctl config: $target_config"
    config_changed=true
else
    run_as_root install -D -m 0644 "$source_config" "$target_config"
    config_changed=true
    print_success "Installed kernel sysctl config: $target_config"
fi

if [[ "$config_changed" == false ]] && live_sysctls_converged; then
    print_success "Kernel sysctl settings already active"
elif [[ "$DRY_RUN" == true ]]; then
    print_warning "would apply kernel sysctl settings from $target_config"
else
    run_as_root sysctl -q -p "$target_config"
    print_success "Applied kernel sysctl settings"
fi
