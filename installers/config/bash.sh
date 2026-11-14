#!/bin/bash
set -euo pipefail

# Link ~/.bash_aliases, make sure ~/.bashrc sources it, and link resync into
# ~/.local/bin, which ~/.bash_aliases (or ~/.zshrc for zsh users) puts on
# PATH. Honors DRY_RUN.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

BASHRC="$HOME/.bashrc"
ZSHRC="$HOME/.zshrc"
# shellcheck disable=SC2016 # Expanded when ~/.zshrc is sourced, not here.
LOCAL_BIN_PATH_LINE='[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"'

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
    print_updated "$bashrc (sources ~/.bash_aliases)"
}

# zsh, macOS's default shell, never reads ~/.bash_aliases. Every interactive
# zsh reads ~/.zshrc, login or not, so the PATH line goes there.
ensure_zshrc_has_local_bin() {
    if grep -Fqx "$LOCAL_BIN_PATH_LINE" "$ZSHRC" 2>/dev/null; then
        print_success "already on PATH: ~/.local/bin in $ZSHRC"
    elif [[ "$DRY_RUN" == true ]]; then
        print_success "would add ~/.local/bin to PATH: $ZSHRC"
    else
        printf '\n# linux-utils: resync lives in ~/.local/bin\n%s\n' "$LOCAL_BIN_PATH_LINE" >> "$ZSHRC"
        print_updated "$ZSHRC (~/.local/bin on PATH)"
    fi
}

apply_link "$REPO_ROOT/.bash_aliases" "$HOME/.bash_aliases"
ensure_bashrc_sources_aliases "$BASHRC"
apply_link "$REPO_ROOT/scripts/resync" "$HOME/.local/bin/resync"
# resync's earlier name; its link dangles once the checkout drops the file.
remove_stale_path "$HOME/.local/bin/upkeep"
if [[ "${SHELL:-}" == */zsh ]]; then
    ensure_zshrc_has_local_bin
fi
