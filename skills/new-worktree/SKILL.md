---
name: new-worktree
description: Create an isolated git worktree with a new branch from freshly fetched origin/main for starting feature development without disturbing unrelated checkouts or local main edits. Use when the user says "/new-worktree", "new worktree", "gitworktree", "create a worktree", "start a feature branch in a separate checkout", "begin a new feature without touching this branch", or asks for a new branch where parallel development or preserving the current worktree matters.
---

# New Worktree

## Purpose

Start a new feature branch in a separate git worktree based on freshly fetched `origin/main`. Leave local branches, local `main`, unrelated worktrees, and uncommitted changes untouched. Do not require the current worktree to be clean.

## Inputs

- Branch name: require `<type>/<slug>`, where type is one of `feat|fix|docs|refactor|perf|test|build|ci|chore`. For a new feature, prefer `feat/<short-slug>`.
- Worktree path: optional. If omitted, create a sibling directory named `<repo>-<branch-slug>`.

If the user did not provide a branch name, ask for one. If the task is clear, suggest 2-3 valid names instead of guessing silently.

## Preferred Workflow

Run the bundled helper from this skill directory:

```bash
bash scripts/start_feature_worktree.sh feat/my-feature
```

Optional arguments:

```bash
bash scripts/start_feature_worktree.sh feat/my-feature --path /absolute/worktree/path
```

The script:

- Verifies it is inside a git repository.
- Requires an `origin` remote.
- Fetches `origin/main` directly into `refs/remotes/origin/main` immediately before creating the worktree.
- Creates the feature branch from freshly fetched `origin/main`, not local `main`, the repository default branch, or the current branch.
- Does not check out, pull, fast-forward, stash, run `git status`, or otherwise modify local `main`; dirty local worktrees are allowed.
- Refuses existing local branches, matching remote branches, and existing worktree paths.
- Creates the new branch and worktree with `git worktree add --no-track` so the feature branch does not track the base branch as its upstream.
- Prints the branch, path, base commit, and previous branch.

## Manual Fallback

Use this only if the helper cannot run and the issue is environmental:

```bash
ROOT=$(git rev-parse --show-toplevel)
BRANCH="feat/my-feature"
DIR="$(dirname "$ROOT")/$(basename "$ROOT")-$(echo "$BRANCH" | tr '/' '-')"
BASE_REF="refs/remotes/origin/main"
git fetch origin +refs/heads/main:"$BASE_REF"
git worktree add --no-track "$DIR" -b "$BRANCH" "$BASE_REF"
```

Before the manual fallback, explicitly check that the branch does not exist locally or on origin and that `$DIR` does not already exist.

## Hard Rules

- Never delete, rename, force-update, or force-push the previous branch.
- Never overwrite an existing directory or worktree path.
- Never auto-stash, discard, or require cleanup of unrelated worktree changes.
- Never require a clean current worktree; dirty local `main` must not block creating the new worktree.
- Never check out, pull, fast-forward, or modify local `main`.
- Never use the current branch, local `main`, the repository default branch, or any ref other than freshly fetched `origin/main` as the start point.
- Never skip fetching `origin/main` immediately before creating the worktree.
- Never push the branch, open a PR, install dependencies, or run project setup unless the user asks.
