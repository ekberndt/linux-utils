#!/bin/bash
set -uo pipefail

# https://github.com/openai/codex

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

# The standalone installer prompts before removing an npm install; installer
# runs are unattended.
export CODEX_NON_INTERACTIVE=1
install_from_web_script codex https://chatgpt.com/codex/install.sh sh || exit 1

# Install and configure AppArmor restrictions required by the Codex installer environment.
if run_as_root apt-get update && \
   run_as_root apt-get install -y apparmor-profiles apparmor-utils && \
   run_as_root install -m 0644 \
   /usr/share/apparmor/extra-profiles/bwrap-userns-restrict \
   /etc/apparmor.d/bwrap-userns-restrict && \
   run_as_root apparmor_parser -r /etc/apparmor.d/bwrap-userns-restrict && \
   run_as_root systemctl reload apparmor.service; then
    print_success "AppArmor user namespace restriction profile configured."
else
    print_error "Failed to configure AppArmor user namespace restriction profile."
    exit 1
fi
