#!/bin/bash

# Shared helpers for the per-tool config sync scripts. Sourcing this defines
# REPO_ROOT. Set DRY_RUN=true in the environment to preview without changes.

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$CONFIG_DIR/../.." && pwd)"

# shellcheck source=../lib/common.sh
source "$REPO_ROOT/installers/lib/common.sh"

# One timestamp per run, so every backup a single invocation makes shares a suffix.
TIMESTAMP="${TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"

DRY_RUN="${DRY_RUN:-false}"

# inject_config <repo-relative-source>... <target>
# Merge tracked config(s) into the copy the agent rewrites. Run through python3
# rather than the shebang so the checkout's exec bits do not matter.
inject_config() {
    local target="${!#}" result
    local -a sources=()
    local i
    for (( i = 1; i < $#; i++ )); do
        sources+=("$REPO_ROOT/${!i}")
    done
    result="$(python3 "$REPO_ROOT/scripts/inject-config" "${sources[@]}" "$target")" || return
    echo "$result"
    if [[ "$result" == *"injected config: "* ]]; then
        record_status updated "$target (merged)"
    fi
}

# Collect before matching: `grep -q` exits on the first hit, and under pipefail
# the SIGPIPE it deals gsettings would read back as "schema missing".
gsettings_has_schema() {
    local schemas
    command -v gsettings >/dev/null 2>&1 || return 1
    schemas="$(gsettings list-schemas 2>/dev/null)" || return 1
    grep -qx "$1" <<<"$schemas"
}

# apply_link <absolute-source> <absolute-target>
# Symlink target -> source, backing up anything already there. Idempotent.
apply_link() {
    local src="$1" dst="$2"

    if [[ ! -e "$src" ]]; then
        print_error "missing in repo: $src"
        return 1
    fi

    [[ "$DRY_RUN" == false ]] && mkdir -p "$(dirname "$dst")"

    if [[ -L "$dst" ]]; then
        local current
        current="$(readlink "$dst")"
        if [[ "$current" == "$src" ]]; then
            print_success "already linked: $dst"
        elif [[ "$DRY_RUN" == true ]]; then
            print_warning "would relink: $dst (currently -> $current)"
        else
            rm "$dst"
            ln -s "$src" "$dst"
            print_success "relinked: $dst (was -> $current)"
            record_status updated "$dst (relinked)"
        fi
    elif [[ -e "$dst" ]]; then
        local backup="${dst}.bak.${TIMESTAMP}"
        if [[ "$DRY_RUN" == true ]]; then
            print_warning "would back up + link: $dst -> $(basename "$backup")"
        else
            mv "$dst" "$backup"
            ln -s "$src" "$dst"
            print_warning "backed up existing $dst -> $(basename "$backup")"
            record_status updated "$dst (linked)"
        fi
    elif [[ "$DRY_RUN" == true ]]; then
        print_success "would link: $dst"
    else
        ln -s "$src" "$dst"
        print_success "linked: $dst"
        record_status updated "$dst (linked)"
    fi
}

# apply_skill_links <repo-skills-dir> <target-skills-dir>
# Symlink each skill directory whole, so its layout stays the repo's business.
apply_skill_links() {
    local src_root="$1" dst_root="$2" skill link

    # A skill is a directory with a SKILL.md. Deleting one in git can leave its
    # ignored files (__pycache__) behind, and that husk is not a skill.
    for skill in "$src_root"/*/SKILL.md; do
        skill="$(dirname "$skill")"
        apply_link "$skill" "$dst_root/$(basename "$skill")"
    done

    # A skill renamed or deleted in the repo leaves its old link behind.
    for link in "$dst_root"/*; do
        [[ -L "$link" && ! -e "$link/SKILL.md" && "$(readlink "$link")" == "$src_root"/* ]] || continue
        if [[ "$DRY_RUN" == true ]]; then
            print_warning "would remove: $link"
        else
            rm -- "$link"
            print_updated "$link (removed)"
        fi
    done
}
