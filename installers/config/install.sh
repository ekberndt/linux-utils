#!/bin/bash

# Universal config sync orchestrator.
# Invokes every per-tool sync script listed in TOOLS, in order. Each tool
# script lives next to this file as <tool>.sh and is also runnable standalone.
#
# Usage:
#   install.sh              # apply changes
#   install.sh --dry-run    # print what would happen, change nothing
#
# To add a tool: drop <name>.sh in this directory and append <name> to TOOLS.

set -euo pipefail

DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=true ;;
        -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done
export DRY_RUN

# Shared timestamp so every backup made in a single run shares the same suffix.
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
export TIMESTAMP

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Per-tool config sync scripts, run in order.
TOOLS=(
    bash
    agents
    claude
    codex
    grok
    nvim
    tmux
)

if [ "$DRY_RUN" = true ]; then
    print_header "DRY RUN - no files will be changed"
fi

for tool in "${TOOLS[@]}"; do
    script="$SCRIPT_DIR/$tool.sh"
    if [ ! -f "$script" ]; then
        print_error "missing tool script: $script"
        continue
    fi
    print_header "Syncing $tool config"
    bash "$script"
done

if [ "$DRY_RUN" = true ]; then
    echo
    echo "Dry run complete. Re-run without --dry-run to apply."
else
    print_success "Done."
fi
