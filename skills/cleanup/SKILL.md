---
name: cleanup
description: Remove the git worktrees an agent has finished with and the branches that only held them — work that merged into the default branch. Use when the user says "/cleanup", "clean up worktrees", "remove the worktrees and branches", "delete merged branches", or asks to tidy up after PRs land. Keeps anything with uncommitted work, anything whose PR is still open, and anything another agent is still sitting in. With --self it also retires the worktree the agent itself is working in, once that work has merged.
---

# Cleanup

## Purpose

Reclaim the worktrees left behind once their work has landed on the default branch. Delete the local branch with the worktree, since the branch existed to give the worktree something to check out.

**Merged is the bar, not pushed.** A branch that is fully pushed with an open PR is still being worked on — agents push to publish a review and keep committing. Removing that worktree destroys a live workspace, and the agent in it loses its checkout mid-task.

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
- Removes a worktree when its commits are already in the default branch, or when `gh` reports its PR merged — the second is what catches a squash merge, which rewrites the commits so no local test can see them.
- Deletes the branch that worktree had checked out.
- Prints one line per worktree: what it removed, and for everything else the reason it stayed.
- Keeps going when one removal fails, rather than abandoning the rest of the run.

## Retiring your own worktree

`--self` additionally considers the worktree the command runs from. This is the end-of-session move for an agent that has merged its PRs and is done:

```bash
bash "$SKILL_DIR/scripts/cleanup_worktrees.sh" --self
```

It is judged by exactly the same rules — uncommitted changes or an unmerged PR still keep it. Two things differ:

- It is evaluated **last**, after every other worktree, because removing it invalidates the directory the script and its caller are standing in.
- It **ignores the tmux check for that one worktree only**. A pane sitting there is the session that just asked for it to go.

Afterwards the caller's shell is in a directory that no longer exists; the script prints the path to `cd` to. Run it as the final action of a session, never mid-task.

## Hard Rules

- Never remove the main checkout. Never remove the worktree the command runs from unless `--self` was passed.
- Never remove a worktree whose PR is open. Pushed is not finished.
- Never remove a worktree with uncommitted changes, including untracked files.
- Never remove a worktree a live tmux pane is sitting in — that is another agent's session, whatever the branch state says. `--self` waives this for the current worktree alone.
- Never remove a worktree holding commits that exist nowhere else. Report it and let the user decide.
- Never delete a remote branch. An open PR needs its head branch, and GitHub deletes merged ones itself.
- Never pass `--force` to `git worktree remove`; a worktree that refuses to go is one of the cases above. Report it and let the user delete the directory.
- Report what stayed and why, not only what went.
