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

## Starting other agents

Each time you start another agent (a subagent, a workflow agent, a reviewer, or
a session), set its model and reasoning effort for that piece of work. This
rule is the explicit request the spawn tools wait for before you set them.
Never leave them to the defaults: those are your own settings or whatever the
user last saved, often the top tier at maximum effort.

| Piece of work | Model |
| --- | --- |
| Most work: implementing, debugging, reviewing, a session's task | one tier below the top |
| Narrow or mechanical: searching, gathering facts, summarizing, scripted edits | the small, fast tier |
| A subtle design or proof, a bug the default tier missed, a mistake that would cost a lot | the top tier |

Effort is always xhigh, or the highest a model offers below that; never low or
medium. Choose the top tier, max effort, or ultracode (a multi-agent workflow)
only when you can say why, and tell the user why. A fork of your conversation
runs at your model and effort; when its piece needs another tier, start a fresh
agent with a brief instead. The tiers in each CLI, top / below the top / small:

- Claude Code: `fable` / `opus` / `sonnet` or `haiku`.
- Codex: the latest frontier / workhorse / fast models that `spawn_agent` and
  `codex debug models` describe. `spawn_agent` takes `model` and
  `reasoning_effort` only with `fork_turns` set to `none`.
- Grok: the newest model in `grok models` serves every tier
  (`--reasoning-effort` for a session). `spawn_subagent` runs at your effort.
- Antigravity: sessions take the highest-effort id of the model `pro`
  subagents run (`gemini-4-argon-high` today), or of Flash for small work
  (`agy models`). A
  subagent's `Model` is `pro` for most work and `flash` or `flash_lite` for
  small work, never top; its effort follows yours.
- OpenCode: a subagent runs on its definition's `model`, else on yours.

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
