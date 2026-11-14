#!/bin/bash
set -uo pipefail

# Global pnpm packages, as `pnpm update -g` updates them. The installer puts
# none here; they are the user's.

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

# "name current -> wanted" per package `pnpm update -g` would move. pnpm exits 1
# when it finds something outdated, so only a failure that lists nothing is a
# failed check.
pnpm_due() {
    local outdated
    outdated="$(pnpm outdated -g --format json)" || [[ -n "$outdated" ]] || return 1
    python3 -I -c '
import json, sys
for name, dep in json.load(sys.stdin).items():
    if dep.get("wanted") != dep.get("current"):
        print(name, dep.get("current"), "->", dep.get("wanted"))
' <<<"$outdated"
}

is_installed pnpm || exit 0

if ! due="$(pnpm_due)"; then
    print_error "Could not check global pnpm packages for upgrades"
    exit 1
fi
[[ -n "$due" ]] || exit 0

if ! pnpm update -g; then
    print_error "pnpm update -g failed"
    exit 1
fi
report_upgraded "$due" pnpm_due
