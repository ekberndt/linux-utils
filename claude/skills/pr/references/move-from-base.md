# Moving commits off the base branch

If `/pr` was invoked while `HEAD` is on `main`/`master` (or the repo's default branch), move the work to a new branch before doing anything else.

## Determine what to move
```bash
AHEAD=$(git rev-list --count "origin/$BASE..HEAD")
```
- `AHEAD == 0`: nothing to PR. Stop and tell the user.
- `AHEAD >= 1`: those commits need to land on a new branch, and local `$BASE` needs to be reset to `origin/$BASE` so it stays clean.

## Pick a branch name (Conventional Commits)

1. Inspect the commits:
   ```bash
   git log "origin/$BASE..HEAD" --format='%s%n%b'
   git diff "origin/$BASE...HEAD" --stat
   ```
2. Map to a type: `feat` / `fix` / `docs` / `refactor` / `perf` / `test` / `build` / `ci` / `chore`.
3. Slug from the first commit subject: lowercase, kebab-case, drop articles/punctuation, ~40 chars max.
4. Format: `<type>/<slug>` (e.g. `feat/oauth-device-flow`, `fix/retry-backoff-overflow`).
5. If inference is ambiguous (commits span types, unclear intent), **ask the user** with 2–3 suggested names.

## Move the commits

This rewrites local `$BASE` to match `origin/$BASE`. Safe because commits are preserved on the new branch — but if the user had unpushed commits on local `$BASE` that they didn't intend to PR, those move too. **Surface this and confirm before the reset:** "Moving N commits from $BASE to $NEW_BRANCH and resetting local $BASE to origin/$BASE — confirm?"

```bash
NEW_BRANCH="<inferred-name>"
git branch "$NEW_BRANCH"
git reset --hard "origin/$BASE"
git checkout "$NEW_BRANCH"
BRANCH="$NEW_BRANCH"
```

Then return to step 2 of SKILL.md.
