---
name: pr
description: Rebase current branch onto main, resolve conflicts where mechanical, run preflight checks, and open a PR via gh CLI. Use when the user says "/pr", "open a PR", "send this for review", or asks to sync-and-submit the current branch. Refuses to run on main/master. Requires gh CLI authenticated and a clean working tree.
allowed-tools: Bash(git *), Bash(gh *), Bash(rg *), Bash(test *), Read, Edit
---

# /pr — rebase, fix, and open a PR

## 1. Preconditions
Stop on first failure:
```bash
git rev-parse --is-inside-work-tree >/dev/null
BRANCH=$(git branch --show-current)
test -z "$(git status --porcelain)" || { echo "Working tree not clean"; exit 1; }
gh auth status >/dev/null
BASE=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
```
If working tree is dirty, stop and ask the user (commit/stash/abort).

**If `BRANCH` equals `BASE`** (or is `main`/`master`): see `references/move-from-base.md` before continuing.

## 2. Fetch and rebase
```bash
git fetch origin "$BASE":refs/remotes/origin/"$BASE"
git fetch . refs/remotes/origin/"$BASE":"$BASE" 2>/dev/null || true
git rebase "origin/$BASE"
```
The second `fetch .` updates the local base ref without checking it out — works even if another worktree has it checked out.

## 3. Conflict handling
If rebase stops with conflicts:

1. `git diff --name-only --diff-filter=U` to list them.
2. Resolve **only if mechanical**:
   - Import/lockfile/generated-file: regenerate or take both.
   - Whitespace/formatter-driven: take ours, re-run formatter.
   - Same-line semantic conflicts: **stop, surface the conflict block, ask the user.** Never guess on logic.
3. `git add <file>` then `git rebase --continue`.
4. If resolution is unclear or user hasn't responded: `git rebase --abort` and report status. Never leave a partial-rebase state.

## 4. Preflight

Two passes: **auto-fix** then **verify**. Detect by file presence; skip silently if absent. Scope to files this branch touches so unrelated repo debt doesn't ride along:

```bash
mapfile -t CHANGED < <(git diff --name-only "origin/$BASE...HEAD")
[ ${#CHANGED[@]} -eq 0 ] && { echo "No changed files vs $BASE"; exit 0; }
```

### 4a. Auto-fix (non-fatal, `|| true`)

| Repo signal | Fixer |
|---|---|
| `.pre-commit-config.yaml` | `pre-commit run --files "${CHANGED[@]}"` (use `uv tool run pre-commit ...` or `pipx run pre-commit ...` if binary missing) |
| `pyproject.toml` with `[tool.ruff]` | `ruff check --fix "${CHANGED[@]}"` then `ruff format "${CHANGED[@]}"` |

If auto-fix modified files, commit as a **separate** fixup — never amend:
```bash
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git commit -m "chore: apply pre-commit auto-fixes"
fi
```

### 4b. Verify (must pass with zero new modifications)

| File present | Run |
|---|---|
| `.pre-commit-config.yaml` | `pre-commit run --files "${CHANGED[@]}"` (second run — fails if anything still wrong) |
| `pyproject.toml` or `setup.py` | `pytest -x` if `tests/` exists; `ruff check .` if ruff configured and pre-commit didn't cover it |

On verifier failure: report which file/rule/command, do **not** open the PR, ask the user (fix / skip / abort). Don't loop the auto-fix pass — if it didn't resolve the first time, it won't.

## 5. Push
Rebased, so use lease:
```bash
git push --force-with-lease origin "$BRANCH"
```
No upstream yet: `git push -u origin "$BRANCH"` first. **Never** plain `--force`.

## 6. PR body

Check for a repo template:
```bash
TEMPLATE=""
for f in .github/PULL_REQUEST_TEMPLATE.md .github/pull_request_template.md \
         docs/pull_request_template.md PULL_REQUEST_TEMPLATE.md; do
  test -f "$f" && TEMPLATE="$f" && break
done
```

If a repo template exists, fill its sections — **but skip/leave-empty any "Test plan", "Testing", "Verification", or "QA" section.** Don't fabricate a test plan.

Otherwise use this default template:

```markdown
## Summary
<1–2 sentences on the end state this PR produces and why.>

## Changes
- <bullet>
- <bullet>
```

Rules:
- **Title**: imperative, no period, <72 chars. If repo uses conventional commits (`git log origin/$BASE..HEAD --oneline` to check), match the prefix style.
- **Summary**: end state + motivation, not a recap of commits.
- **Bullets**: describe end state, not the act of changing. Skip trivial churn. Group with bold lead-ins (no headers) if >8 items.
- Generate from `git diff origin/$BASE...HEAD` and `git log origin/$BASE..HEAD --format='%s%n%b'`. Describe end state vs base, not commits chronologically.
- **Never** add a "Test plan" / "Testing" / "Verification" section. Not in the default template, not appended to repo templates that omit it. If the user wants one, they'll ask.
- **No** "Generated with Claude" footer, Co-Authored-By trailer, or AI attribution unless asked.
- If branch name implies an issue (`fix/123-foo`), append `Fixes #123`.

## 7. Create / update the PR

Write body to a tempfile and pass via `--body-file` (avoids shell-escaping issues with backticks/quotes):

```bash
EXISTING=$(gh pr list --head "$BRANCH" --json number -q '.[0].number')
if [ -n "$EXISTING" ]; then
  gh pr edit "$EXISTING" --title "<title>" --body-file "$BODY"
else
  gh pr create --base "$BASE" --head "$BRANCH" --title "<title>" --body-file "$BODY"
fi
```

## 8. Output
Print the PR URL on success. On failure, print the failing step and current git state (`git status`, `git log -1`) so the user can pick up where it stopped.
