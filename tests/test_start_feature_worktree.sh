#!/bin/bash
set -uo pipefail

# Drive the real helper against a throwaway clone. Every task starts here, so
# where it puts the checkout decides whether the repo's parent directory fills
# up with one loose folder per task.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

start="$ROOT/skills/worktree/scripts/start_feature_worktree.sh"
tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf -- "$tmp"' EXIT

# A HOME without ~/.agents, so the helper cannot rename the tmux window of
# whoever runs the tests.
export HOME="$tmp/home"
mkdir "$HOME"

git init -q --bare -b main "$tmp/origin.git"
git init -q -b main "$tmp/seed"
git -C "$tmp/seed" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$tmp/seed" remote add origin "$tmp/origin.git"
git -C "$tmp/seed" push -q origin main
git clone -q "$tmp/origin.git" "$tmp/repo"

first="$tmp/repo__worktrees/feat-first-task"
out="$(cd "$tmp/repo" && bash "$start" feat/first-task 2>&1)"
assert_contains "the first worktree creates the folder beside the repo" "$out" \
    "Created worktree: $first"
assert_eq "it checks out the new branch" \
    "$(git -C "$first" branch --show-current)" "feat/first-task"

# An agent already in a worktree starts the next task from there; the folder
# belongs to the primary checkout, not to whichever worktree it ran in.
second="$tmp/repo__worktrees/fix-second-task"
out="$(cd "$first" && bash "$start" fix/second-task 2>&1)"
assert_contains "a worktree started from another worktree lands beside the primary checkout" \
    "$out" "Created worktree: $second"
assert_eq "it checks out the new branch" \
    "$(git -C "$second" branch --show-current)" "fix/second-task"

assert_eq "worktrees leave no loose folders beside the repo" \
    "$(cd "$tmp" && echo *)" "home origin.git repo repo__worktrees seed"

test_result
