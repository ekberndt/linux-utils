# Workflow

Every task that edits a git repository runs in its own worktree:

- **Start.** Before the first edit, use the `worktree` skill and make every
  edit in the checkout it creates. Skip it only when this checkout is already a
  linked worktree on a branch made for this task.
- **Finish.** When the change is done and verified, say it is ready to land.
  Pushing, the PR and the merge wait until the user asks for the `land` skill,
  which also removes the worktree and closes the session.

Answering questions, reviewing, and reading code need no worktree.
