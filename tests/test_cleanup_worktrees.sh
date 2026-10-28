#!/bin/bash
set -uo pipefail

# Drive the real script against throwaway repos. Every worktree below is one of
# the states the script has to tell apart, and the ones that matter most are the
# ones it must refuse to remove: work that has not merged, and a checkout
# somebody is still in.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

cleanup="$ROOT/skills/cleanup/scripts/cleanup_worktrees.sh"
tmp="$(cd "$(mktemp -d)" && pwd -P)"
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

# Work that landed: committed on its own branch, and that commit is now on the
# default branch. Note the commit -- a branch created off main and never
# committed to is NOT this shape, it is the shape of a checkout nobody has
# started yet, and wt-fresh below covers that case.
git_q -C "$repo" worktree add -q "$tmp/wt-merged" -b feat/merged main
git_q -C "$tmp/wt-merged" commit -q --allow-empty -m merged-work
git_q -C "$tmp/wt-merged" push -q origin feat/merged:main

# Created and not yet worked in: no commits of its own, sitting exactly where it
# was branched from. Ancestry cannot tell this from a merged branch -- it is
# trivially contained in its own base -- which is how a live checkout with an
# agent in it used to be deleted along with its branch. It must survive.
git_q -C "$repo" worktree add -q "$tmp/wt-fresh" -b feat/fresh main

# Pushed to its own upstream with nothing merged: the shape of an open PR. The
# agent that opened it is still committing to it, so this one has to survive.
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
assert_contains "a pushed but unmerged worktree stays" "$out" \
    "$tmp/wt-pushed: work that has not landed on main"
assert_contains "unmerged commits stay" "$out" \
    "$tmp/wt-local: commits that are on no remote — they exist nowhere else"
assert_contains "an edited worktree stays" "$out" "$tmp/wt-dirty: uncommitted changes"
assert_contains "a fresh worktree stays" "$out" \
    "$tmp/wt-fresh: no commits of its own — a fresh checkout is not finished work"
assert_contains "the main checkout stays" "$out" "$repo: the main checkout"

assert_eq "the merged worktree is gone" "$([ -e "$tmp/wt-merged" ] && echo present)" ""
assert_eq "the pushed worktree is still there" "$([ -e "$tmp/wt-pushed" ] && echo present)" "present"
assert_eq "the unmerged worktree is still there" "$([ -e "$tmp/wt-local" ] && echo present)" "present"
assert_eq "the fresh worktree is still there" "$([ -e "$tmp/wt-fresh" ] && echo present)" "present"
assert_eq "the fresh branch survives" \
    "$(git -C "$repo" branch --list feat/fresh --format='%(refname:short)')" "feat/fresh"
assert_eq "the branch goes with the worktree" \
    "$(git -C "$repo" branch --list feat/merged)" ""
assert_eq "the pushed branch survives" \
    "$(git -C "$repo" branch --list feat/pushed --format='%(refname:short)')" "feat/pushed"
assert_eq "the unmerged branch survives" \
    "$(git -C "$repo" branch --list feat/local --format='%(refname:short)')" "feat/local"

# --dry-run has to agree with the run it stands in for, and change nothing.
#  Branched from the fetched remote, not local main: earlier fixtures have
#  already moved origin/main, and a branch cut from a stale local main cannot
#  land on it.
git_q -C "$repo" fetch -q origin
git_q -C "$repo" worktree add -q "$tmp/wt-dry" -b feat/dry origin/main
git_q -C "$tmp/wt-dry" commit -q --allow-empty -m dry-work
git_q -C "$tmp/wt-dry" push -q origin feat/dry:main
out="$(cd "$repo" && bash "$cleanup" --dry-run 2>&1)"
assert_contains "dry-run names what it would remove" "$out" "would remove $tmp/wt-dry (feat/dry)"
assert_eq "dry-run removes nothing" "$([ -e "$tmp/wt-dry" ] && echo present)" "present"

# Run from inside a worktree that is otherwise a clean candidate: removing the
# ground you are standing on is how an agent loses the rest of its session.
out="$(cd "$tmp/wt-dry" && bash "$cleanup" 2>&1)"
assert_contains "the worktree you are in stays" "$out" "$tmp/wt-dry: you are working in it"
assert_eq "and is still there" "$([ -e "$tmp/wt-dry" ] && echo present)" "present"

# --self is the end-of-session move, so it answers to the same rules: an
# unmerged current worktree stays exactly as it would without the flag.
out="$(cd "$tmp/wt-local" && bash "$cleanup" --self 2>&1)"
assert_contains "--self refuses unmerged work" "$out" \
    "$tmp/wt-local: commits that are on no remote — they exist nowhere else"
assert_eq "and leaves it there" "$([ -e "$tmp/wt-local" ] && echo present)" "present"

out="$(cd "$tmp/wt-dirty" && bash "$cleanup" --self 2>&1)"
assert_contains "--self refuses an edited worktree" "$out" "$tmp/wt-dirty: uncommitted changes"
assert_eq "and leaves it there" "$([ -e "$tmp/wt-dirty" ] && echo present)" "present"

# wt-dry is gone by now: the two runs above swept it up as an ordinary merged
# worktree, which is right — being spared is a property of being the one you are
# standing in, not of the directory itself.
assert_eq "a merged worktree goes once you leave it" \
    "$([ -e "$tmp/wt-dry" ] && echo present)" ""

# The current worktree is judged after every other one, because removing it
# invalidates the directory the script is standing in.
#  Branched from the fetched remote, not local main: earlier fixtures have
#  already moved origin/main, and a branch cut from a stale local main cannot
#  land on it.
git_q -C "$repo" fetch -q origin
git_q -C "$repo" worktree add -q "$tmp/wt-self" -b feat/self origin/main
git_q -C "$tmp/wt-self" commit -q --allow-empty -m self-work
git_q -C "$tmp/wt-self" push -q origin feat/self:main
out="$(cd "$tmp/wt-self" && bash "$cleanup" --dry-run --self 2>&1)"
assert_contains "--self names the current worktree" "$out" "would remove $tmp/wt-self (feat/self)"
#  The last VERDICT, not the last line: the run ends with the post-cleanup hook
#  and the summary, so counting back from the bottom would be measuring those.
assert_contains "--self weighs it last" \
    "$(printf '%s\n' "$out" | grep -E '^(keep|would remove|removed) ' | tail -1)" \
    "would remove $tmp/wt-self"
assert_eq "--self honours dry-run" "$([ -e "$tmp/wt-self" ] && echo present)" "present"

out="$(cd "$tmp/wt-self" && bash "$cleanup" --self 2>&1)"
assert_contains "--self removes a merged current worktree" "$out" \
    "removed $tmp/wt-self (feat/self)"
assert_contains "--self says the shell is now nowhere" "$out" "cd $repo"
assert_eq "the current worktree is gone" "$([ -e "$tmp/wt-self" ] && echo present)" ""
assert_eq "its branch went with it" "$(git -C "$repo" branch --list feat/self)" ""

# Gitignored data/ and outputs/ directories are wiped by `git worktree remove`
# without showing up in `git status --porcelain`; a merged worktree holding data
# must be kept.
git_q -C "$repo" fetch -q origin
git_q -C "$repo" worktree add -q "$tmp/wt-data" -b feat/data origin/main
printf '/data/\n' > "$tmp/wt-data/.gitignore"
git_q -C "$tmp/wt-data" add .gitignore
git_q -C "$tmp/wt-data" commit -q -m "ignore data"
git_q -C "$tmp/wt-data" push -q origin feat/data:main
mkdir -p "$tmp/wt-data/data"
echo "precious-recording" > "$tmp/wt-data/data/run.bag"
out="$(cd "$repo" && bash "$cleanup" 2>&1)"
assert_contains "a merged worktree with gitignored data/ stays" "$out" \
    "$tmp/wt-data: non-empty data/ directory — move or delete it first"
assert_eq "the data file survives" "$(cat "$tmp/wt-data/data/run.bag")" "precious-recording"
rm -rf "$tmp/wt-data/data"

# GitHub squash-merges after an "Update branch" merge commit: headRefOid on the
# PR points at GitHub's server-side merge commit, not the local branch tip,
# while the local branch commit is still recorded in the PR's commits[] list.
# Also test a stacked branch folded into a subsequent squash-merged PR, and a
# primary repo with a stale core.bare=true config that still has tools/cleanup-hook.sh.
git_q -C "$repo" fetch -q origin
git_q -C "$repo" worktree add -q "$tmp/wt-squash" -b feat/squash origin/main
git_q -C "$tmp/wt-squash" commit -q --allow-empty -m "feat: squash work"
squash_oid="$(git -C "$tmp/wt-squash" rev-parse HEAD)"

git_q -C "$repo" worktree add -q "$tmp/wt-folded" -b feat/folded origin/main
git_q -C "$tmp/wt-folded" commit -q --allow-empty -m "feat: folded step"
folded_oid="$(git -C "$tmp/wt-folded" rev-parse HEAD)"

# Simulate the squash commit landing on origin/main with a (#42) suffix.
git_q -C "$tmp/seed" pull -q origin main
git_q -C "$tmp/seed" commit -q --allow-empty -m "feat: folded step (#42)"
git_q -C "$tmp/seed" push -q origin main

mkdir -p "$tmp/bin" "$repo/tools"
cat > "$repo/tools/cleanup-hook.sh" <<'EOF'
#!/bin/bash
echo "hook-executed"
EOF
chmod +x "$repo/tools/cleanup-hook.sh"
git -C "$repo" config core.bare true

cat > "$tmp/bin/gh" <<EOF
#!/bin/bash
if [ "\$1 \$2" = "auth status" ]; then exit 0; fi
if [ "\$1 \$2" = "pr list" ]; then
    cat <<JSON
[
  {
    "number": 41,
    "state": "MERGED",
    "headRefName": "feat/squash",
    "headRefOid": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
    "title": "feat: squash work",
    "commits": [{"oid": "$squash_oid", "messageHeadline": "feat: squash work"}]
  },
  {
    "number": 42,
    "state": "MERGED",
    "headRefName": "pr/stacked-bundle",
    "headRefOid": "cafebabecafebabecafebabecafebabecafebabe",
    "title": "feat: stacked bundle",
    "commits": [{"oid": "$folded_oid", "messageHeadline": "feat: folded step"}]
  }
]
JSON
    exit 0
fi
exit 1
EOF
chmod +x "$tmp/bin/gh"

out="$(cd "$repo" && PATH="$tmp/bin:$PATH" bash "$cleanup" 2>&1)"
assert_contains "squash-merged PR after GitHub branch update goes" "$out" \
    "removed $tmp/wt-squash (feat/squash)"
assert_contains "folded stacked branch whose commit is in a merged PR goes" "$out" \
    "removed $tmp/wt-folded (feat/folded)"
assert_contains "cleanup-hook runs even if core.bare was left true on a non-bare primary" "$out" \
    "hook-executed"

test_result
