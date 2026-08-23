#!/usr/bin/env bash
# cleanup_worktrees.sh: remove the worktrees an agent has finished with, and the
# branches that only existed to hold them.
#
# A worktree goes only once its work has landed: its commits are already in the
# default branch, or GitHub says its PR merged. Pushing is not enough. A branch
# with an open PR is still being revised — usually by the agent that opened it,
# which pushes to publish a review and keeps working — so it stays.
#
# --self also retires the worktree this runs from, for an agent closing out its
# own session once its PRs have landed. It is judged by the same rules, it goes
# last, and it leaves the caller standing in a directory that no longer exists.
#
# Usage: cleanup_worktrees.sh [--dry-run] [--self]
set -euo pipefail

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

dry_run=false
include_self=false
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=true ;;
    --self) include_self=true ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"

primary="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
current="$(git rev-parse --show-toplevel)"

# Judging "merged" against a stale remote-tracking ref would keep a worktree
# whose PR landed minutes ago.
git fetch --quiet --prune origin 2>/dev/null || true

base="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
base="${base:-main}"
base_ref="refs/remotes/origin/$base"
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

# pr_state <branch> -> MERGED, OPEN, CLOSED, or empty when GitHub knows no PR.
# Asked once per worktree: gh is by far the slowest thing in this script.
pr_state() {
  local branch="$1"
  [ -n "$branch" ] || return 0
  command -v gh >/dev/null 2>&1 || return 0
  gh pr list --head "$branch" --state all --limit 1 --json state -q '.[0].state' 2>/dev/null || true
}

keep() {
  printf 'keep    %s: %s\n' "$1" "$2"
}

# consider <path> <branch> <skip_pane_check> -> print a verdict, and remove the
# worktree when its work has landed. 0 if it went, 1 if it stayed.
consider() {
  local path="$1" branch="$2" skip_pane_check="$3" state

  if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
    keep "$path" "uncommitted changes"
    return 1
  fi
  if [ "$skip_pane_check" = false ] && in_use "$path"; then
    keep "$path" "a tmux pane is still in it"
    return 1
  fi

  # Ancestry settles the cheap case and costs no network: a merge or a
  # fast-forward leaves the commits reachable from the default branch.
  if ! git -C "$path" merge-base --is-ancestor HEAD "$base_ref" 2>/dev/null; then
    state="$(pr_state "$branch")"
    case "$state" in
      # A squash merge rewrites the commits, so ancestry cannot see them and
      # the head branch is usually deleted with it. GitHub is the only witness.
      MERGED) ;;
      OPEN)
        keep "$path" "its PR is open, not merged — still being worked on"
        return 1
        ;;
      *)
        keep "$path" "work that has not landed on $base"
        return 1
        ;;
    esac
  fi

  if [ "$dry_run" = true ]; then
    printf 'would remove %s%s\n' "$path" "${branch:+ ($branch)}"
    return 0
  fi

  # Driven from the primary checkout, not from $path: this may be the worktree
  # the script is standing in, and git needs a directory that outlives it.
  # A refusal is one directory's problem, so report it and let the rest of the
  # run finish rather than aborting on set -e. The usual cause is a build tool's
  # ignored symlink, which git will not delete and --force is not worth.
  if ! git -C "$primary" worktree remove "$path" 2>/dev/null; then
    printf 'failed  %s: git would not remove it; delete the directory by hand\n' "$path" >&2
    return 1
  fi
  # -D, not -d: the work is provably landed by the check above, while -d refuses
  # a squash-merged branch — the usual shape here — because its commits are not
  # ancestors of anything left.
  if [ -n "$branch" ]; then
    git -C "$primary" branch -D "$branch" >/dev/null
  fi
  printf 'removed %s%s\n' "$path" "${branch:+ ($branch)}"
  return 0
}

removed=0
kept=0
path=""
branch=""
self_path=""
self_branch=""

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
    # Deferred to the end of the run: removing it invalidates the directory this
    # script and everything after it are standing in.
    self_path="$path"
    self_branch="$branch"
  elif consider "$path" "$branch" false; then
    removed=$((removed + 1))
  else
    kept=$((kept + 1))
  fi

  path=""
  branch=""
done < <(git worktree list --porcelain; printf '\n')

if [ -n "$self_path" ]; then
  if [ "$include_self" = false ]; then
    keep "$self_path" "you are working in it; --self retires it too"
    kept=$((kept + 1))
  else
    # Stand in the primary checkout first, so this script keeps a working
    # directory once its own goes away.
    cd "$primary"
    # A pane sitting in this worktree is the session that just asked for it to
    # be retired, so --self looks past the pane check here and nowhere else.
    if consider "$self_path" "$self_branch" true; then
      removed=$((removed + 1))
      [ "$dry_run" = true ] ||
        printf 'note    your shell is still in a directory that is gone; cd %s\n' "$primary"
    else
      kept=$((kept + 1))
    fi
  fi
fi

printf '%d removed, %d kept\n' "$removed" "$kept"
