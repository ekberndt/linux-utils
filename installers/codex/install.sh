#!/bin/bash
set -uo pipefail

# https://github.com/openai/codex

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

# The standalone installer prompts before removing an npm install; installer
# runs are unattended.
export CODEX_NON_INTERACTIVE=1
install_from_web_script codex https://chatgpt.com/codex/install.sh sh || exit 1

# Codex sandboxes with bubblewrap. Ubuntu 24.04+ sets
# kernel.apparmor_restrict_unprivileged_userns=1, which denies bwrap a user
# namespace unless bwrap-userns-restrict is loaded. 22.04 leaves that sysctl
# off and its apparmor-profiles package does not ship the profile; copying it
# fails the install, and loading a profile on an unrestricted host is unnecessary.
userns_restrict="/proc/sys/kernel/apparmor_restrict_unprivileged_userns"
bwrap_profile="/usr/share/apparmor/extra-profiles/bwrap-userns-restrict"
if command -v apt-get >/dev/null 2>&1 &&
   [[ -f /sys/module/apparmor/parameters/enabled ]] &&
   [[ "$(< /sys/module/apparmor/parameters/enabled)" == "Y" ]] &&
   [[ -f "$userns_restrict" && "$(< "$userns_restrict")" == "1" ]]; then
    if run_as_root apt-get update &&
       run_as_root apt-get install -y apparmor-profiles apparmor-utils &&
       [[ -f "$bwrap_profile" ]] &&
       run_as_root install -m 0644 "$bwrap_profile" /etc/apparmor.d/bwrap-userns-restrict &&
       run_as_root apparmor_parser -r /etc/apparmor.d/bwrap-userns-restrict &&
       run_as_root systemctl reload apparmor.service; then
        print_success "AppArmor user namespace restriction profile configured."
    else
        print_error "Failed to configure AppArmor user namespace restriction profile."
        exit 1
    fi
fi
