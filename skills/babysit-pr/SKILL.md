---
name: babysit-pr
description: Continuously steward a GitHub pull request until it is finalized. Use when Codex is asked to babysit, shepherd, monitor, keep green, rebase, resolve merge conflicts, fix failing CI, address review comments, or keep a PR description/comment aligned with the repository PR template and AGENTS instructions.
---

# Babysit PR

## Core Contract

Keep one PR moving until it is merged, closed, or explicitly declared ready by the user. Work from the local checkout when available, keep GitHub state and local branch state aligned, and do not claim background monitoring will continue after the active Codex session ends.

If the platform provides goal or auto-resume tooling and the user explicitly asked to babysit until finalization, use it. Otherwise run a bounded poll loop in the active session and report the next recommended check time before stopping.

## Required Context

Resolve the PR first:

```bash
gh pr view --json number,url,title,state,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,baseRefName,headRefName,body,headRepositoryOwner,headRepository
```

Then read, in this order:

1. `AGENTS.md` files that govern the repo paths being changed, plus any referenced local agent files that exist.
2. `.github/pull_request_template.md` or repo-specific PR template variants.
3. The current PR body and latest pushed diff.

Treat AGENTS instructions and the PR template as authoritative for wording, checks, branch hygiene, and PR description shape.

## Main Loop

Repeat until finalized or blocked by an external human decision:

1. Refresh state: `git fetch origin`, `git status -sb`, `gh pr view ...`, and check whether the branch is behind the base.
2. Normalize the PR body/comment to the repo template. Keep exactly the template's shape; do not add extra sections unless the template or AGENTS instructions require them. Prefer REST for body edits when `gh pr edit` hits GraphQL metadata failures:

   ```bash
   gh api repos/OWNER/REPO/pulls/PR -X PATCH -f body="$BODY"
   ```

3. Address review comments and requested changes. If the `github:gh-address-comments` skill is available, use it for unresolved review threads; otherwise use `gh api graphql` or `gh pr view --comments` to identify actionable comments.
4. Fix CI failures. If the `github:gh-fix-ci` skill is available, use it. Otherwise inspect checks with `gh pr checks`, `gh run view --log-failed`, and local reproduction.
5. Rebase on the target branch when the PR is behind or has merge conflicts:

   ```bash
   git fetch origin
   git rebase origin/BASE
   ```

   Resolve conflicts in the smallest correct way, run relevant checks, then `git push --force-with-lease`. Never use destructive reset/checkout commands to discard user work.
6. Commit only intentional changes. Stage explicit files unless the worktree is known to contain only PR-babysitting changes.
7. Push after every completed fix, then refresh PR state.
8. Decide the next wait:
   - Immediate action needed: no wait.
   - Checks pending: short wait, usually 60-300 seconds.
   - Awaiting human review with green checks: longer wait, usually 15-30 minutes.
   - Repeated same blocker for three consecutive loops: mark/report blocked with the exact blocker.

Use `scripts/next_check.py` on a saved PR JSON snapshot when a deterministic wait suggestion is useful.

## CI And Review Rules

- Prefer focused checks based on the changed files and failing jobs; broaden only when shared behavior changes or AGENTS/PR instructions require it.
- When a check fails remotely but not locally, read the remote logs before guessing.
- When review feedback requests a change, implement it or explain concretely why it should not be implemented. Do not resolve or dismiss comments silently.
- Keep PR comments concise and template-shaped. If the repo template asks for "summary line, then bullets", do exactly that.
- If a PR is draft, keep it draft unless the user asks to mark ready or the repo instructions say otherwise.

## Finalization

Treat the PR as finalized when one of these is true:

- The PR is merged.
- The PR is closed by a human.
- The user-defined stopping condition is met, such as "green and ready for review."

Before final response, report:

- PR URL and current state.
- Branch and latest commit.
- Issues fixed during babysitting.
- Checks run locally and remote check status.
- Any remaining human blockers.
