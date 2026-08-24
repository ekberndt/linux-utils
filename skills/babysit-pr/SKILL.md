---
name: babysit-pr
description: >
  Land a GitHub PR, or a stack of them: fix red CI, resolve conflicts, answer
  review threads, keep the body template-shaped, then approve, enable auto-merge
  with squash, and keep re-enqueueing until GitHub merges it. Use when the user
  says "/babysit-pr", "babysit this PR", "watch this PR until it merges", "get
  this PR green", or asks to keep a PR unblocked.
argument-hint: "[PR# | branch] | check | status"
user-invocable: true
---

# Babysit PR

Invoke only as **`/babysit-pr`**.

**Goal:** land the PR. Done means `state == MERGED` (or the user cancelled /
closed it) — never "green", never "ready", never "enqueued".

**Invoking `/babysit-pr` is the approval.** Asking you to babysit a PR is the
user saying they want it merged, so you carry the authority to get it there:
approve it, enable auto-merge with squash, and put it back in the merge queue
as often as the queue ejects it. What you may not do is *skip* a gate — approve
past red CI, an unanswered review thread, or a conflict. Clear the gate, then
use the authority. See **Merge authority**.

Use `git` + `gh`. Prefer harness schedulers/loops when available; otherwise
poll in-session with `next_check.py` waits. Do not claim monitoring continues
after the session ends unless a real scheduler is running.

Optional state: `~/.agents/babysit-pr/state-<owner__repo>.json`.

## Contract

- Work until **merged** or **closed**, or the user stops babysitting.
- Clear every agent-actionable blocker: red CI, conflicts, behind base,
  review changes, unresolved threads that need code or a real answer.
- Then land it: approve, auto-merge with squash, enqueue, re-enqueue.
- Leave gates you genuinely cannot clear (CODEOWNERS you are not in, an
  approval GitHub refuses from this account, org policy) — report them and keep
  polling so you catch the next actionable failure.
- PR title/body follow the **working repo's PR template** + `AGENTS.md`
  (template shape; AGENTS wins wording conflicts).
- New commits on top + normal **`git push`**. Never force-push.

## Resolve target

```bash
gh auth status
gh pr view --json number,url,title,state,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,baseRefName,headRefName,body,autoMergeRequest
```

Default: current branch. Else PR#/URL/branch. No PR → **Open PR**. A stack →
every PR in it, bottom-up.

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
4. Repeat until every PR in the stack is MERGED.

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

## Open PR

1. Refuse main/master/detached/empty.
2. Commit intentional dirty work (explicit paths) or require commits ahead of base.
3. If behind base: `git merge origin/BASE` (or fix commits on top) → `git push`.
4. Open **ready** (not draft) so the queue can take it, unless the user asked
   for a draft:

```bash
gh pr create --base BASE --head BRANCH --title "..." --body-file BODY.md
```

Body from the working repo's template via `--body-file`. Then babysit it like
any other: green first, then **Merge authority**.

## Check cycle

Repeat until MERGED/CLOSED or blocked on a human decision you cannot resolve.

### 1. Refresh

```bash
git fetch origin && git status -sb
gh pr view N --json state,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,baseRefName,headRefName,body,autoMergeRequest
gh pr checks N 2>/dev/null || true
```

### 2. Description

Refresh body to the **working repo template** only on first babysit, when HEAD
scope changed since `description_synced_to`, or when asked. Keep template
sections; do not thrash human edits.

```bash
gh api repos/OWNER/REPO/pulls/N -X PATCH -f body="$BODY"
```

### 3. Decision order

Conflicts and CI are not exclusive. Always handle reviews unless MERGED/CLOSED.

1. **MERGED** → next PR up the stack, or cleanup and stop (success)
2. **CLOSED** (unmerged) → cleanup; stop (cancelled)
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
SKILL_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/babysit-pr"
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

## Finalization

Only after **MERGED** or **CLOSED**:

1. Worktree clean (never discard unrelated dirt)
2. Remove linked worktree if used (not primary)
3. Local branch `-d` if merged, `-D` if closed unmerged
4. Do not delete remote unless asked

## Report (each cycle + final)

PR URL · state · approved/enqueued · branch@SHA · actions · checks · blockers ·
next_check · cleanup (final only). For a stack, one line per PR, bottom-up.

## Never

Approve past a gate — red CI, an unanswered thread, a conflict · re-enqueue a
real test failure instead of fixing it · merge a PR the user did not ask you to
babysit · force-push · discard unrelated dirty work · rewrite body every idle
cycle · spam automated comments · skip review threads · open from
main/detached · stop at "green" or "enqueued" while the PR is still open · fake
out-of-session monitoring.
