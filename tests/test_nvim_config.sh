#!/bin/bash
set -euo pipefail

# Config sync must link every spec in installers/lazyvim/plugins/, not a
# hardcoded subset — a new plugin that only the LazyVim installer links would
# vanish on the next config run.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

plugin_src="$ROOT/installers/lazyvim/plugins"
specs=()
for f in "$plugin_src"/*.lua; do
    [ -e "$f" ] || continue
    specs+=("$(basename "$f")")
done
((${#specs[@]}))

HOME="$tmp" TIMESTAMP=stamp DRY_RUN=false bash "$ROOT/installers/config/nvim.sh"

for spec in "${specs[@]}"; do
    got="$(readlink "$tmp/.config/nvim/lua/plugins/$spec")"
    assert_eq "links $spec" "$got" "$plugin_src/$spec"
done

test_result
