#!/bin/bash
set -euo pipefail

# Run every per-tool config sync in order. Each tool lives next to this file as
# <tool>.sh and is also runnable standalone; add one by dropping it in and
# appending its name to TOOLS.
#
# Usage:
#   install.sh              # apply changes
#   install.sh --dry-run    # print what would happen, change nothing

DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=true ;;
        -h|--help) sed -n '4,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done
export DRY_RUN

# Shared so every backup made in a single run gets the same suffix.
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
export TIMESTAMP

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TOOLS=(
    bash
    agents
    claude
    codex
    grok
    opencode
    nvim
    tmux
    gnome
    power
    ssh
    aerospace
)

[[ "$DRY_RUN" == true ]] && print_header "DRY RUN - no files will be changed"

for tool in "${TOOLS[@]}"; do
    print_header "Syncing $tool config"
    bash "$CONFIG_DIR/$tool.sh"
done

if [[ "$DRY_RUN" == true ]]; then
    echo
    echo "Dry run complete. Re-run without --dry-run to apply."
else
    print_success "Done."
fi
