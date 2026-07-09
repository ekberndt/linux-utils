#!/bin/bash

# Shared helpers for per-tool config sync scripts.
# Set DRY_RUN=true in the environment to preview without changing files.

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

# One timestamp per run, shared across all tools so all backups in a single
# invocation share the same suffix.
TIMESTAMP="${TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"

# apply_link <absolute-source> <absolute-target>
# Create a symlink at <target> pointing to <source>. Idempotent. If <target>
# already exists as a non-symlink (or symlink to something else), back it up
# with a .bak.<TIMESTAMP> suffix before linking.
apply_link() {
    local src="$1" dst="$2"
    local dry_run="${DRY_RUN:-false}"

    if [ ! -e "$src" ]; then
        print_error "missing in repo: $src"
        return 1
    fi

    if [ "$dry_run" = false ]; then
        mkdir -p "$(dirname "$dst")"
    fi

    if [ -L "$dst" ]; then
        local current
        current="$(readlink "$dst")"
        if [ "$current" = "$src" ]; then
            print_success "already linked: $dst"
            return 0
        fi
        if [ "$dry_run" = true ]; then
            print_warning "would relink: $dst (currently -> $current)"
        else
            rm "$dst"
            ln -s "$src" "$dst"
            print_success "relinked: $dst (was -> $current)"
        fi
    elif [ -e "$dst" ]; then
        local backup="${dst}.bak.${TIMESTAMP}"
        if [ "$dry_run" = true ]; then
            print_warning "would back up + link: $dst -> $(basename "$backup")"
        else
            mv "$dst" "$backup"
            ln -s "$src" "$dst"
            print_warning "backed up existing $dst -> $(basename "$backup")"
        fi
    else
        if [ "$dry_run" = true ]; then
            print_success "would link: $dst"
        else
            ln -s "$src" "$dst"
            print_success "linked: $dst"
        fi
    fi
}

# is_repo_link_tree <dir> <skills-root>
# True when <dir> holds nothing but symlinks into <skills-root>, i.e. we made it.
is_repo_link_tree() {
    local dir="$1" root="$2" f
    [ -d "$dir" ] && [ ! -L "$dir" ] || return 1

    while IFS= read -r -d '' f; do
        [ -L "$f" ] || return 1
        case "$(readlink "$f")" in
            "$root"/*) ;;
            *) return 1 ;;
        esac
    done < <(find "$dir" ! -type d -print0)
}

# apply_skill_links <repo-skills-dir> <target-skills-dir>
# Symlink each skill directory whole, so its internal layout stays the repo's business.
apply_skill_links() {
    local src_root="$1" dst_root="$2"

    local skill dst
    for skill in "$src_root"/*/; do
        skill="${skill%/}"
        dst="$dst_root/$(basename "$skill")"

        # Our own per-file links carry nothing worth keeping; only a user's
        # files reach apply_link's backup.
        if is_repo_link_tree "$dst" "$src_root"; then
            if [ "${DRY_RUN:-false}" = true ]; then
                print_success "would replace per-file links: $dst"
                continue
            fi
            rm -r -- "$dst"
        fi

        apply_link "$skill" "$dst"
    done
}
