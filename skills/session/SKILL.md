---
name: session
description: Start another coding agent in its own Herdr terminal, shown as a new tab in the Herdr app's left panel, with its own context and a self-contained brief. Use when the user says "new session", "start a session", "spawn an agent", "new herdr tab", "new herdr terminal", "hand this to another agent", or asks for work to run in a separate agent they can watch and steer. Use an in-process subagent instead only when the user says "subagent".
---

# Session

## Purpose

A session is a separate agent the user can see and talk to: its own Herdr terminal and context, in a new tab beside yours in the app's left panel. It is not an in-process subagent; use one of those only when the user says "subagent".

Do not start sessions with a plain `hc run`. The app does not show the terminal it makes, and the child types notes into your context and dies when you exit. The helper below avoids both.

## Workflow

1. Write the brief to a file outside the repository (your scratchpad, or `mktemp`). The new agent sees none of this conversation, so the brief must stand alone:
   - **Goal:** what done looks like, and why the user wants it.
   - **Established facts:** what you or the user already verified (paths, commands, root causes, decisions), so it neither redoes nor second-guesses them. Mark anything unverified.
   - **Constraints:** it starts in its own worktree on the branch you pass as `--worktree` (name both) and works only there, never in a checkout another agent uses; do not commit, push, or open a PR unless the user asked; the files, sessions, and scope it must stay out of.
   - **Report:** what to tell the user when it finishes, e.g. files changed, test results, open questions. If you need the result yourself, ask it to `hc send <your $HC_TERMINAL_ID> "<result>"` as well.
2. Launch it:

   ```bash
   "${AGENTS_CONFIG_DIR:-$HOME/.agents}/scripts/agent-session" \
       --name fix-flaky-test --cwd ~/src/repo --worktree fix/flaky-test \
       --brief /path/to/brief.md -- claude --model opus --effort xhigh
   ```

   - `--name`: 1-32 of `a-z 0-9 - _`, unique among live terminals; name it for the task.
   - `--cwd`: the repository the work belongs to.
   - `--worktree <type/slug>`: for work that edits the repository, a new branch named the way the `worktree` skill names them. The helper makes that worktree with the `worktree` skill and starts the agent in it, so the Herdr app's Changes panel and the agent's status line show that checkout; an agent that makes its worktree after starting stays in `--cwd`, and so do they. If the branch exists, pick a more specific slug and run it again. Leave it out for questions, reviews, and reading code.
   - `--on <machine>`: run it on a machine from `hc machine ls`; `--cwd` is then a path on that machine, and the worktree is made there.
   - The agent command: whichever CLI the user asked for, otherwise the one you are, with the model and effort that "Starting other agents" in your instructions gives the brief. A bare command starts on whatever the user last saved.

     | CLI | Agent command |
     | --- | --- |
     | Claude Code | `claude --model <alias> --effort <level>` |
     | Codex | `codex --no-daemon -m <model> -c model_reasoning_effort=<level>`; without `--no-daemon`, Codex runs its commands outside hc |
     | Grok | `~/.grok/bin/grok -m <model> --reasoning-effort <level>`, by path because a login shell does not find it |
     | Antigravity | `agy --model <id> -i`, with `-i` last: the helper appends the brief, and `agy` takes its first prompt only from `-i` |
     | OpenCode | not checked on a machine yet; see `opencode --help` |

3. Tell the user the session's name, its worktree, and the tab it landed in, from the helper's `Created worktree:` and last lines: `t1q (fix-flaky-test) is in Herdr tab: scalar / 7`.

The helper finds the Herdr space your terminal is shown in, makes the worktree, opens a new tab in that space, starts the agent by absolute path with no parent, passes the brief as its first message, and waits until the app has placed it. If it reports that no space shows your terminal, or that the app has not shown the session, pass that on to the user rather than retrying. A session that fails to start leaves no worktree behind.

## Afterwards

The session belongs to the user, who reads and steers it in its tab. Check on it with `hc get <name>` and `hc read <name>`. Agent shells inherit the Herdr core's PATH, which lacks `~/.local/bin`; if `hc` is not found, call `~/.local/bin/hc`.

Before any `hc send`, check `hc get <name>`. A `blocked` status means it is waiting on a question or permission, and typing would answer that dialog. Tell the user which tab needs them instead.

## Hard Rules

- Never use an in-process subagent for a "session"; never start a session with a plain `hc run`.
- Never type into a `blocked` session, and never `hc send --force`.
- Never kill or remove a session the user may still be using.
