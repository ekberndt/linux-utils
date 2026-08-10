#!/bin/bash
set -uo pipefail

# Ubuntu's package, so installation does not depend on an external APT
# repository or its signing key.

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

if is_installed gh; then
    print_success "Already installed: gh$(version_suffix gh)"
    exit 0
fi

echo "Installing GitHub CLI from Ubuntu repositories..."
if ! apt_install gh; then
    print_error "Failed to install gh"
    exit 1
fi
print_success "Successfully installed: gh$(version_suffix gh)"
