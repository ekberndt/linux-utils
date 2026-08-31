#!/bin/bash
set -euo pipefail

# Link ~/.bash_aliases and make sure ~/.bashrc sources it. Honors DRY_RUN.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

BASHRC="$HOME/.bashrc"

# Any uncommented `. ~/.bash_aliases` counts, however the user wrote it, so a
# stock Ubuntu .bashrc does not get a second block appended to it. A bash loop
# instead of awk: BSD awk rejects the POSIX class used in the original pattern.
bashrc_sources_aliases() {
    local line trimmed
    [[ -f "$1" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ "$trimmed" == \#* ]] && continue
        if [[ "$trimmed" == '.'*'.bash_aliases'* || "$trimmed" == 'source '*'.bash_aliases'* ]]; then
            return 0
        fi
    done < "$1"
    return 1
}

ensure_bashrc_sources_aliases() {
    local bashrc="$1"

    if bashrc_sources_aliases "$bashrc"; then
        print_success "already sources: $bashrc"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_success "would add aliases source block: $bashrc"
        return 0
    fi

    mkdir -p "$(dirname "$bashrc")"
    if [[ -e "$bashrc" ]]; then
        cp "$bashrc" "${bashrc}.bak.${TIMESTAMP}"
        print_warning "backed up existing $bashrc -> $(basename "${bashrc}.bak.${TIMESTAMP}")"
    fi

    cat >> "$bashrc" <<'EOF'

# >>> linux-utils bash aliases >>>
if [ -f "$HOME/.bash_aliases" ]; then
    . "$HOME/.bash_aliases"
fi
# <<< linux-utils bash aliases <<<
EOF
    print_success "added aliases source block: $bashrc"
}

apply_link "$REPO_ROOT/.bash_aliases" "$HOME/.bash_aliases"
ensure_bashrc_sources_aliases "$BASHRC"
