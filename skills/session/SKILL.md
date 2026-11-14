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
   - **Constraints:** work in its own worktree via the `worktree` skill, never in a checkout another agent uses; do not commit, push, or open a PR unless the user asked; the files, sessions, and scope it must stay out of.
   - **Report:** what to tell the user when it finishes, e.g. files changed, test results, open questions. If you need the result yourself, ask it to `hc send <your $HC_TERMINAL_ID> "<result>"` as well.
2. Launch it:

   ```bash
   "${AGENTS_CONFIG_DIR:-$HOME/.agents}/scripts/agent-session" \
       --name fix-flaky-test --cwd ~/src/repo --brief /path/to/brief.md -- claude
   ```

   - `--name`: 1-32 of `a-z 0-9 - _`, unique among live terminals; name it for the task.
   - `--cwd`: the repository the work belongs to; the agent makes its own worktree from there.
   - `--on <machine>`: run it on a machine from `hc machine ls`; `--cwd` is then a path on that machine.
   - The agent command: whichever the user asked for, otherwise the agent you are — `claude` for Claude Code, `codex --no-daemon` for Codex (without `--no-daemon`, Codex runs its commands outside hc).
3. Tell the user the session's name and the tab it landed in, from the helper's last line: `t1q (fix-flaky-test) is in Herdr tab: scalar / 7`.

The helper finds the Herdr space your terminal is shown in, opens a new tab in it, starts the agent by absolute path with no parent, passes the brief as its first message, and waits until the app has placed it. If it reports that no space shows your terminal, or that the app has not shown the session, pass that on to the user rather than retrying.

## Afterwards

The session belongs to the user, who reads and steers it in its tab. Check on it with `hc get <name>` and `hc read <name>`. Agent shells inherit the Herdr core's PATH, which lacks `~/.local/bin`; if `hc` is not found, call `~/.local/bin/hc`.

Before any `hc send`, check `hc get <name>`. A `blocked` status means it is waiting on a question or permission, and typing would answer that dialog. Tell the user which tab needs them instead.

## Hard Rules

- Never use an in-process subagent for a "session"; never start a session with a plain `hc run`.
- Never type into a `blocked` session, and never `hc send --force`.
- Never kill or remove a session the user may still be using.
