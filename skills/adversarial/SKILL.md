---
name: adversarial
description: Have a fresh-context subagent try to break whatever the conversation is about (a plan, a design, code, a feature, or an idea), attacking it from every angle that applies, then verify each finding yourself before acting on it. Use when the user says "adversarial" (asking for a review, not adversarial training or examples), "/adversarial", "adversarial review", "red-team this", "try to break this", "poke holes in this", "tear this apart", "stress-test this", or asks for a review that is not anchored on your reasoning.
argument-hint: "[what to review]"
---

# Adversarial Review

## Purpose

A reviewer that shares your reasoning inherits your blind spots. This one sees the artifacts and the goal, never why you think the work is right, and its only job is to break them. Its findings are leads, not verdicts: you check each one before acting on it.

## The Reviewer

Start it as an in-process subagent that sees none of your conversation, so its report comes straight back to you for the verify step. Never fork your conversation into it or resume an earlier agent, which carries your reasoning over, and never give it a worktree or isolated workspace, which is a new branch in the author's repository without the uncommitted changes.

- Claude Code: the Agent tool with the `general-purpose` type, not `fork`.
- Codex: `spawn_agent` with `fork_turns` set to `none`. The default, `all`, copies your conversation into it.
- Grok: `spawn_subagent` with the default `general-purpose` type, without `resume_from`.
- OpenCode: the `task` tool, without `task_id`.
- Antigravity: `define_subagent` with `EnableWriteTools`, so it can run commands and reproduce what it finds, then `invoke_subagent` with that `TypeName`, the default `Workspace`, and no fork.

Set its model and effort as "Starting other agents" in your instructions says.

If you cannot start one with empty context, tell the user and stop: reviewing the work yourself is not this review. Do not use the `session` skill either. It hands the reviewer to the user to steer, and its result would come back typed into your context.

Use one reviewer, so the seams between artifacts (code that does not do what the plan says) stay in one view. Split only by artifact, when one reviewer cannot cover them all in depth, such as a large diff plus a long design doc.

## Workflow

1. **Work out what to review.** Gather every artifact the conversation is about: a diff, a plan, a design, a feature, or an idea that is not yet written down. Honor any target the user names. If you cannot tell what "this" is, or there is nothing to review, ask.
2. **If an artifact is on a branch, run `git fetch origin`**, so the reviewer tests it against the current base.
3. **Write the brief.** The reviewer sees none of this conversation, so the brief must stand alone:
   - **Goal:** what the user wants and what done means, quoting the user's own messages where they set it, plus every hard constraint they set (platforms, compatibility, what must not change). This is the spec the reviewer checks against. Anything you produced, including a plan the code implements, is artifact, not spec.
   - **Artifacts:** for code, the checkout path, the base the change will merge into (`origin/<base>`: the PR's base branch, otherwise the default branch), the change (`git diff $(git merge-base origin/<base> HEAD)`), and untracked files (`git status --short`); with no change, the paths to attack. Give a PR that is not checked out here by number, for `gh pr diff`. For anything else, give the text verbatim or the path of the file holding it. Point the reviewer at the repo's `AGENTS.md` or other conventions.
   - **Angles:** the table below. Tell the reviewer to decide which angles apply and attack from each, and to add the classes of failure that recur in this domain. For an installer change these might be skips that hide work, parsers that misparse real tool output, prompts swallowed by quiet output, partial failures that read green, and macOS vs Linux. Name domain classes, not the spots in this artifact you suspect.
   - **Rules and report format:** paste the block below, with the checkout path filled in.
   - Leave out your conclusions: why you think it works, what you tested, what you already fixed, where you expect trouble. If it finds those on its own, they are confirmed; if you hand them over, it stops looking past them.
4. **Run the subagent and wait for its report.**
5. **Verify every finding yourself** by reproducing it or tracing it through the artifact. A reasoned-only or low-confidence finding gets the same check; it is neither discarded nor accepted on the reviewer's say-so. Then:
   - Real: fix it. For code, add a test that fails without the fix. For a plan, design, or idea, revise it.
   - Not real: decline it, with the reason the scenario cannot happen.
   - Cannot be checked here, such as a macOS failure seen from Linux: say so, and what would settle it.
   - A trade-off only the user can weigh: ask them.
6. **Report to the user**, who never sees the reviewer's report: one line per finding under the reviewer's own title, with its outcome. Then pass on the reviewer's list of what it found sound, as its claim rather than yours.

| Angle | Attack |
| --- | --- |
| Code | Inputs and states the tests skip: empty, huge, malformed, concurrent, interrupted, re-run. Partial failures that report success; swallowed or misreported errors. Parsers fed real tool output rather than the test's example. Platform differences: macOS vs Linux, BSD vs GNU tools, bash vs zsh. Shortcuts and caches that skip real work. Tests that pass without exercising the change. Commits on `origin/<base>` that conflict with the change, uncommitted work included, or break it. |
| Feature | Whether it solves the user's actual problem end to end. First run, re-run, upgrade, removal. Interactions with neighbouring features. Errors a user cannot act on. Output that buries a prompt or a failure. Docs that disagree with behavior. |
| Design | Invariants some path violates. Crashes midway and the partial state they leave. Concurrency and ordering. Limits at 10x and 100x the load. Coupling to a backend or representation that will change. What callers must know that the interface does not say. A simpler design that does the same job. |
| Plan | Missing or misordered steps. Assumptions nobody verified. Irreversible steps with no check before them. Steps with no way to tell they succeeded. Done criteria that do not prove the goal. Parts of the goal quietly dropped. The state left if it stops halfway. |
| Idea | Whether the problem exists, for whom, and how much it costs them. Existing tools or past attempts that already solve it. The strongest argument against. The cheapest experiment that would kill it. Its costs, second-order effects, and what it displaces. |
| Seams | Where artifacts disagree with each other or with the goal: code that does not do what the plan or design says, docs describing other behavior, a plan step nothing implements. |

```text
You are reviewing, not fixing. Do not edit, commit, check out, stash, reset, or
create branches or worktrees in <checkout>. Do the review yourself: start no
subagents and do not load the adversarial skill. Read the artifacts and the
repository, and nothing the author or an earlier reviewer left behind: scratch
files, logs, or agent session transcripts.

Experiment only in a directory you make with `mktemp -d`, and leave it in place
so the author can rerun your evidence. To run the code, `git clone` the
checkout there, point the clone's `origin` at the checkout's remote URL and
fetch it (otherwise `origin` is the checkout's local branches, which can be
stale), apply the checkout's `git diff --binary HEAD`, and copy its untracked
files. A plain copy of a worktree still points `.git` at the author's
repository.

Change nothing outside that directory: run anything that writes to the home
directory (config sync, for example) with HOME pointed inside it, and start no
terminals, tmux windows, or agent sessions. Run nothing destructive or
outward-facing: nothing that runs sudo, which rules out most installers; no
package installs or upgrades; no writes to remote services (no pushes,
comments, or state-changing API calls); no killing processes you did not start.

Report each finding, most severe first, as:
- Title, and where: file:line, plan step, or section.
- Failure scenario: the concrete inputs or state, and the wrong outcome they
  lead to.
- Evidence: reproduced (give the command, and the path of any script in your
  scratch directory) or reasoned only.
- Confidence: high, medium, or low.
A finding is something that breaks, misleads, or fails the goal; style is not a
finding. End with one line listing the angles you attacked and what you found
sound.
```
