#!/bin/bash

# Universal config sync.
# Symlinks tracked config in this repo into its user-config locations so edits
# in either place stay in sync. Currently covers:
#   - Claude Code: settings, custom skills, helper scripts -> ~/.claude/
#   - Neovim:      LazyVim plugin specs                    -> ~/.config/nvim/lua/plugins/
# Conflicting non-symlink files at the target are backed up with a timestamp.
#
# Usage:
#   install.sh              # apply changes
#   install.sh --dry-run    # print what would happen, change nothing

set -euo pipefail

DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=true ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

CLAUDE_TARGET="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
NVIM_TARGET="$HOME/.config/nvim"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# Each entry: <source-relative-to-repo-root>|<absolute-target>
# Listed explicitly so we never sync private state (sessions, history, credentials).
LINKS=(
    # --- Claude Code ---
    "claude/settings.json|$CLAUDE_TARGET/settings.json"
    "claude/scripts/cc-fanout|$CLAUDE_TARGET/scripts/cc-fanout"
    "claude/scripts/statusline-worktree|$CLAUDE_TARGET/scripts/statusline-worktree"
    "claude/skills/new-branch/SKILL.md|$CLAUDE_TARGET/skills/new-branch/SKILL.md"
    "claude/skills/pr/SKILL.md|$CLAUDE_TARGET/skills/pr/SKILL.md"
    "claude/skills/pr/references/move-from-base.md|$CLAUDE_TARGET/skills/pr/references/move-from-base.md"

    # --- Neovim (LazyVim plugin specs bundled with the lazyvim installer) ---
    "installers/lazyvim/plugins/vim-tmux-navigator.lua|$NVIM_TARGET/lua/plugins/vim-tmux-navigator.lua"
)

# Keep helper scripts executable in this checkout
# (git tracks the +x bit, but a fresh editor write may drop it).
if [ "$DRY_RUN" = false ]; then
    chmod +x "$REPO_ROOT/claude/scripts/cc-fanout" \
             "$REPO_ROOT/claude/scripts/statusline-worktree" 2>/dev/null || true
fi

if [ "$DRY_RUN" = true ]; then
    print_header "DRY RUN - no files will be changed"
fi
print_header "Syncing config files"

for entry in "${LINKS[@]}"; do
    src_rel="${entry%%|*}"
    dst="${entry##*|}"
    src="$REPO_ROOT/$src_rel"

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
            print_success "already linked: $dst"
            continue
        fi
        if [ "$DRY_RUN" = true ]; then
            print_warning "would relink: $dst (currently -> $current)"
        else
            rm "$dst"
            ln -s "$src" "$dst"
            print_success "relinked: $dst (was -> $current)"
        fi
    elif [ -e "$dst" ]; then
        backup="${dst}.bak.${TIMESTAMP}"
        if [ "$DRY_RUN" = true ]; then
            print_warning "would back up + link: $dst -> $(basename "$backup")"
        else
            mv "$dst" "$backup"
            ln -s "$src" "$dst"
            print_warning "backed up existing $dst -> $(basename "$backup")"
        fi
    else
        if [ "$DRY_RUN" = true ]; then
            print_success "would link: $dst"
        else
            ln -s "$src" "$dst"
            print_success "linked: $dst"
        fi
    fi
done

if [ "$DRY_RUN" = true ]; then
    echo
    echo "Dry run complete. Re-run without --dry-run to apply."
else
    print_success "Done."
fi
