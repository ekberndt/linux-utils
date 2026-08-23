#!/usr/bin/env bash
# cleanup_worktrees.sh: remove the worktrees an agent has finished with, and the
# branches that only existed to hold them.
#
# A worktree goes only when nothing in it lives solely on this disk: its commits
# are in the default branch, GitHub says its PR merged, or it is fully pushed to
# an upstream where an open PR is holding them. Anything else is reported and
# left where it is — including a worktree another agent is sitting in.
#
# Usage: cleanup_worktrees.sh [--dry-run]
set -euo pipefail

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

dry_run=false
case "${1:-}" in
  --dry-run) dry_run=true ;;
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) die "unknown option: $1" ;;
esac

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"

primary="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
current="$(git rev-parse --show-toplevel)"

# Judging "merged" against a stale remote-tracking ref would keep a worktree
# whose PR landed minutes ago. --prune is what drops the upstream ref of a head
# branch GitHub deleted on merge, so the checks below see that branch as gone
# rather than as unpushed work.
git fetch --quiet --prune origin 2>/dev/null || true

base="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
base_ref="refs/remotes/origin/${base:-main}"
git rev-parse --verify --quiet "$base_ref" >/dev/null ||
  die "no $base_ref to compare against; fetch origin first"

# A pane's cwd, and the worktree an agent moved to (see scripts/agent-tmux), are
# the two ways a live agent says which checkout is still under it. Collected
# once: this is the only question worth asking tmux, and it has no answer at all
# when no server is running.
busy_paths=""
if command -v tmux >/dev/null 2>&1; then
  busy_paths="$(
    {
      tmux list-panes -a -F '#{pane_current_path}' 2>/dev/null || true
      tmux list-windows -a -F '#{@agent_dir}' 2>/dev/null || true
    } | sort -u
  )"
fi

# in_use <path> -> a live pane is in this worktree, or somewhere under it.
in_use() {
  local path="$1" busy
  while IFS= read -r busy; do
    [ -n "$busy" ] || continue
    case "$busy" in
      "$path" | "$path"/*) return 0 ;;
    esac
  done <<< "$busy_paths"
  return 1
}

# finished <dir> <branch> -> nothing in this worktree exists only here. Three
# ways that is true, cheapest first:
#   - its commits are already in the default branch (a merge or fast-forward)
#   - it is fully pushed to its upstream, where an open PR holds the work
#   - GitHub says its PR merged: a squash merge rewrites the commits, so the
#     first test cannot see them and the head branch is usually deleted with it
finished() {
  local dir="$1" branch="$2" upstream

  git -C "$dir" merge-base --is-ancestor HEAD "$base_ref" 2>/dev/null && return 0

  upstream="$(git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  if [ -n "$upstream" ] && [ "$(git -C "$dir" rev-list --count "$upstream..HEAD")" -eq 0 ]; then
    return 0
  fi

  [ -n "$branch" ] || return 1
  command -v gh >/dev/null 2>&1 || return 1
  [ "$(gh pr list --head "$branch" --state merged --limit 1 --json state -q '.[0].state' 2>/dev/null)" = MERGED ]
}

keep() {
  printf 'keep    %s: %s\n' "$1" "$2"
}

removed=0
kept=0
path=""
branch=""

# --porcelain emits a blank-line-separated record per worktree; the branch line
# is absent on a detached HEAD, which is why branch is reset per record.
while IFS= read -r line; do
  case "$line" in
    worktree\ *)
      path="${line#worktree }"
      branch=""
      continue
      ;;
    branch\ *)
      branch="${line#branch refs/heads/}"
      continue
      ;;
    "") ;;
    *) continue ;;
  esac

  [ -n "$path" ] || continue

  if [ "$path" = "$primary" ]; then
    keep "$path" "the main checkout"
    kept=$((kept + 1))
  elif [ "$path" = "$current" ]; then
    keep "$path" "you are working in it"
    kept=$((kept + 1))
  elif [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
    keep "$path" "uncommitted changes"
    kept=$((kept + 1))
  elif in_use "$path"; then
    keep "$path" "a tmux pane is still in it"
    kept=$((kept + 1))
  elif ! finished "$path" "$branch"; then
    keep "$path" "commits that exist nowhere else"
    kept=$((kept + 1))
  elif [ "$dry_run" = true ]; then
    printf 'would remove %s%s\n' "$path" "${branch:+ ($branch)}"
    removed=$((removed + 1))
  else
    git worktree remove "$path"
    # -D, not -d: the branch is provably preserved by the check above, while -d
    # refuses a squash-merged branch — the usual shape here — because its
    # commits are not ancestors of anything left.
    if [ -n "$branch" ]; then
      git branch -D "$branch" >/dev/null
    fi
    printf 'removed %s%s\n' "$path" "${branch:+ ($branch)}"
    removed=$((removed + 1))
  fi

  path=""
  branch=""
done < <(git worktree list --porcelain; printf '\n')

printf '%d removed, %d kept\n' "$removed" "$kept"
