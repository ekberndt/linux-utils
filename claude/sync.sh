#!/bin/bash

# Sync Claude Code config from this repo into ~/.claude/.
# Creates symlinks so edits in either place stay in sync.
# Conflicting non-symlink files at the target are backed up with a timestamp suffix.
#
# Usage:
#   sync.sh              # apply changes
#   sync.sh --dry-run    # print what would happen, change nothing

set -euo pipefail

DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=true ;;
        -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Shared helpers if available; otherwise fall back to plain echo.
if [ -f "$SCRIPT_DIR/../installers/lib/common.sh" ]; then
    # shellcheck source=../installers/lib/common.sh
    source "$SCRIPT_DIR/../installers/lib/common.sh"
else
    print_header()  { echo "=== $1 ==="; }
    print_success() { echo "OK  $1"; }
    print_warning() { echo "WARN $1"; }
    print_error()   { echo "ERR $1" >&2; }
fi

TARGET_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# repo_relative_path -> target_relative_path (relative to ~/.claude/)
# Keep this list explicit so we never sync private state (sessions, history, credentials).
LINKS=(
    "settings.json|settings.json"
    "scripts/cc-fanout|scripts/cc-fanout"
    "scripts/statusline-worktree|scripts/statusline-worktree"
    "skills/new-branch/SKILL.md|skills/new-branch/SKILL.md"
    "skills/pr/SKILL.md|skills/pr/SKILL.md"
    "skills/pr/references/move-from-base.md|skills/pr/references/move-from-base.md"
)

# Ensure script files are executable in this checkout
# (git tracks the +x bit, but a fresh write from the editor may not have it).
if [ "$DRY_RUN" = false ]; then
    chmod +x "$SCRIPT_DIR/scripts/cc-fanout" "$SCRIPT_DIR/scripts/statusline-worktree" 2>/dev/null || true
fi

if [ "$DRY_RUN" = true ]; then
    print_header "DRY RUN — no files will be changed"
fi
print_header "Syncing Claude Code config -> $TARGET_ROOT"

for entry in "${LINKS[@]}"; do
    src_rel="${entry%%|*}"
    dst_rel="${entry##*|}"
    src="$SCRIPT_DIR/$src_rel"
    dst="$TARGET_ROOT/$dst_rel"

    if [ ! -e "$src" ]; then
        print_error "missing in repo: $src_rel"
        continue
    fi

    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$(dirname "$dst")"
    fi

    if [ -L "$dst" ]; then
        current="$(readlink "$dst")"
        if [ "$current" = "$src" ]; then
            print_success "already linked: $dst_rel"
            continue
        fi
        if [ "$DRY_RUN" = true ]; then
            print_warning "would relink: $dst_rel (currently -> $current)"
        else
            rm "$dst"
            ln -s "$src" "$dst"
            print_success "relinked: $dst_rel (was -> $current)"
        fi
    elif [ -e "$dst" ]; then
        backup="${dst}.bak.${TIMESTAMP}"
        if [ "$DRY_RUN" = true ]; then
            print_warning "would back up + link: $dst_rel -> $(basename "$backup")"
        else
            mv "$dst" "$backup"
            ln -s "$src" "$dst"
            print_warning "backed up existing $dst_rel -> $(basename "$backup")"
        fi
    else
        if [ "$DRY_RUN" = true ]; then
            print_success "would link: $dst_rel"
        else
            ln -s "$src" "$dst"
            print_success "linked: $dst_rel"
        fi
    fi
done

if [ "$DRY_RUN" = true ]; then
    echo
    echo "Dry run complete. Re-run without --dry-run to apply."
else
    print_success "Done."
    echo
    echo "Next:"
    echo "  - Verify: claude doctor (or just run 'claude')"
    echo "  - On another machine: clone this repo, then run claude/sync.sh"
fi
