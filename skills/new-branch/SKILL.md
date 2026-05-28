---
name: new-branch
description: Sync with origin's default branch and start a clean branch for the next task. Use when the user says "/new-branch", "start a new branch", "branch off fresh main", "next task", or "set up a clean slate after that PR". Default rebranches in the current worktree; pass `--worktree` to create an isolated git worktree instead. Refuses to run with a dirty working tree. Leaves the previous branch untouched.
---

# /new-branch — start a clean branch off latest base

## When to run
- User invokes `/new-branch [name] [--worktree]`, or asks for a fresh branch to start the next task.
- Working tree must be clean. If dirty, stop and ask the user whether to commit, stash, or abort — never auto-stash.
- The branch you're currently on is left **untouched**: no checkout-back, no delete, no force-push. If it has an open PR, it stays as-is and the user can `git checkout` back to it any time review feedback comes in.

## Args
- `<name>` (optional): explicit branch name in `<type>/<slug>` form. If omitted, ask the user — suggest 2-3 names if recent conversation makes the task obvious, otherwise just ask.
- `--worktree`: create a new git worktree instead of rebranching in place. Use when:
  - parallel agents will run simultaneously,
  - the current branch has untracked scratch state worth preserving without committing,
  - dep/env state (lockfiles, migrations, model weights) would conflict between branches.

  Default is rebranch-in-place because worktree setup re-pays dep install / build cache costs.

## Sequence

### 1. Preconditions
```bash
git rev-parse --is-inside-work-tree >/dev/null
test -z "$(git status --porcelain)" \
  || { echo "Working tree not clean"; exit 1; }

BASE=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null \
        || git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||' \
        || echo main)
CURRENT=$(git branch --show-current)
```

If `gh` isn't available and `origin/HEAD` isn't set, fall back to `main` but warn the user.

### 2. Branch name
If `<name>` was not passed, ask the user. If the recent conversation contains a clear task description, propose 2-3 names following Conventional Commits scopes; otherwise just ask plainly.

Validate format: `<type>/<slug>` where type is one of `feat|fix|docs|refactor|perf|test|build|ci|chore`. Reject malformed names — ask the user to pick a type rather than guessing.

Refuse if the branch already exists locally or on the remote:
```bash
git show-ref --verify --quiet "refs/heads/$NAME" \
  && { echo "Branch $NAME already exists locally"; exit 1; }
git ls-remote --exit-code --heads origin "$NAME" >/dev/null 2>&1 \
  && { echo "Branch $NAME already exists on origin"; exit 1; }
```

### 3. Fetch the base
```bash
git fetch origin "$BASE":refs/remotes/origin/"$BASE"
```

This updates `origin/$BASE` without touching any local branch — safe whether or not local `$BASE` is checked out somewhere.

### 4a. Default: rebranch in current worktree
```bash
git checkout -b "$NAME" "origin/$BASE"
```

Branch directly off `origin/$BASE`. Don't `checkout $BASE && pull` — that's an extra step that leaves stale local-base refs behind if anything fails midway.

### 4b. With `--worktree`
Pick a sibling-of-repo-root path by default:
```bash
ROOT=$(git rev-parse --show-toplevel)
REPO=$(basename "$ROOT")
SLUG=$(echo "$NAME" | tr '/' '-')
DIR="$(dirname "$ROOT")/${REPO}-${SLUG}"
```

If `$DIR` already exists, **refuse and ask** the user for a different path — never `--force` or overwrite.

```bash
git worktree add "$DIR" -b "$NAME" "origin/$BASE"
```

Tell the user the new path explicitly; they (or the agent) need to `cd "$DIR"` to start working there.

### 5. Output
Print:
- The new branch name and the commit it's based on (`git rev-parse --short HEAD`).
- For `--worktree`: the new worktree path.
- A one-line reminder if `$CURRENT` was not `$BASE`: "Previous branch `$CURRENT` is preserved at `<short-sha>` — `git checkout $CURRENT` to return."

## Hard rules
- Never delete, rename, or force-push the previous branch.
- Never run with a dirty working tree. No auto-stash.
- Never assume the base is `main` — read the repo's default branch.
- Never silently accept a malformed branch name — surface and ask.
- Never overwrite an existing worktree path or branch. Refuse and ask.
- This skill does not push, does not open PRs, does not run preflight. Use `/pr` for that flow when the new branch is ready to ship.
