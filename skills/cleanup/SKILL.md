---
name: cleanup
description: Remove the git worktrees an agent has finished with and the branches that only held them — work that merged into the default branch. Use when the user says "/cleanup", "clean up worktrees", "remove the worktrees and branches", "delete merged branches", or asks to tidy up after PRs land. Keeps anything with uncommitted or stashed work, anything whose PR is still open, anything another agent is still sitting in, and any checkout that has never committed anything of its own. With --self it also retires the worktree the agent itself is working in, once that work has merged. Afterwards it runs the repo's own tools/cleanup-hook.sh if there is one, so state keyed to a removed worktree gets reclaimed.
---

# Cleanup

## Purpose

Reclaim the worktrees left behind once their work has landed on the default branch. Delete the local branch with the worktree, since the branch existed to give the worktree something to check out.

**Merged is the bar, not pushed.** A branch that is fully pushed with an open PR is still being worked on — agents push to publish a review and keep committing. Removing that worktree destroys a live workspace, and the agent in it loses its checkout mid-task.

**Contained in the default branch is not merged.** A checkout that has never committed anything is contained too — trivially, because it is sitting on a commit the default branch already has. Ancestry cannot tell the two apart, so the bar is positive evidence that the branch once held work of its own and that the work landed. A brand-new worktree is a live workspace, not finished work.

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
- Removes a worktree when the branch's own commits are in the default branch, or when `gh` reports a merged PR whose head is the commit this checkout is standing on — the second is what catches a squash merge, which rewrites the commits so no local test can see them.
- Reads the branch's reflog to tell "its commits merged" from "it never made any". Both are contained in the default branch and the commit graph cannot separate them; the reflog is the only local record that the branch once held work of its own. The messages it accepts as evidence are a whitelist, so an unfamiliar one means "no evidence", which means keep. `rebase` is deliberately not on it — rebasing a fresh branch onto a newer base leaves a reflog entry with no commit of its own in it, and that is a routine agent warm-up.
- Checks the stash, which `git status` does not report and which every worktree shares.
- Deletes the branch that worktree had checked out.
- Prints one line per worktree: what it removed, and for everything else the reason it stayed.
- Keeps going when one removal fails, rather than abandoning the rest of the run.

When reflogs are switched off repo-wide (`core.logAllRefUpdates=false`) nothing local can speak for any branch, so only a merged PR retires anything. The script says so once on stderr rather than looking broken.

## Retiring your own worktree

`--self` additionally considers the worktree the command runs from. This is the end-of-session move for an agent that has merged its PRs and is done:

```bash
bash "$SKILL_DIR/scripts/cleanup_worktrees.sh" --self
```

It is judged by exactly the same rules — uncommitted changes or an unmerged PR still keep it. Two things differ:

- It is evaluated **last**, after every other worktree, because removing it invalidates the directory the script and its caller are standing in.
- It **ignores the tmux check for that one worktree only**. A pane sitting there is the session that just asked for it to go.

Afterwards the caller's shell is in a directory that no longer exists; the script prints the path to `cd` to. Run it as the final action of a session, never mid-task.

## Repo hook

Removing a worktree orphans whatever the repo keyed to that path — a Bazel output base, a virtualenv, a container volume, a cache directory. Nothing can tell that state is dead until the directory is actually gone, so the cleanup is the only moment the reclamation is decidable, and it belongs here rather than in a separate step a caller has to remember to run second.

If the **primary checkout** holds an executable `tools/cleanup-hook.sh` (or `.cleanup-hook`), the script runs it once at the end. It is opt-in and it is the repo's own code: a repo without the file is untouched and prints nothing, and this skill carries no knowledge of any particular build system.

The contract:

- It runs **last**, after every removal including `--self`.
- Its working directory is the **primary checkout**. A feature worktree may not have the state a reclamation tool needs to find, and after `--self` the caller's own directory is gone.
- `CLEANUP_PRIMARY` and `CLEANUP_REMOVED` are in its environment, so a hook that is only worth running after something actually went can check the count.
- `--dry-run` **names it and does not run it**. A dry run removes no worktrees, so no path disappears and there is nothing new to reclaim — while a careless hook would still delete.
- A non-zero exit is reported on stderr and the cleanup still succeeds. The removals already happened; a repo's hook misbehaving is not cleanup failing.
- It is killed after 1800s, as a hang-stop.
- `CLEANUP_NO_HOOK=1` skips it, for cleaning up in a repo cloned only to read. `--post-hook CMD` replaces it, for an ad-hoc run or for testing a hook before committing it.

The hook is read from the primary checkout only, never from a worktree: a worktree holds a feature branch, possibly one from a PR under review, and that is not code to execute. From the primary checkout it carries the same trust as the repo's justfile, `BUILD` files and pre-commit config, all of which already run during an ordinary build. Put it under `tools/`, not `.claude/`, which repos commonly gitignore — a hook nobody else gets is not a shared convention.

## Hard Rules

- Never remove the main checkout. Never remove the worktree the command runs from unless `--self` was passed.
- Never remove a worktree whose PR is open. Pushed is not finished.
- Never remove a worktree with uncommitted changes, including untracked files.
- Never remove a worktree with no commits of its own. Being contained in the default branch is exactly what a brand-new checkout looks like — it is not evidence that anything landed, and the worktree is probably a live workspace someone is about to use.
- Never remove a worktree whose only work is stashed. `git status` reports nothing for a stash, and `refs/stash` is shared by every worktree, so entries are matched by the branch their message names.
- Never let a merged PR retire a checkout it did not produce. `gh pr list --head` answers for a branch *name*, and names get reused; the PR speaks for this worktree only when the commit GitHub merged is the one checked out here.
- Never remove a worktree a live tmux pane is sitting in — that is another agent's session, whatever the branch state says. `--self` waives this for the current worktree alone.
- Never remove a worktree holding commits that exist nowhere else. Report it and let the user decide.
- Never delete a remote branch. An open PR needs its head branch, and GitHub deletes merged ones itself.
- Never pass `--force` to `git worktree remove`; a worktree that refuses to go is one of the cases above. Report it and let the user delete the directory.
- Never resolve the repo hook from a worktree, only from the primary checkout. Never run it on `--dry-run` — print what would run.
- Report what stayed and why, not only what went.
