#!/usr/bin/env bash
# cleanup_worktrees.sh: remove the worktrees an agent has finished with, and the
# branches that only existed to hold them.
#
# A worktree goes only on evidence that it held work and that the work landed:
# its own commits are in the default branch, or GitHub says its PR merged. Being
# contained in the default branch is not that evidence — a checkout that has
# committed nothing is contained too, and removing one destroys a live
# workspace. Pushing is not enough either: a branch with an open PR is still
# being revised — usually by the agent that opened it, which pushes to publish
# a review and keeps working — so it stays.
#
# --self also retires the worktree this runs from, for an agent closing out its
# own session once its PRs have landed. It is judged by the same rules, it goes
# last, and it leaves the caller standing in a directory that no longer exists.
#
# A repo can ask for one more step. If the primary checkout holds an executable
# tools/cleanup-hook.sh (or .cleanup-hook), it runs once at the end, from that
# checkout, after every removal including --self. Removing a worktree orphans
# whatever the repo keyed to its path — a Bazel output base, a virtualenv, a
# container volume — and nothing can tell that state is dead until the directory
# is actually gone, so afterwards is the only correct time. --dry-run names the
# hook instead of running it; CLEANUP_NO_HOOK=1 skips it.
#
# Usage: cleanup_worktrees.sh [--dry-run] [--self] [--post-hook CMD]
set -euo pipefail

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

dry_run=false
include_self=false
post_hook=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=true ;;
    --self) include_self=true ;;
    --post-hook)
      shift
      [ $# -gt 0 ] || die "--post-hook needs a command"
      post_hook="$1"
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"

# The main worktree, and whether the repository is bare and therefore has none.
# Asking git for --git-common-dir/.. is wrong for the bare layout an agent that
# lives in worktrees usually has: it names the bare repo's PARENT directory,
# which is not a checkout at all and is exactly where unrelated sibling clones
# sit. That was survivable while $primary was only a `git -C` target. It is not
# survivable now that the hook is executed from it. The first record of
# `git worktree list` is the main worktree in both layouts, and carries a `bare`
# line when there is no checkout to speak of.
primary=""
primary_bare=false
while IFS= read -r line; do
  case "$line" in
    worktree\ *) primary="${line#worktree }" ;;
    bare) primary_bare=true ;;
    "") break ;;
  esac
done < <(git worktree list --porcelain; printf '\n')
[ -n "$primary" ] || die "could not resolve the main worktree"
current="$(git rev-parse --show-toplevel)"

# Judging "merged" against a stale remote-tracking ref would keep a worktree
# whose PR landed minutes ago.
git fetch --quiet --prune origin 2>/dev/null || true

base="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
base="${base:-main}"
base_ref="refs/remotes/origin/$base"
git rev-parse --verify --quiet "$base_ref" >/dev/null ||
  die "no $base_ref to compare against; fetch origin first"

# Reflogs are how a branch proves it once held work of its own. With them off,
# nothing local can speak for any branch and only a merged PR retires anything,
# which is safe but keeps almost everything — so say it once rather than look
# broken.
if [ "$(git config --bool core.logAllRefUpdates 2>/dev/null || echo true)" = false ]; then
  printf 'note    reflogs are off (core.logAllRefUpdates=false); only a merged PR can retire a worktree\n' >&2
fi

# A pane's cwd, and the worktree an agent moved to (see scripts/agent-tmux), are
# the two ways a live agent says which checkout is still under it. Collected
# once: this is the only question worth asking tmux, and it has no answer at all
# when no server is running.
busy_paths=""
if command -v tmux >/dev/null 2>&1; then
  busy_paths="$(
    {
      tmux list-panes -a -F '#{pane_current_path}' 2>/dev/null || true
      tmux list-windows -a -F '#{@agent_dir}' 2>/dev/null || true
    } | sort -u
  )"
fi

# in_use <path> -> a live pane is in this worktree, or somewhere under it.
in_use() {
  local path="$1" busy
  while IFS= read -r busy; do
    [ -n "$busy" ] || continue
    case "$busy" in
      "$path" | "$path"/*) return 0 ;;
    esac
  done <<< "$busy_paths"
  return 1
}

# stashed <path> <branch> -> a stash entry belongs to this checkout. git status
# reports nothing for a stashed change, so a worktree whose only work is parked
# in one reads as clean; and refs/stash is a single ref shared by every
# worktree, so entries have to be attributed rather than counted. The branch the
# message names does that for a branch, and the commit it was taken on does it
# for a detached HEAD. Attributing by commit for a named branch would be wrong:
# two fresh worktrees sit on the same commit and would claim each other's.
stashed() {
  local path="$1" branch="$2" head entry
  head="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    case "${entry#* }" in
      "WIP on $branch:"* | "On $branch:"*)
        [ -z "$branch" ] || return 0
        ;;
      "WIP on (no branch):"* | "On (no branch):"*)
        #  Only a detached checkout can own a stash taken on "(no branch)". A
        #  named-branch worktree that merely sits on the same commit does not,
        #  and claiming it there is worse than a wrong verdict for one
        #  directory: every worktree parked on that commit stops being
        #  cleanable, each with a reason that names a stash it does not own.
        [ -z "$branch" ] || continue
        if [ -n "$head" ] &&
          [ "$(git -C "$path" rev-parse --verify --quiet "${entry%% *}^1" 2>/dev/null)" = "$head" ]; then
          return 0
        fi
        ;;
    esac
  done <<< "$(git -C "$path" stash list --format='%H %gs' 2>/dev/null || true)"
  return 1
}

# consider() reads a ref's reflog once and hands it to both of these. It is the
# only record of what the ref has held, and the whole reason this script can
# tell a merged branch from a checkout that never committed anything: once
# merged, both are contained in the default branch and the commit graph has
# nothing left to tell them apart by.
#
# committed_here <reflog> -> an entry records an operation that put a commit of
# this ref's own on it. The message list is a whitelist on purpose: anything
# unrecognised counts as no evidence, so a git that words things differently
# keeps the worktree rather than deleting it. `rebase (finish)` is deliberately
# absent — rebasing a fresh branch onto a newer base writes exactly that, with
# no commit of its own anywhere in it, and that is the routine agent warm-up.
committed_here() {
  local line
  while IFS= read -r line; do
    case "${line#* }" in
      commit:* | "commit ("* | am:* | cherry-pick:* | revert:* | *": Merge made by "*) return 0 ;;
    esac
  done <<< "$1"
  return 1
}

# reflog_landed <path> <reflog> -> every commit this ref has ever pointed at is
# on the default branch. A branch reset away from work it had made is contained
# in the base again, but its reflog holds the only pointer left to that work and
# deleting the branch drops it.
reflog_landed() {
  local path="$1" oid
  while IFS= read -r oid; do
    git -C "$path" merge-base --is-ancestor "$oid" "$base_ref" 2>/dev/null || return 1
  done < <(printf '%s\n' "$2" | awk 'NF && !seen[$1]++ { print $1 }')
  return 0
}

# pr_info <branch> -> "<state> <head oid>", or empty when GitHub knows no PR.
# Asked once per worktree: gh is by far the slowest thing in this script. The
# head oid is not optional — `gh pr list --head` answers for a branch *name*,
# and agents reuse names, so the PR only speaks for this checkout when the
# commit GitHub merged is the one standing here.
pr_info() {
  local branch="$1"
  [ -n "$branch" ] || return 0
  command -v gh >/dev/null 2>&1 || return 0
  gh pr list --head "$branch" --state all --limit 1 --json state,headRefOid \
    -q '.[] | "\(.state) \(.headRefOid)"' 2>/dev/null || true
}

keep() {
  printf 'keep    %s: %s\n' "$1" "$2"
}

# find_hook -> print the hook to run, or nothing.
#
# Resolved against the primary checkout and nowhere else. A worktree holds a
# feature branch, including a branch from a PR under review, so a hook read from
# one is whatever code happens to be checked out there. From the primary
# checkout it carries the same trust as the repo's justfile, BUILD files and
# pre-commit config, all of which already run during an ordinary build. The
# executable bit is the opt-in: a repo without the file is untouched, and a dev
# disables a committed hook with chmod -x.
find_hook() {
  local candidate
  #  A bare repository has no main checkout, so there is no working tree whose
  #  contents carry the repo's trust -- and $primary is then a directory that
  #  merely contains it. Run nothing.
  [ "$primary_bare" = false ] || return 1
  for candidate in tools/cleanup-hook.sh .cleanup-hook; do
    if [ -x "$primary/$candidate" ]; then
      printf '%s\n' "$primary/$candidate"
      return 0
    fi
  done
  return 1
}

# run_hook <label> <cmd...> -- from the primary checkout, never fatal.
#
# The working directory is load-bearing, not tidiness: a repo's reclamation tool
# finds its state through the checkout it is run from, and a worktree that has
# never built does not have that state to point at — it would report nothing and
# look like it worked. The primary checkout is also the one directory guaranteed
# to still exist after --self.
#
# The hook is the repo's code, not this script's. A non-zero exit is reported
# and the run still succeeds: every removal above already happened, and cleanup
# must not call itself failed because a repo's hook misbehaved. The timeout is a
# hang-stop, generous because a real reclamation walks terabytes, and it is an
# if/else rather than an array prefix because an empty expansion breaks under
# set -u and the guarding && aborts under set -e.
run_hook() {
  local label="$1" status=0
  shift
  printf 'hook    %s\n' "$label"
  if command -v timeout >/dev/null 2>&1; then
    (cd "$primary" && exec env CLEANUP_PRIMARY="$primary" CLEANUP_REMOVED="$removed" \
      timeout 1800 "$@") || status=$?
  else
    (cd "$primary" && exec env CLEANUP_PRIMARY="$primary" CLEANUP_REMOVED="$removed" \
      "$@") || status=$?
  fi
  [ "$status" -eq 0 ] ||
    printf 'failed  %s: exited %d; the cleanup itself succeeded\n' "$label" "$status" >&2
}

# consider <path> <branch> <skip_pane_check> -> print a verdict, and remove the
# worktree when its work has landed. 0 if it went, 1 if it stayed.
consider() {
  local path="$1" branch="$2" skip_pane_check="$3"
  local reflog_ref reflog head_now ahead pr state head_oid

  if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
    keep "$path" "uncommitted changes"
    return 1
  fi
  if stashed "$path" "$branch"; then
    keep "$path" "a stash is parked on it — git status does not show one"
    return 1
  fi
  if [ "$skip_pane_check" = false ] && in_use "$path"; then
    keep "$path" "a tmux pane is still in it"
    return 1
  fi

  # A detached worktree keeps its own reflog under HEAD; a branch's reflog
  # outlives any one worktree, so prefer it when there is a branch.
  reflog_ref=HEAD
  [ -z "$branch" ] || reflog_ref="refs/heads/$branch"
  reflog="$(git -C "$path" reflog show --format='%H %gs' "$reflog_ref" 2>/dev/null || true)"
  head_now="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
  ahead="$(git -C "$path" rev-list --count "$base_ref..HEAD" 2>/dev/null || echo 0)"
  pr=""
  state=""
  head_oid=""

  if [ "${ahead:-0}" -eq 0 ]; then
    # Contained in the default branch. That is what a merged branch looks like,
    # and equally what a checkout that has never committed anything looks like —
    # including one created minutes ago, which is a live workspace. Ancestry
    # cannot separate them, so ask what this ref has actually held.
    if committed_here "$reflog"; then
      if ! reflog_landed "$path" "$reflog"; then
        keep "$path" "a commit in its reflog is not on $base — this branch is the last pointer to it"
        return 1
      fi
    elif [ -n "$reflog" ]; then
      # The reflog is here and says this ref has never held a commit of its own.
      # Nothing landed from this worktree, whatever GitHub reports for a branch
      # that happens to share its name.
      keep "$path" "no commits of its own — a fresh checkout is not finished work"
      return 1
    else
      # No reflog at all: expired, or switched off. Nothing local can speak for
      # this branch, so the only thing that retires it is a merged PR whose head
      # is this exact commit — a fast-forward merge, most likely. An ancestor
      # would not do: sitting on a commit the default branch already has is the
      # one thing every fresh worktree also does.
      pr="$(pr_info "$branch")"
      state="${pr%% *}"
      head_oid="${pr#* }"
      if [ "$state" != MERGED ] || [ "$head_oid" != "$head_now" ]; then
        keep "$path" "no commits of its own on record — its reflog is gone, so nothing can say work landed here"
        return 1
      fi
    fi
  else
    pr="$(pr_info "$branch")"
    state="${pr%% *}"
    head_oid="${pr#* }"
    case "$state" in
      # A squash merge rewrites the commits, so ancestry cannot see them and
      # the head branch is usually deleted with it. GitHub is the only witness,
      # and it speaks for this checkout only when the commit it merged is the
      # one standing here. An ancestor will not do: a branch that merged long
      # ago is an ancestor of every checkout made since.
      MERGED)
        if [ "$head_oid" != "$head_now" ]; then
          if git -C "$path" merge-base --is-ancestor "$head_oid" HEAD 2>/dev/null; then
            keep "$path" "commits made after its PR merged — they exist nowhere else"
          else
            keep "$path" "a PR by this branch's name merged, but not these commits"
          fi
          return 1
        fi
        ;;
      OPEN)
        keep "$path" "its PR is open, not merged — still being worked on"
        return 1
        ;;
      *)
        if [ -z "$(git -C "$path" branch -r --contains HEAD 2>/dev/null)" ]; then
          keep "$path" "commits that are on no remote — they exist nowhere else"
        else
          keep "$path" "work that has not landed on $base"
        fi
        return 1
        ;;
    esac
  fi

  if [ "$dry_run" = true ]; then
    printf 'would remove %s%s\n' "$path" "${branch:+ ($branch)}"
    return 0
  fi

  # Driven from the primary checkout, not from $path: this may be the worktree
  # the script is standing in, and git needs a directory that outlives it.
  # A refusal is one directory's problem, so report it and let the rest of the
  # run finish rather than aborting on set -e. The usual cause is a build tool's
  # ignored symlink, which git will not delete and --force is not worth.
  if ! git -C "$primary" worktree remove "$path" 2>/dev/null; then
    printf 'failed  %s: git would not remove it; delete the directory by hand\n' "$path" >&2
    return 1
  fi
  # -D, not -d: the work is provably landed by the check above, while -d refuses
  # a squash-merged branch — the usual shape here — because its commits are not
  # ancestors of anything left.
  if [ -n "$branch" ]; then
    git -C "$primary" branch -D "$branch" >/dev/null
  fi
  printf 'removed %s%s\n' "$path" "${branch:+ ($branch)}"
  return 0
}

removed=0
kept=0
path=""
branch=""
self_path=""
self_branch=""

# --porcelain emits a blank-line-separated record per worktree; the branch line
# is absent on a detached HEAD, which is why branch is reset per record.
while IFS= read -r line; do
  case "$line" in
    worktree\ *)
      path="${line#worktree }"
      branch=""
      continue
      ;;
    branch\ *)
      branch="${line#branch refs/heads/}"
      continue
      ;;
    "") ;;
    *) continue ;;
  esac

  [ -n "$path" ] || continue

  if [ "$path" = "$primary" ]; then
    keep "$path" "the main checkout"
    kept=$((kept + 1))
  elif [ "$path" = "$current" ]; then
    # Deferred to the end of the run: removing it invalidates the directory this
    # script and everything after it are standing in.
    self_path="$path"
    self_branch="$branch"
  elif consider "$path" "$branch" false; then
    removed=$((removed + 1))
  else
    kept=$((kept + 1))
  fi

  path=""
  branch=""
done < <(git worktree list --porcelain; printf '\n')

if [ -n "$self_path" ]; then
  if [ "$include_self" = false ]; then
    keep "$self_path" "you are working in it; --self retires it too"
    kept=$((kept + 1))
  else
    # Stand in the primary checkout first, so this script keeps a working
    # directory once its own goes away.
    cd "$primary"
    # A pane sitting in this worktree is the session that just asked for it to
    # be retired, so --self looks past the pane check here and nowhere else.
    if consider "$self_path" "$self_branch" true; then
      removed=$((removed + 1))
      [ "$dry_run" = true ] ||
        printf 'note    your shell is still in a directory that is gone; cd %s\n' "$primary"
    else
      kept=$((kept + 1))
    fi
  fi
fi

# The hook runs last, after every removal including --self, and only on a real
# run. A dry run removes no worktrees, so no path disappears and a reclamation
# tool would find nothing new by construction — while a careless hook would
# still delete. Naming it instead of running it makes that a guarantee rather
# than a convention a third-party hook is trusted to honour, and it costs the
# user nothing. The "none" line is deliberate: a dry run is where a dev in
# another repo finds out the convention exists.
hook_label=""
hook_cmd=()
if [ -n "$post_hook" ]; then
  hook_label="$post_hook"
  hook_cmd=(bash -c "$post_hook")
elif hook_path="$(find_hook)"; then
  hook_label="$hook_path"
  hook_cmd=("$hook_path")
fi

if [ -z "$hook_label" ]; then
  [ "$dry_run" = false ] ||
    printf 'hook    none (no executable tools/cleanup-hook.sh in %s)\n' "$primary"
elif [ -n "${CLEANUP_NO_HOOK:-}" ]; then
  printf 'hook    skipped, CLEANUP_NO_HOOK is set: %s\n' "$hook_label"
elif [ "$dry_run" = true ]; then
  printf 'would run %s\n' "$hook_label"
else
  run_hook "$hook_label" "${hook_cmd[@]}"
fi

printf '%d removed, %d kept\n' "$removed" "$kept"
