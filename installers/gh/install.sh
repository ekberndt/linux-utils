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
    print_installed "gh$(version_suffix gh)"
}

# `gh extension install` resolves the release through gh's authenticated API
# client, so it fails on a machine that has not run `gh auth login` yet — which
# is every machine this installer reaches first. The CLI itself is installed and
# usable, so name the commands left to run rather than failing the component.
install_stack_extension() {
    echo "Installing GitHub CLI extension: $STACK_EXTENSION..."
    if gh extension install "$STACK_EXTENSION"; then
        print_installed "gh stack"
        return 0
    fi
    print_warning "Could not install gh stack; run 'gh auth login', then 'gh extension install $STACK_EXTENSION'"
}

# "repo version" per extension, from the tab-separated name, repo, and version
# `gh extension list` prints when piped.
extension_versions() {
    gh extension list | awk -F'\t' '{ print $2, $3 }'
}

# An installed extension came through the same authenticated API, so a failed
# upgrade is a real failure rather than a missing login.
upgrade_extensions() {
    local before="$1"
    if ! gh extension upgrade --all; then
        print_error "Failed to upgrade GitHub CLI extensions"
        return 1
    fi
    report_version_changes "$before" "$(extension_versions)"
}

install_gh || exit 1
# Listing extensions needs a login too.
if ! extensions="$(extension_versions)"; then
    print_warning "Could not list GitHub CLI extensions; run 'gh auth login', then re-run"
    exit 0
fi
had_failure=false
if [[ -n "$extensions" ]]; then
    upgrade_extensions "$extensions" || had_failure=true
fi
if [[ "$extensions" != *"$STACK_EXTENSION "* ]]; then
    install_stack_extension
fi
[[ "$had_failure" == false ]]
