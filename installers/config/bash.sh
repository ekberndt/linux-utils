#!/bin/bash

# Sync Bash aliases into ~/.bash_aliases and ensure ~/.bashrc sources them.
#
# Honors DRY_RUN=true. Usually invoked via the orchestrator
# (`installers/config/install.sh`); also runnable standalone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

ALIASES_SRC="$REPO_ROOT/.bash_aliases"
ALIASES_DST="$HOME/.bash_aliases"
BASHRC="$HOME/.bashrc"
BLOCK_START="# >>> linux-utils bash aliases >>>"
BLOCK_END="# <<< linux-utils bash aliases <<<"

bashrc_sources_aliases() {
    local bashrc="$1"

    if [ ! -f "$bashrc" ]; then
        return 1
    fi

    awk '
        /^[[:space:]]*#/ { next }
        /(^|[[:space:]])(\.|source)[[:space:]]+[^#;]*\.bash_aliases([^[:alnum:]_./-]|$)/ { found=1 }
        END { exit found ? 0 : 1 }
    ' "$bashrc"
}

ensure_bashrc_sources_aliases() {
    local bashrc="$1"
    local dry_run="${DRY_RUN:-false}"

    if bashrc_sources_aliases "$bashrc"; then
        print_success "already sources: $bashrc"
        return 0
    fi

    if [ "$dry_run" = true ]; then
        if [ -e "$bashrc" ]; then
            print_warning "would back up + append linux-utils aliases source block: $bashrc"
        else
            print_success "would create aliases source block: $bashrc"
        fi
        return 0
    fi

    mkdir -p "$(dirname "$bashrc")"

    if [ -e "$bashrc" ]; then
        local backup="${bashrc}.bak.${TIMESTAMP}"
        cp "$bashrc" "$backup"
        print_warning "backed up existing $bashrc -> $(basename "$backup")"
    fi

    local needs_blank=false
    if [ -s "$bashrc" ]; then
        needs_blank=true
    fi

    {
        if [ "$needs_blank" = true ]; then
            printf '\n'
        fi
        printf '%s\n' "$BLOCK_START"
        printf '%s\n' "if [ -f \"\$HOME/.bash_aliases\" ]; then"
        printf '%s\n' "    . \"\$HOME/.bash_aliases\""
        printf '%s\n' 'fi'
        printf '%s\n' "$BLOCK_END"
    } >> "$bashrc"

    print_success "added aliases source block: $bashrc"
}

apply_link "$ALIASES_SRC" "$ALIASES_DST"
ensure_bashrc_sources_aliases "$BASHRC"

# Child processes cannot inject into the caller's shell. Tmux can reload its
# server in-process; bash cannot. Point interactive users at a reload, or use
# the linux-utils-config shell function (which sources after syncing).
if [ "${DRY_RUN:-false}" = true ]; then
    print_success "would note: source ~/.bash_aliases to load in the current shell"
else
    print_warning "aliases linked for new shells; this shell: source ~/.bash_aliases"
    print_warning "(or run linux-utils-config, which sources after sync)"
fi
