#!/bin/bash
set -uo pipefail

# Ubuntu's package, so installation does not depend on an external APT
# repository or its signing key.

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

STACK_EXTENSION="github/gh-stack"

install_gh() {
    if is_installed gh; then
        print_success "Already installed: gh$(version_suffix gh)"
        return 0
    fi

    echo "Installing GitHub CLI from Ubuntu repositories..."
    if ! apt_install gh; then
        print_error "Failed to install gh"
        return 1
    fi
    print_success "Successfully installed: gh$(version_suffix gh)"
}

# `gh extension install` resolves the release through gh's authenticated API
# client, so it fails on a machine that has not run `gh auth login` yet — which
# is every machine this installer reaches first. The CLI itself is installed and
# usable, so name the commands left to run rather than failing the component.
install_stack_extension() {
    if gh extension list 2>/dev/null | grep -q "$STACK_EXTENSION"; then
        print_success "Already installed: gh stack"
        return 0
    fi

    echo "Installing GitHub CLI extension: $STACK_EXTENSION..."
    if gh extension install "$STACK_EXTENSION"; then
        print_success "Successfully installed: gh stack"
        return 0
    fi
    print_warning "Could not install gh stack; run 'gh auth login', then 'gh extension install $STACK_EXTENSION'"
}

install_gh || exit 1
install_stack_extension
