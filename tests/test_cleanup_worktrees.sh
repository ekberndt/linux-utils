#!/bin/bash
set -uo pipefail

# Drive the real script against throwaway repos. Every worktree below is one of
# the states the script has to tell apart, and the two that matter most are the
# ones it must refuse to remove: work that exists nowhere else, and a checkout
# somebody is still in.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

cleanup="$ROOT/skills/cleanup/scripts/cleanup_worktrees.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

git_q() { git -c user.email=t@t -c user.name=t "$@"; }

# A real remote, so "pushed" and "merged" mean what they mean in a clone.
git init -q --bare -b main "$tmp/origin.git"
git_q init -q -b main "$tmp/seed"
git_q -C "$tmp/seed" commit -q --allow-empty -m init
git_q -C "$tmp/seed" remote add origin "$tmp/origin.git"
git_q -C "$tmp/seed" push -q origin main
repo="$tmp/repo"
git clone -q "$tmp/origin.git" "$repo"

# Already in the default branch: the shape a merged, fast-forwarded PR leaves.
git_q -C "$repo" worktree add -q "$tmp/wt-merged" -b feat/merged main

# Pushed to its own upstream: the shape of an open PR holding the work.
git_q -C "$repo" worktree add -q "$tmp/wt-pushed" -b feat/pushed main
git_q -C "$tmp/wt-pushed" commit -q --allow-empty -m pushed
git_q -C "$tmp/wt-pushed" push -q -u origin feat/pushed

# A commit that exists on this disk and nowhere else.
git_q -C "$repo" worktree add -q "$tmp/wt-local" -b feat/local main
git_q -C "$tmp/wt-local" commit -q --allow-empty -m local-only

# Merged, but with an edit in it. The branch state says go; the tree says no.
git_q -C "$repo" worktree add -q "$tmp/wt-dirty" -b feat/dirty main
touch "$tmp/wt-dirty/scratch.txt"

out="$(cd "$repo" && bash "$cleanup" 2>&1)"

assert_contains "a merged worktree goes" "$out" "removed $tmp/wt-merged (feat/merged)"
assert_contains "a fully pushed worktree goes" "$out" "removed $tmp/wt-pushed (feat/pushed)"
assert_contains "unpushed commits stay" "$out" "$tmp/wt-local: commits that exist nowhere else"
assert_contains "an edited worktree stays" "$out" "$tmp/wt-dirty: uncommitted changes"
assert_contains "the main checkout stays" "$out" "$repo: the main checkout"

assert_eq "the merged worktree is gone" "$([ -e "$tmp/wt-merged" ] && echo present)" ""
assert_eq "the unpushed worktree is still there" "$([ -e "$tmp/wt-local" ] && echo present)" "present"
assert_eq "the branch goes with the worktree" \
    "$(git -C "$repo" branch --list feat/merged)" ""
assert_eq "the unpushed branch survives" \
    "$(git -C "$repo" branch --list feat/local --format='%(refname:short)')" "feat/local"

# --dry-run has to agree with the run it stands in for, and change nothing.
git_q -C "$repo" worktree add -q "$tmp/wt-dry" -b feat/dry main
out="$(cd "$repo" && bash "$cleanup" --dry-run 2>&1)"
assert_contains "dry-run names what it would remove" "$out" "would remove $tmp/wt-dry (feat/dry)"
assert_eq "dry-run removes nothing" "$([ -e "$tmp/wt-dry" ] && echo present)" "present"

# Run from inside a worktree that is otherwise a clean candidate: removing the
# ground you are standing on is how an agent loses the rest of its session.
out="$(cd "$tmp/wt-dry" && bash "$cleanup" 2>&1)"
assert_contains "the worktree you are in stays" "$out" "$tmp/wt-dry: you are working in it"
assert_eq "and is still there" "$([ -e "$tmp/wt-dry" ] && echo present)" "present"

test_result
