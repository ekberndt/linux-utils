#!/bin/bash
set -uo pipefail

# https://github.com/openai/codex

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

# The standalone installer prompts before removing an npm install; installer
# runs are unattended. `codex update` re-runs that installer on every call,
# current or not, so ask GitHub first; it knows how codex was installed
# (script, npm, or Homebrew) and updates through the same route.
export CODEX_NON_INTERACTIVE=1
install_or_update codex https://chatgpt.com/codex/install.sh sh \
    update_if_released codex openai/codex codex update || exit 1

# Codex sandboxes with bubblewrap. Ubuntu 24.04+ sets
# kernel.apparmor_restrict_unprivileged_userns=1, which denies bwrap a user
# namespace unless bwrap-userns-restrict is loaded. 22.04 leaves that sysctl
# off and its apparmor-profiles package does not ship the profile; copying it
# fails the install, and loading a profile on an unrestricted host is unnecessary.
userns_restrict="/proc/sys/kernel/apparmor_restrict_unprivileged_userns"
bwrap_profile="/usr/share/apparmor/extra-profiles/bwrap-userns-restrict"
installed_profile="/etc/apparmor.d/bwrap-userns-restrict"

# Current when the packages are installed, the copy in /etc matches the
# packaged profile, and the kernel has it loaded. securityfs lists loaded
# profiles to any user, so a converged host needs neither apt nor sudo.
bwrap_profile_current() {
    [[ -z "$(missing_apt_packages apparmor-profiles apparmor-utils)" ]] &&
        cmp -s "$bwrap_profile" "$installed_profile" &&
        compgen -G "/sys/kernel/security/apparmor/policy/profiles/bwrap.*" >/dev/null
}

if command -v apt-get >/dev/null 2>&1 &&
   [[ -f /sys/module/apparmor/parameters/enabled ]] &&
   [[ "$(< /sys/module/apparmor/parameters/enabled)" == "Y" ]] &&
   [[ -f "$userns_restrict" && "$(< "$userns_restrict")" == "1" ]]; then
    if bwrap_profile_current; then
        print_success "AppArmor bwrap profile already loaded."
    elif apt_install apparmor-profiles apparmor-utils &&
       [[ -f "$bwrap_profile" ]] &&
       run_as_root install -m 0644 "$bwrap_profile" "$installed_profile" &&
       run_as_root apparmor_parser -r "$installed_profile" &&
       run_as_root systemctl reload apparmor.service; then
        print_updated "AppArmor bwrap user-namespace profile"
    else
        print_error "Failed to configure AppArmor user namespace restriction profile."
        exit 1
    fi
fi
