#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: start_feature_worktree.sh <type/slug> [--path DIR]

Creates a new git worktree and branch from freshly fetched origin/main.

Branch types: feat, fix, docs, refactor, perf, test, build, ci, chore
USAGE
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

branch=""
worktree_dir=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --path)
      [ "$#" -ge 2 ] || die "--path requires a directory"
      worktree_dir="$2"
      shift 2
      ;;
    --*)
      die "unknown option: $1"
      ;;
    *)
      [ -z "$branch" ] || die "unexpected extra argument: $1"
      branch="$1"
      shift
      ;;
  esac
done

[ -n "$branch" ] || { usage >&2; die "branch name is required"; }

case "$branch" in
  feat/*|fix/*|docs/*|refactor/*|perf/*|test/*|build/*|ci/*|chore/*) ;;
  *)
    die "branch must use <type>/<slug> with type feat|fix|docs|refactor|perf|test|build|ci|chore"
    ;;
esac

slug=${branch#*/}
[ -n "$slug" ] || die "branch slug cannot be empty"
case "$slug" in
  *[!a-z0-9-]*)
    die "branch slug must contain only lowercase letters, digits, and hyphens"
    ;;
  -*|*-)
    die "branch slug cannot start or end with a hyphen"
    ;;
esac

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"
root=$(git rev-parse --show-toplevel)
repo=$(basename "$root")
previous_branch=$(git branch --show-current 2>/dev/null || true)
previous_sha=$(git rev-parse --short HEAD 2>/dev/null || true)
base_ref="refs/remotes/origin/main"

git show-ref --verify --quiet "refs/heads/$branch" \
  && die "branch '$branch' already exists locally"

git remote get-url origin >/dev/null 2>&1 \
  || die "origin remote is required to fetch origin/main before creating a worktree"

if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  die "branch '$branch' already exists on origin"
else
  remote_check_status=$?
  [ "$remote_check_status" -eq 2 ] || die "could not check origin for existing branch '$branch'"
fi

if [ -z "$worktree_dir" ]; then
  worktree_dir="$(dirname "$root")/${repo}-${branch//\//-}"
fi

case "$worktree_dir" in
  /*) ;;
  *) worktree_dir="$(pwd)/$worktree_dir" ;;
esac

[ ! -e "$worktree_dir" ] || die "worktree path already exists: $worktree_dir"
parent_dir=$(dirname "$worktree_dir")
[ -d "$parent_dir" ] || die "parent directory does not exist: $parent_dir"

git fetch origin +refs/heads/main:"$base_ref"

base_sha=$(git rev-parse --short "$base_ref^{commit}" 2>/dev/null) \
  || die "base start point 'origin/main' does not resolve to a commit"

git worktree add --no-track "$worktree_dir" -b "$branch" "$base_ref"
new_sha=$(git -C "$worktree_dir" rev-parse --short HEAD)

printf 'Created worktree: %s\n' "$worktree_dir"
printf 'Created branch: %s\n' "$branch"
printf 'Based on: origin/main (%s)\n' "$base_sha"
printf 'Worktree HEAD: %s\n' "$new_sha"

if [ -n "$previous_branch" ]; then
  printf 'Previous branch preserved: %s' "$previous_branch"
  [ -n "$previous_sha" ] && printf ' (%s)' "$previous_sha"
  printf '\n'
fi
