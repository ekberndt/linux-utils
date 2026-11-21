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

if [[ -n "${PNPM_HOME:-}" ]]; then
    pnpm_home="$PNPM_HOME"
elif [[ -n "${XDG_DATA_HOME:-}" ]]; then
    pnpm_home="$XDG_DATA_HOME/pnpm"
elif [[ "$(uname -s)" == Darwin ]]; then
    pnpm_home="$HOME/Library/pnpm"
else
    pnpm_home="$HOME/.local/share/pnpm"
fi
# pnpm refuses every `-g` command unless its global bin directory ($PNPM_HOME
# through pnpm 10, $PNPM_HOME/bin in pnpm 11) is on PATH. `pnpm setup` writes
# that only to interactive shell rc files, and a machine that has never run it
# (e.g. Corepack's /usr/bin/pnpm shim) has neither on PATH.
export PATH="$pnpm_home/bin:$pnpm_home:$PATH"

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
