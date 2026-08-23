---
name: cleanup
description: Remove the git worktrees an agent has finished with and the branches that only held them — work whose PR merged, or that is pushed where an open PR holds it. Use when the user says "/cleanup", "clean up worktrees", "remove the worktrees and branches", "delete merged branches", or asks to tidy up after PRs land. Keeps anything with uncommitted or unpushed work, and anything another agent is still sitting in.
---

# Cleanup

## Purpose

Reclaim the worktrees left behind once their work is somewhere else — merged into the default branch, or pushed to a branch an open PR is holding. Delete the local branch with the worktree, since the branch existed to give the worktree something to check out.

## Preferred Workflow

Run the bundled helper. The working directory is the user's repository, not this
skill directory, so invoke it by absolute path:

```bash
SKILL_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/cleanup"
bash "$SKILL_DIR/scripts/cleanup_worktrees.sh"
```

Add `--dry-run` to print the same verdicts without removing anything.

The script:

- Fetches `origin` with `--prune` first, so a PR that landed a minute ago is judged against current refs and a head branch GitHub deleted on merge stops looking like unpushed work.
- Removes a worktree when its commits are in the default branch, when it is fully pushed to its upstream, or when `gh` reports its PR merged — the last is what catches a squash merge, which rewrites the commits so no local test can see them.
- Deletes the branch that worktree had checked out.
- Prints one line per worktree: what it removed, and for everything else the reason it stayed.

## Hard Rules

- Never remove the main checkout, or the worktree the command runs from.
- Never remove a worktree with uncommitted changes, including untracked files.
- Never remove a worktree a live tmux pane is sitting in — that is another agent's session, whatever the branch state says.
- Never remove a worktree holding commits that exist nowhere else. Report it and let the user decide.
- Never delete a remote branch. An open PR needs its head branch, and GitHub deletes merged ones itself.
- Never pass `--force` to `git worktree remove`; a worktree that refuses to go is one of the cases above.
- Report what stayed and why, not only what went.
