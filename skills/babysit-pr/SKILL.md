---
name: babysit-pr
description: >
  Steward GitHub PR(s) until merged, closed, or ready: rebase, fix CI, address
  review comments, resolve conflicts, keep the body template-shaped per AGENTS.md.
  Use for babysit, shepherd, keep green, restack, fix CI, review feedback, or
  open/maintain a PR. Triggers: /babysit-pr, /pr-babysit.
argument-hint: "[PR# | branch] | check | status"
user-invocable: true
---

# Babysit PR

Portable skill for Grok, Claude Code, and Codex. Installed at
`~/.agents/skills/babysit-pr` (shared tree; also linked for Claude/Codex).

Use `git` + `gh` everywhere. Use harness loops/schedulers/worktrees only when
present. Do not claim monitoring continues after the session ends unless a real
scheduler is running.

Optional multi-cycle state: `~/.agents/babysit-pr/state-<owner__repo>.json`.

## Contract

- Drive one PR (or one stack, bottom-up) until merged, closed, or the user stop
  condition (e.g. green + ready for review).
- **Never merge.** Never plain `--force` (only `--force-with-lease`).
- Max **3 code fixes per PR per cycle**. Still evaluate every review thread.
- Same failure signature @ same HEAD **3×** → blocked; stop pushing.
- Prefer in-place checkout when it is the PR head and has no unrelated dirt;
  otherwise use a worktree. Stage explicit paths.

## Resolve target

```bash
gh auth status
gh pr view --json number,url,title,state,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,baseRefName,headRefName,body
```

Default: current branch. Else explicit PR#/URL/branch. No PR → **Open PR**.

**Stacks:** if base is another open PR's head (or others base on this head),
process bottom-up. Use `gt` / `gh stack` only when already in play; else plain
rebase + `--force-with-lease` per branch.

## Context (every run)

1. `AGENTS.md` for changed paths
2. PR template under `.github/`
3. PR body + `git diff origin/BASE...HEAD`

## Open PR

1. Refuse main/master/detached/empty. Base = user or repo default.
2. Commit intentional dirty work (explicit paths) or require commits ahead of base.
3. `git fetch && git rebase origin/BASE` → mechanical conflicts only → push.
4. Draft unless user asked ready; template-shaped body via `--body-file`:

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

Rewrite body to template shape **only** on first babysit, when HEAD scope changed
since `description_synced_to`, or when asked. Do not thrash human edits.

```bash
gh api repos/OWNER/REPO/pulls/N -X PATCH -f body="$BODY"
```

### Decision order

Conflicts and CI are not exclusive; always handle reviews unless MERGED/CLOSED.

1. **MERGED/CLOSED** → cleanup; stop
2. **Conflicts** (`CONFLICTING` / `DIRTY`) → rebase/restack
3. **CI FAILURE/ERROR** → logs → fix or one flake rerun
4. **Reviews** — `CHANGES_REQUESTED` body + every unresolved thread
5. **CANCELLED/TIMED_OUT/…** (no hard fails) → `ci_needs_attention`
6. **Pending checks** → still act on known issues
7. **Healthy** — mergeable, no bad conclusions, no changes requested, no open threads

| Class | When | Wait |
| ------- | ------ | ------ |
| act_now | conflicts, red CI, CHANGES_REQUESTED, open threads | 0 |
| wait_short | pending checks, mergeable UNKNOWN | 60–300s |
| wait_long | green + human review (`REVIEW_REQUIRED`), idle draft | 15–30m |
| blocked | 3× same fail, semantic conflict, product call | stop |

```bash
gh pr view N --json state,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup \
  | python3 "${SKILL_DIR}/scripts/next_check.py" --cycle K
```

`SKILL_DIR` = this skill's directory. Flags: `--has-unresolved-threads`,
`--agent-can-fix-ci` / `--no-agent-can-fix-ci`.

### Conflicts

```bash
git fetch origin && git rebase origin/BASE
# resolve → git add <files> → git rebase --continue
git push --force-with-lease
```

Mechanical only: imports, lockfiles, generated, formatter/whitespace. Same-line
**semantic** conflicts → stop and ask. Rebase: `HEAD` is base; bottom is replay.
After resolve, focused build/lint on touched files before push.

### CI

1. Failed run IDs via `gh pr checks` / `gh run list`
2. `gh run view ID --log-failed`
3. Code bug → minimal fix + local check + commit (`fix(ci): …`) + push
4. Flake/infra → **one** `gh run rerun`; do not paper over infra

### Reviews

Paginate GraphQL `reviewThreads` with `NO_COLOR=1`. Every unresolved thread:

| Case | Action |
| ------ | -------- |
| Clear fix, under cap | implement → push → reply with **SHA** |
| Clear fix, cap hit | technical plan reply (files/lines/why) |
| Question / disagree / OOS | substantive reply; do not silent-resolve |
| Semgrep noise | repo-norm dismiss if applicable |

Never "will fix" / "acked" / empty thanks. Reply after push when code changed.

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

Merge · plain `--force` · discard unrelated dirty work · rewrite body every idle
cycle · spam automated comments · skip review threads · open from main/detached ·
fake out-of-session monitoring.
