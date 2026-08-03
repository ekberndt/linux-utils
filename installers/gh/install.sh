#!/bin/bash

# GitHub CLI installer
# Installs gh from the official GitHub apt repository to get the latest version
# (the default Ubuntu apt package is outdated)
# https://github.com/cli/cli/blob/trunk/docs/install_linux.md

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

if is_installed "gh"; then
    print_success "Already installed: gh"
    exit 0
fi

echo "Installing GitHub CLI from official repository..."

# Download and install the signing key
run_as_root mkdir -p -m 755 /etc/apt/keyrings
wget -nv -O- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | run_as_root tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
run_as_root chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg

# Add the official GitHub CLI apt repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | run_as_root tee /etc/apt/sources.list.d/github-cli.list > /dev/null

# Update and install
run_as_root apt-get update
if run_as_root apt-get install -y gh; then
    print_success "Successfully installed: gh $(gh --version | head -1)"
else
    print_error "Failed to install gh"
    exit 1
fi
