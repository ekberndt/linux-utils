---
name: babysit-pr
description: >
  Keep fixing a GitHub PR until it merges: CI, review comments, conflicts, and
  template-shaped body. Assumes the user already enabled autosquash / auto-merge.
  Commits go on top with normal git push (no force). Invoke with /babysit-pr.
argument-hint: "[PR# | branch] | check | status"
user-invocable: true
---

# Babysit PR

Invoke only as **`/babysit-pr`**.

**Goal:** keep the PR mergeable and unblocked until **GitHub merges it**. The
user already enabled **autosquash** (auto-merge / merge queue with squash). Do
**not** merge the PR yourself, do **not** toggle autosquash, and do **not**
claim the job is done when the PR is only "green" or "ready" — done means
`state == MERGED` (or the user cancelled / closed it).

Use `git` + `gh`. Prefer harness schedulers/loops when available; otherwise
poll in-session with `next_check.py` waits. Do not claim monitoring continues
after the session ends unless a real scheduler is running.

Optional state: `~/.agents/babysit-pr/state-<owner__repo>.json`.

## Contract

- Work until **merged** or **closed**, or the user stops babysitting.
- Clear every agent-actionable blocker: red CI, conflicts, behind base,
  review changes, unresolved threads that need code or a real answer.
- Leave human-only gates alone (missing approvals, CODEOWNERS, org policy) —
  report them and keep polling so you catch the next actionable failure.
- PR title/body follow the **working repo's PR template** + `AGENTS.md`
  (template shape; AGENTS wins wording conflicts).
- New commits on top + normal **`git push`**. Never force-push.

## Resolve target

```bash
gh auth status
gh pr view --json number,url,title,state,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,baseRefName,headRefName,body,autoMergeRequest
```

Default: current branch. Else PR#/URL/branch. No PR → **Open PR**.

**Stacks:** process bottom-up. Prefer commits on top + `git push` per branch
unless `gt` / `gh stack` is already in use.

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
4. Open **ready** (not draft) so autosquash can land, unless the user asked draft:

```bash
gh pr create --base BASE --head BRANCH --title "..." --body-file BODY.md
```

Body from the working repo's template via `--body-file`. User enables
autosquash; do not set auto-merge yourself unless they ask.

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

1. **MERGED** → cleanup; stop (success)
2. **CLOSED** (unmerged) → cleanup; stop (cancelled)
3. **Draft** → mark ready if the user wants merge (autosquash needs non-draft)
4. **Conflicts / DIRTY / behind** → merge base or fix on top → `git push`
5. **CI FAILURE/ERROR** → logs → fix → `git push`
6. **Reviews** — `CHANGES_REQUESTED` + every unresolved thread
7. **CANCELLED/TIMED_OUT checks** → report; re-check next loop (no invented fixes)
8. **Pending checks** → wait short; still fix known issues
9. **Healthy + autosquash path clear** → wait short/medium for merge; do not stop

"Healthy" means mergeable, checks green, no CHANGES_REQUESTED, no unresolved
threads that need work. Then autosquash should land — keep polling until MERGED.

| Class | When | Wait |
| ------- | ------ | ------ |
| act_now | conflicts, red CI, CHANGES_REQUESTED, open actionable threads, draft blocking merge | 0 |
| wait_short | checks pending, mergeable UNKNOWN, green + waiting for autosquash | 60–300s |
| wait_long | green but blocked only on human review/approval | 15–30m |
| blocked | semantic conflict or product decision only a human can make | stop + report |

```bash
gh pr view N --json state,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup \
  | python3 "${SKILL_DIR}/scripts/next_check.py" --cycle K
```

`SKILL_DIR` = this skill directory. Prefer shorter waits while green and
waiting for autosquash than when idle without auto-merge.

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

PR URL · state · autosquash/auto-merge if visible · branch@SHA · actions ·
checks · blockers · next_check · cleanup (final only).

## Never

Merge the PR yourself · enable/disable autosquash unprompted · force-push ·
discard unrelated dirty work · rewrite body every idle cycle · spam automated
comments · skip review threads · open from main/detached · stop at "green" while
the PR is still open · fake out-of-session monitoring.
