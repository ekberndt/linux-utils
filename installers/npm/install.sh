#!/bin/bash
set -uo pipefail

# Global npm packages, as `npm update -g` updates them. The installer puts
# tree-sitter-cli here on a root host (lazyvim); the rest are the user's.

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

# "name current -> wanted" per package `npm update -g` would move, from
# "<dir>:<name>@<wanted>:<name>@<current>:<name>@<latest>:<dependent>". npm
# exits 1 when it finds something outdated, so only a failure that lists
# nothing is a failed check.
npm_due() {
    local outdated
    outdated="$(npm outdated -g --parseable)" || [[ -n "$outdated" ]] || return 1
    awk -F: '$2 != $3 {
        name = $3; current = $3; wanted = $2
        sub(/@[^@]*$/, "", name); sub(/.*@/, "", current); sub(/.*@/, "", wanted)
        print name, current, "->", wanted
    }' <<<"$outdated"
}

is_installed npm || exit 0

if ! due="$(npm_due)"; then
    print_error "Could not check global npm packages for upgrades"
    exit 1
fi
[[ -n "$due" ]] || exit 0

# NodeSource and distro Node keep global packages under /usr; Homebrew and nvm
# keep them writable by the user, where sudo would leave root-owned files.
if [[ -w "$(npm root -g)" ]]; then
    npm update -g
else
    run_as_root npm update -g
fi || {
    print_error "npm update -g failed"
    exit 1
}
report_upgraded "$due" npm_due
