# Workflow

Every task that edits a git repository runs in its own worktree:

- **Start.** Before the first edit, use the `worktree` skill and make every
  edit in the checkout it creates. Skip it only when this checkout is already a
  linked worktree on a branch made for this task.
- **Finish.** When the change is done and verified, say it is ready to land.
  Pushing, the PR and the merge wait until the user asks for the `land` skill,
  which, once nothing is left to discuss, also removes the worktree and closes
  the session's terminal.

Answering questions, reviewing, and reading code need no worktree.

## Maintenance

`MAINTENANCE.md` at a repo's root lists what drifts while nobody touches the
code: pins, files copied from upstream, OS-release workarounds, docs that
restate code, and what machines still hold from installs the repo has moved.

- A change that adds something that drifts adds its item there in the same PR;
  a change that removes it deletes the item. The `maintenance` skill gives the
  format.
- A change that moves, renames or drops something a machine has installed
  ships no cleanup code for the old one; the machine section of
  `MAINTENANCE.md` removes it.
- When the user asks for maintenance, run a pass with the `maintenance` skill.
