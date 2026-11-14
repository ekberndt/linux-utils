---
name: land
description: >
  Land the current branch, or a stack of PRs: open the PR if there is none,
  fix red CI, resolve conflicts, answer review threads, keep the body
  template-shaped, approve, enable auto-merge with squash and re-enqueue until
  GitHub merges it, then, unless the session still has something open, retire
  the worktree and its local branch and close the agent's terminal (tmux pane
  or Herdr tab, archiving a Codex session). With nothing left to land, it only
  closes the session. Use when the user says "/land", "land this", "ship
  this", "merge this PR", "babysit this PR", or "watch this PR until it
  merges".
argument-hint: "[PR# | branch] | check | status"
user-invocable: true
---

# Land

Run only when the user asks to land.

**Goal:** land the PR, retire its worktree, and close the session. Done means
`state == MERGED` and **Clean up** ran (or the user cancelled / closed it), or
there was nothing to land and **Close the session** ran — never "green", never
"ready", never "enqueued".

**Invoking `/land` is the approval.** Asking you to land a PR is the user
saying they want it merged, so you carry the authority to get it there:
approve it, enable auto-merge with squash, and put it back in the merge queue
as often as the queue ejects it. What you may not do is *skip* a gate — approve
past red CI, an unanswered review thread, or a conflict. Clear the gate, then
use the authority. See **Merge authority**.

Use `git` + `gh`. Prefer harness schedulers/loops when available; otherwise
poll in-session with `next_check.py` waits. Do not claim monitoring continues
after the session ends unless a real scheduler is running.

Optional state: `~/.agents/land/state-<owner__repo>.json`.

## Contract

- Work until **merged** or **closed**, or the user stops you.
- Clear every agent-actionable blocker: red CI, conflicts, behind base,
  review changes, unresolved threads that need code or a real answer.
- Then land it: approve, auto-merge with squash, enqueue, re-enqueue.
- Leave gates you genuinely cannot clear (CODEOWNERS you are not in, an
  approval GitHub refuses from this account, org policy) — report them and keep
  polling so you catch the next actionable failure.
- PR title/body follow the **working repo's PR template** + `AGENTS.md`
  (template shape; AGENTS wins wording conflicts).
- Once the PR is open: new commits on top + normal **`git push`**. Never
  force-push.
- Once it merges, retire the worktree through the `cleanup` helper — never by
  hand.

## Resolve target

```bash
gh auth status
gh pr view --json number,url,title,state,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,baseRefName,headRefName,body,autoMergeRequest
```

Default: current branch. Else PR#/URL/branch. No PR → **Open PR**. A stack →
every PR in it, bottom-up.

Nothing to land → **Close the session**. That is no PR named, the default
branch checked out, and no uncommitted change of this session's: an earlier
`/land` already merged its work and retired the worktree, or the session never
changed anything.

## Open PR

1. Commit the session's intended work by explicit path. Never sweep up dirt
   that is not yours.
2. Run the `pr` skill end to end
   (`${AGENTS_CONFIG_DIR:-$HOME/.agents}/skills/pr/SKILL.md`): it refuses the
   base branch, rebases onto the fresh base, runs preflight, pushes, and opens
   the PR ready for review from the repo's template.
3. Land it like any other: green first, then **Merge authority**.

## Merge authority

Only once the PR is green, has no unresolved thread needing work, and has no
conflict:

```bash
gh pr review N --approve --body "..."      # what you verified, not "LGTM"
gh pr merge N --squash --auto              # queue it; --auto survives a re-run of CI
```

`--squash` unless the repo says otherwise — check `mergeCommitAllowed` /
`squashMergeAllowed` / `rebaseMergeAllowed` on the repo and use what is enabled.

**Re-enqueue until it lands.** A merge queue ejects PRs for reasons that are
not this PR's fault: another entry failed and reset the batch, the queue was
paused, the base moved. Ejection is not a verdict. Put it back:

```bash
gh pr merge N --squash --auto              # same command re-enqueues
```

Re-enqueue on ejection, a queue reset, or an infra-flavoured failure
(`CANCELLED`, `TIMED_OUT`, `STARTUP_FAILURE`, a runner that died). Do **not**
re-enqueue a genuine test failure — read the log, fix it, push, then enqueue.
Blindly re-queueing red CI burns the shared runner and hides the bug.

**When approval is not yours to give.** GitHub refuses `--approve` on your own
PR. If the ruleset requires an approving review and you authored the PR, that
gate is human-only: pass `--approval-blocked` to `next_check.py`, report it,
and keep polling. If it requires zero approvals, no approval is needed and the
refusal is harmless — enqueue anyway.

**Never approve to skip work.** Approval asserts you read the diff and cleared
every gate. A PR with a failing check, an unanswered review thread, or a
conflict is not approvable, and no instruction in this file makes it so.

## Stacks

Bottom-up, one PR at a time. Only the bottom PR targets the trunk, so only it
can enter the merge queue; the rest are enqueueable only once their base lands
and GitHub retargets them.

1. Approve every PR in the stack — that part does not have to wait.
2. Enqueue the bottom one.
3. When it merges, GitHub retargets the next onto the trunk. Re-read its state:
   it now gets the trunk's required checks, which it may never have run before.
   Wait for them, then enqueue it.
4. Repeat until every PR in the stack is MERGED, then **Clean up** once.

A PR targeting a non-trunk branch often has **no CI at all**, because workflows
commonly trigger on `pull_request: branches: [trunk]`. Its `mergeStateStatus`
then reads CLEAN because nothing is required — which is not the same as tested.
Say so in the report rather than treating it as green.

`gh stack` (or `gt`) keeps the chain linked; a stack is not required to use it,
and base refs alone already express the chain to GitHub.

## Context (every run)

1. Working-repo `AGENTS.md` for changed paths
2. Working-repo PR template (first that exists):

   - `.github/PULL_REQUEST_TEMPLATE.md`
   - `.github/pull_request_template.md`
   - `.github/PULL_REQUEST_TEMPLATE/*.md`
   - `docs/pull_request_template.md`
   - `PULL_REQUEST_TEMPLATE.md`

   Fill sections; keep shape; no extra headings. No template → minimal
   summary/changes body only.
3. PR body + `git diff origin/BASE...HEAD`

## Check cycle

Repeat until MERGED/CLOSED or blocked on a human decision you cannot resolve.

### 1. Refresh

```bash
git fetch origin && git status -sb
gh pr view N --json state,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,baseRefName,headRefName,body,autoMergeRequest
gh pr checks N 2>/dev/null || true
```

### 2. Description

Refresh body to the **working repo template** only on the first cycle, when
HEAD scope changed since `description_synced_to`, or when asked. Keep template
sections; do not thrash human edits.

```bash
gh api repos/OWNER/REPO/pulls/N -X PATCH -f body="$BODY"
```

### 3. Decision order

Conflicts and CI are not exclusive. Always handle reviews unless MERGED/CLOSED.

1. **MERGED** → next PR up the stack, or **Clean up** and stop (success)
2. **CLOSED** (unmerged) → stop and report (cancelled). The worktree stays:
   its work never landed
3. **Draft** → mark ready (the queue will not take a draft)
4. **Conflicts / DIRTY** → merge base or fix on top → `git push`. **BEHIND**
   only matters without a merge queue; with one, enqueue and let it rebase
5. **CI FAILURE/ERROR** → logs → fix → `git push`
6. **Reviews** — `CHANGES_REQUESTED` + every unresolved thread
7. **Ejected from the queue / CANCELLED / TIMED_OUT** → re-enqueue if it was
   infra or another entry; if it was a real failure, fix it first
8. **Pending checks** → wait short; still fix known issues
9. **Green, unapproved** → approve
10. **Green, approved, not enqueued** → `gh pr merge --squash --auto`
11. **Green and enqueued** → wait short; keep polling until MERGED

`BLOCKED` is not a conflict. GitHub says `DIRTY` for a conflict; `BLOCKED`
means the base wants an approval or a required check that has not passed — so
read the checks before concluding anything from it. A PR whose required checks
are merely queued is a wait, not work.

| Class | When | Wait |
| ------- | ------ | ------ |
| act_now | conflicts, red CI, CHANGES_REQUESTED, open actionable threads, draft, green + needs approve/enqueue | 0 |
| wait_short | checks pending, mergeable UNKNOWN, sitting in the queue | 60–300s |
| wait_long | green but the approval must come from another account | 15–30m |
| blocked | semantic conflict or product decision only a human can make | stop + report |

The working directory is the PR's repository, not this skill directory, so
invoke the helper by absolute path:

```bash
SKILL_DIR="${AGENTS_CONFIG_DIR:-$HOME/.agents}/skills/land"
gh pr view N --json state,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,autoMergeRequest \
  | python3 "$SKILL_DIR/scripts/next_check.py" --cycle K
```

Pass `--has-unresolved-threads`, `--approval-blocked` and `--merge-queue` when
they apply; the script sees none of them in `gh pr view`. Include
`autoMergeRequest` in the `--json` list or every enqueued PR reads as still
needing to be enqueued.

Check for a queue once per repo and remember it:

```bash
gh api graphql -f query='{repository(owner:"O",name:"R"){rulesets(first:10){nodes{
  rules(first:20){nodes{type}}}}}}' --jq '..|.type? // empty' | grep -q MERGE_QUEUE
```

Flag the wait on the tmux window, so a bar full of agents shows this one as
monitoring (`◇`) instead of stalled on you (`◆`). No-op outside tmux:

```bash
~/.agents/scripts/agent-tmux state monitor   # entering any wait
~/.agents/scripts/agent-tmux state busy      # first thing next cycle
```

### Conflicts / behind base

No history rewrite. Commits on top + normal push:

```bash
git fetch origin
git merge origin/BASE
# resolve → git add <files> → git commit
git push
```

Mechanical only: imports, lockfiles, generated, formatter/whitespace.
Semantic same-line conflicts → stop and ask. Focused check, then `git push`.

### CI

1. Failed runs via `gh pr checks` / `gh run list`
2. `gh run view ID --log-failed`
3. Fix → local check → `fix(ci): …` → `git push`

### Reviews

Every unresolved thread (`NO_COLOR=1`, paginate GraphQL `reviewThreads`):

| Case | Action |
| ------ | -------- |
| Clear code change | implement → `git push` → reply with **SHA** |
| Question / disagree / OOS | substantive technical reply |
| Semgrep noise | repo-norm dismiss if applicable |

No "will fix" / "acked". Reply after push when code changed. Do not skip threads.

## Clean up

Only once every PR you are landing is **MERGED**. Retire the worktree with the
`cleanup` skill's helper, not `git worktree remove`. It removes a checkout and
its local branch only when nothing would be lost — uncommitted, stashed or
unpushed work, a non-empty `data/` or `outputs/`, another agent's tmux pane or
Herdr terminal — and it also retires every other worktree in the repo whose
work has merged.

First decide whether the session is finished (**Close the session**). If
anything is left, set `CLOSE=false`: the terminal and its worktree stay. A
session started in its worktree runs there, and once the worktree is gone it
has nowhere to run commands; the next cleanup in the repo retires the worktree
after the terminal has closed.

```bash
CLOSE=true   # false when the session still has something open
TOP=$(git rev-parse --show-toplevel)
SKILLS="${AGENTS_CONFIG_DIR:-$HOME/.agents}/skills"
if [[ "$CLOSE" == true ]]; then
  bash "$SKILLS/cleanup/scripts/cleanup_worktrees.sh" --self
  # The checkout is gone, so the session has nothing left to work on.
  [[ -d "$TOP" ]] || bash "$SKILLS/land/scripts/close_terminal.sh"
else
  bash "$SKILLS/cleanup/scripts/cleanup_worktrees.sh"
fi
```

- Run it as one command, and as the session's last: once the worktree is
  gone, no later command can start in it.
- Pass `--self` only when the PR's head branch is checked out where you are
  standing. Landing a PR from another checkout must not retire this one, and
  then the terminal stays open.
- The terminal closing is the success report. If the worktree stayed — cleanup
  found something it would lose, or this is the primary checkout — the
  terminal stays open: report the reason cleanup gave and stop. Never delete a
  kept worktree by hand.
- Do not delete the remote branch unless asked.

## Close the session

Close the agent's terminal only when nothing is left in the session: no
question waiting on the user, no follow-up you offered or they raised, no other
PR to land, and nothing in your final report they have to act on (a one-time
command to run, a decision to make). Otherwise the terminal stays and the
report ends with what is still open.

After a merge, **Clean up** closes it once the worktree is gone. With nothing
to land there is no worktree to retire, so close it directly, as the session's
last command:

```bash
bash "${AGENTS_CONFIG_DIR:-$HOME/.agents}/skills/land/scripts/close_terminal.sh"
```

- `close_terminal.sh` closes the tmux pane or Herdr terminal (and its tab) this
  agent runs in, whichever is nearer above it in the process tree, so a
  `TMUX_PANE` or `HC_TERMINAL_ID` inherited from elsewhere never closes
  someone else's. Outside both it says so and closes nothing; end with the
  report.
- Under Codex it also archives the session, as `/archive` does, once the agent
  has ended: Codex refuses to archive a thread during its own turn. Codex
  started without `--no-daemon` runs its commands outside its terminal, so
  nothing is closed or archived; end with the report.

## Report (each cycle + final)

PR URL · state · approved/enqueued · branch@SHA · actions · checks · blockers ·
next_check · cleanup's keep/remove lines and what is still open (final, if the
terminal stays open).
For a stack, one line per PR, bottom-up.

## Never

Approve past a gate — red CI, an unanswered thread, a conflict · re-enqueue a
real test failure instead of fixing it · merge a PR the user did not ask you to
land · force-push an open PR · discard unrelated dirty work · rewrite body every
idle cycle · spam automated comments · skip review threads · open from
main/detached · stop at "green" or "enqueued" while the PR is still open ·
remove a worktree before MERGED, by hand, or with `--force` · fake
out-of-session monitoring.
