---
name: babysit-pr
description: >
  Steward GitHub PR(s) until merged, closed, or ready: fix CI, address review
  comments, resolve conflicts with commits on top (normal git push, no force),
  keep the body shaped to the working repo's PR template and AGENTS.md. Use when
  asked to babysit, shepherd, keep green, fix CI, or address review feedback.
  Invoke with /babysit-pr.
argument-hint: "[PR# | branch] | check | status"
user-invocable: true
---

# Babysit PR

Invoke only as **`/babysit-pr`**.

Use `git` + `gh` everywhere. Use harness loops/schedulers/worktrees only when
present. Do not claim monitoring continues after the session ends unless a real
scheduler is running.

Optional multi-cycle state: `~/.agents/babysit-pr/state-<owner__repo>.json`.

## Contract

- Drive one PR (or one stack, bottom-up) until merged, closed, or the user stop
  condition (e.g. green + ready for review).
- PR title/body must follow the **PR template in the repo you are babysitting**
  (not a generic default, unless that repo has no template).
- Prefer new commits on top + normal **`git push`**. Do not force-push.

## Resolve target

```bash
gh auth status
gh pr view --json number,url,title,state,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,baseRefName,headRefName,body
```

Default: current branch. Else explicit PR#/URL/branch. No PR → **Open PR**.

**Stacks:** if base is another open PR's head (or others base on this head),
process bottom-up. Use `gt` / `gh stack` only when already in play; else add
commits on top of each branch and `git push` (no force).

## Context (every run)

1. `AGENTS.md` (and nested path AGENTS) for the **working repo's** changed paths
2. That repo's PR template — look in order and use the first that exists:

   - `.github/PULL_REQUEST_TEMPLATE.md`
   - `.github/pull_request_template.md`
   - `.github/PULL_REQUEST_TEMPLATE/*.md` (directory templates)
   - `docs/pull_request_template.md`
   - `PULL_REQUEST_TEMPLATE.md`

   Fill the template's sections; keep its shape; do not invent extra headings.
   If AGENTS.md constrains PR wording, both apply — AGENTS wins on conflict.
   Only fall back to a minimal summary/changes body when the repo has no
   template.
3. Current PR body + `git diff origin/BASE...HEAD`

## Open PR

1. Refuse main/master/detached/empty. Base = user or repo default.
2. Commit intentional dirty work (explicit paths) or require commits ahead of base.
3. `git fetch` · if behind base, merge `origin/BASE` (or commit fixes on top) —
   mechanical conflicts only · **`git push`** (never force).
4. Draft unless user asked ready. Body must be filled from the **working repo's**
   PR template (see Context) via `--body-file` — never a placeholder:

```bash
gh pr create --draft --base BASE --head BRANCH --title "..." --body-file BODY.md
```

## Check cycle

### Refresh

```bash
git fetch origin && git status -sb
gh pr view N --json state,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,baseRefName,headRefName,body
gh pr checks N 2>/dev/null || true
```

### Description

Normalize body to the **working repo's PR template** **only** when:

- first babysit on this PR, or
- HEAD scope changed since `description_synced_to`, or
- the user asked to refresh the description.

Keep the template's section order and headings; fill from the current diff.
Do not thrash human edits or add non-template sections.

```bash
gh api repos/OWNER/REPO/pulls/N -X PATCH -f body="$BODY"
```

### Decision order

Conflicts and CI are not exclusive; always handle reviews unless MERGED/CLOSED.

1. **MERGED/CLOSED** → cleanup; stop
2. **Conflicts** (`CONFLICTING` / `DIRTY`) → merge base or fix on top; normal push
3. **CI FAILURE/ERROR** → logs → fix
4. **Reviews** — `CHANGES_REQUESTED` body + every unresolved thread
5. **CANCELLED/TIMED_OUT/…** (no hard fails) → `ci_needs_attention`
6. **Pending checks** → still act on known issues
7. **Healthy** — mergeable, no bad conclusions, no changes requested, no open threads

| Class | When | Wait |
| ------- | ------ | ------ |
| act_now | conflicts, red CI, CHANGES_REQUESTED, open threads | 0 |
| wait_short | pending checks, mergeable UNKNOWN | 60–300s |
| wait_long | green + human review (`REVIEW_REQUIRED`), idle draft | 15–30m |
| blocked | semantic conflict, product decision needed | stop |

```bash
gh pr view N --json state,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup \
  | python3 "${SKILL_DIR}/scripts/next_check.py" --cycle K
```

`SKILL_DIR` = this skill's directory. Flags: `--has-unresolved-threads`,
`--agent-can-fix-ci` / `--no-agent-can-fix-ci`.

### Conflicts / behind base

Do **not** rewrite history or force-push. Put new commits on top and use a
normal push:

```bash
git fetch origin
git merge origin/BASE
# resolve → git add <files> → git commit
git push
```

Mechanical only: imports, lockfiles, generated, formatter/whitespace. Same-line
**semantic** conflicts → stop and ask. After resolve, focused build/lint on
touched files, then `git push` (no `--force` / `--force-with-lease`).

### CI

1. Failed run IDs via `gh pr checks` / `gh run list`
2. `gh run view ID --log-failed`
3. Minimal fix + local check + commit (`fix(ci): …`) + `git push`

### Reviews

Paginate GraphQL `reviewThreads` with `NO_COLOR=1`. Every unresolved thread:

| Case | Action |
| ------ | -------- |
| Clear correct code change | implement → `git push` → reply with **SHA** |
| Question / disagree / out of scope | substantive technical reply |
| Semgrep noise | repo-norm dismiss if applicable |

Never "will fix" / "acked" / empty thanks. Reply after push when code changed.
Do not silently skip threads.

### Draft

Stay draft unless user/AGENTS say otherwise. Mark ready only for an explicit
"ready for review" stop condition when healthy.

## Finalization

After **merged/closed** only (not mere green):

1. Clean worktree required; never discard unrelated dirt
2. Remove linked worktree if used (not the primary)
3. Local branch `-d` (merged) or `-D` (closed unmerged)
4. Do not delete remote unless asked

## Report

PR URL · state · branch@SHA · actions · local/remote checks · blockers ·
next_check `{seconds,reason,class}` · cleanup status (final).

## Never

Force-push (`--force` or `--force-with-lease`) · discard unrelated dirty work ·
rewrite body every idle cycle · spam automated comments · skip review threads ·
open from main/detached · fake out-of-session monitoring.
