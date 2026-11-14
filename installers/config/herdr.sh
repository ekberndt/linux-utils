#!/bin/bash
set -euo pipefail

# Link the agent-tree mod and the layout that shows it into the Herdr app's
# home, where the app loads them; Settings > Look switches to the layout.
# Herdr's shipped layouts stay as they are. Honors DRY_RUN.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# The app's own lookup order.
APP_HOME="${HERDR_APP_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr-app}"

apply_link "$REPO_ROOT/herdr/mods/agent-tree" "$APP_HOME/mods/agent-tree"
apply_link "$REPO_ROOT/herdr/layouts/agent-tree.json" "$APP_HOME/layouts/agent-tree.json"
