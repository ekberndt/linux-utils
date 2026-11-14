#!/bin/bash
set -uo pipefail

# Apps installed with pipx. The installer puts none here; they are the user's.

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

is_installed pipx || exit 0

# "name version" per app.
if ! before="$(pipx list --short)"; then
    print_error "Could not list pipx apps"
    exit 1
fi
[[ -n "$before" ]] || exit 0

# pipx has no outdated check; upgrade-all asks the index per app and
# reinstalls only those with a newer release.
if ! pipx upgrade-all; then
    print_error "pipx upgrade-all failed"
    exit 1
fi
after="$(pipx list --short)"
report_version_changes "$before" "$after"
if [[ "$after" == "$before" ]] && ! pip_index_reachable pipx runpip "${before%% *}"; then
    print_error "Could not reach the package index to upgrade pipx apps"
    exit 1
fi
