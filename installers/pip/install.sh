#!/bin/bash
set -uo pipefail

# Packages installed with `pip install --user`. The installer puts none here;
# they are the user's.

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

# "name version -> latest" per user package, from a two-line header and then
# "name version latest type" rows.
pip_due() {
    python3 -m pip list --user --outdated --format=columns | awk 'NR > 2 { print $1, $2, "->", $3 }'
}

# python3 is the virtualenv's while one is active, and it has no user site.
if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    print_skipped "pip user packages (virtualenv $VIRTUAL_ENV is active)"
    exit 0
fi
python3 -m pip --version >/dev/null 2>&1 || exit 0
# Listing what is installed stays offline; without user packages there is
# nothing to ask the index about.
[[ -n "$(python3 -m pip list --user --format=freeze 2>/dev/null)" ]] || exit 0

if ! due="$(pip_due)"; then
    print_error "Could not check pip user packages for upgrades"
    exit 1
fi
if [[ -z "$due" ]]; then
    pip_index_reachable python3 -m pip && exit 0
    print_error "Could not reach the package index to check pip user packages"
    exit 1
fi

packages=()
while read -r name _; do
    packages+=("$name")
done <<<"$due"
if ! python3 -m pip install --user --upgrade "${packages[@]}"; then
    print_error "pip install --user --upgrade failed"
    exit 1
fi
report_upgraded "$due" pip_due
