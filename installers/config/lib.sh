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

# inject_config <repo-relative-source> <target>
# Merge a tracked config into the copy the agent rewrites. Run through python3
# rather than the shebang so the checkout's exec bits do not matter.
inject_config() {
    python3 "$REPO_ROOT/scripts/inject-config" "$REPO_ROOT/$1" "$2"
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
        fi
    elif [[ -e "$dst" ]]; then
        local backup="${dst}.bak.${TIMESTAMP}"
        if [[ "$DRY_RUN" == true ]]; then
            print_warning "would back up + link: $dst -> $(basename "$backup")"
        else
            mv "$dst" "$backup"
            ln -s "$src" "$dst"
            print_warning "backed up existing $dst -> $(basename "$backup")"
        fi
    elif [[ "$DRY_RUN" == true ]]; then
        print_success "would link: $dst"
    else
        ln -s "$src" "$dst"
        print_success "linked: $dst"
    fi
}

# remove_stale_path <path>
# Delete a path a previous sync created and no longer manages.
remove_stale_path() {
    local path="$1"

    [[ -e "$path" || -L "$path" ]] || return 0

    if [[ "$DRY_RUN" == true ]]; then
        print_warning "would remove: $path"
    elif [[ -L "$path" || ! -d "$path" ]]; then
        rm -- "$path"
        print_success "removed: $path"
    else
        rm -r -- "$path"
        print_success "removed dir: $path"
    fi
}

# True when <dir> holds nothing but symlinks into <root>, i.e. we made it.
is_repo_link_tree() {
    local dir="$1" root="$2" file
    [[ -d "$dir" && ! -L "$dir" ]] || return 1

    while IFS= read -r -d '' file; do
        [[ -L "$file" ]] || return 1
        case "$(readlink "$file")" in
            "$root"/*) ;;
            *) return 1 ;;
        esac
    done < <(find "$dir" ! -type d -print0)
}

# apply_skill_links <repo-skills-dir> <target-skills-dir>
# Symlink each skill directory whole, so its layout stays the repo's business.
apply_skill_links() {
    local src_root="$1" dst_root="$2" skill dst

    for skill in "$src_root"/*/; do
        skill="${skill%/}"
        dst="$dst_root/$(basename "$skill")"

        # Our own per-file links carry nothing worth keeping; only a user's
        # files reach apply_link's backup.
        if is_repo_link_tree "$dst" "$src_root"; then
            if [[ "$DRY_RUN" == true ]]; then
                print_success "would replace per-file links: $dst"
                continue
            fi
            rm -r -- "$dst"
        fi

        apply_link "$skill" "$dst"
    done
}
