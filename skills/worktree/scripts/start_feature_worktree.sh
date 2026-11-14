#!/usr/bin/env bash
set -euo pipefail
exec python3 - "$@" <<'PY'
import os
from pathlib import Path
import re
import subprocess
import sys

USAGE = """\
Usage: start_feature_worktree.sh <type/slug> [--path DIR]

Creates a new git worktree and branch from the freshly fetched default branch.

Branch types: feat, fix, docs, refactor, perf, test, build, ci, chore"""

VALID_TYPES = {"feat", "fix", "docs", "refactor", "perf", "test", "build", "ci", "chore"}


def die(msg: str) -> "NoReturn":
    print(f"Error: {msg}", file=sys.stderr)
    sys.exit(1)


def git(*args: str, cwd: str | None = None) -> subprocess.CompletedProcess[str]:
    cmd = ["git", *args] if cwd is None else ["git", "-C", cwd, *args]
    return subprocess.run(cmd, text=True, capture_output=True, check=False)


def parse_args(argv: list[str]) -> tuple[str, str]:
    branch = ""
    worktree_dir = ""
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in ("-h", "--help"):
            print(USAGE)
            sys.exit(0)
        if arg == "--path":
            if i + 1 >= len(argv):
                die("--path requires a directory")
            worktree_dir = argv[i + 1]
            i += 2
            continue
        if arg.startswith("--"):
            die(f"unknown option: {arg}")
        if branch:
            die(f"unexpected extra argument: {arg}")
        branch = arg
        i += 1

    if not branch:
        print(USAGE, file=sys.stderr)
        die("branch name is required")
    return branch, worktree_dir


def resolve_base_branch() -> str:
    symref = git("symbolic-ref", "--short", "refs/remotes/origin/HEAD").stdout.strip()
    if symref.startswith("origin/"):
        base = symref.removeprefix("origin/")
        if base:
            return base
    ls_remote = git("ls-remote", "--symref", "origin", "HEAD").stdout
    for line in ls_remote.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] == "ref:" and parts[1].startswith("refs/heads/"):
            return parts[1].removeprefix("refs/heads/")
    return "main"


def main() -> None:
    branch, worktree_dir = parse_args(sys.argv[1:])

    prefix, sep, slug = branch.partition("/")
    if not sep or prefix not in VALID_TYPES:
        die(
            "branch must use <type>/<slug> with type feat|fix|docs|refactor|perf|test|build|ci|chore"
        )
    if not slug:
        die("branch slug cannot be empty")
    if re.search(r"[^a-z0-9-]", slug):
        die("branch slug must contain only lowercase letters, digits, and hyphens")
    if slug.startswith("-") or slug.endswith("-"):
        die("branch slug cannot start or end with a hyphen")

    if git("rev-parse", "--is-inside-work-tree").returncode != 0:
        die("not inside a git repository")

    # Resolve primary worktree so creating a worktree from inside a secondary
    # worktree still names the sibling directory after the primary repo.
    porcelain = git("worktree", "list", "--porcelain").stdout
    root = ""
    for line in porcelain.splitlines():
        if line.startswith("worktree "):
            root = line.removeprefix("worktree ")
            break
    if not root:
        root = git("rev-parse", "--show-toplevel").stdout.strip()
    repo = Path(root).name

    previous_branch = git("branch", "--show-current").stdout.strip()
    previous_sha = git("rev-parse", "--short", "HEAD").stdout.strip()

    base_branch = resolve_base_branch()
    base_ref = f"refs/remotes/origin/{base_branch}"

    if git("show-ref", "--verify", "--quiet", f"refs/heads/{branch}").returncode == 0:
        die(f"branch '{branch}' already exists locally")

    if git("remote", "get-url", "origin").returncode != 0:
        die("origin remote is required to fetch the base branch before creating a worktree")

    remote_check = git("ls-remote", "--exit-code", "--heads", "origin", branch)
    if remote_check.returncode == 0:
        die(f"branch '{branch}' already exists on origin")
    if remote_check.returncode != 2:
        die(f"could not check origin for existing branch '{branch}'")

    if not worktree_dir:
        worktree_dir = str(Path(root).parent / f"{repo}-{branch.replace('/', '-')}")
    elif not os.path.isabs(worktree_dir):
        worktree_dir = os.path.abspath(worktree_dir)

    if os.path.exists(worktree_dir) or os.path.islink(worktree_dir):
        die(f"worktree path already exists: {worktree_dir}")
    parent_dir = os.path.dirname(worktree_dir)
    if not os.path.isdir(parent_dir):
        die(f"parent directory does not exist: {parent_dir}")

    fetch = git("fetch", "origin", f"+refs/heads/{base_branch}:{base_ref}")
    if fetch.returncode != 0:
        sys.stderr.write(fetch.stderr)
        sys.exit(fetch.returncode)

    base_sha_res = git("rev-parse", "--short", f"{base_ref}^{{commit}}")
    if base_sha_res.returncode != 0:
        die(f"base start point 'origin/{base_branch}' does not resolve to a commit")
    base_sha = base_sha_res.stdout.strip()

    add_res = git("worktree", "add", "--no-track", worktree_dir, "-b", branch, base_ref)
    if add_res.returncode != 0:
        sys.stderr.write(add_res.stderr)
        sys.exit(add_res.returncode)

    new_sha = git("rev-parse", "--short", "HEAD", cwd=worktree_dir).stdout.strip()

    print(f"Created worktree: {worktree_dir}")
    print(f"Created branch: {branch}")
    print(f"Based on: origin/{base_branch} ({base_sha})")
    print(f"Worktree HEAD: {new_sha}")

    agent_tmux = Path.home() / ".agents" / "scripts" / "agent-tmux"
    if agent_tmux.is_file() and os.access(agent_tmux, os.X_OK):
        subprocess.run([str(agent_tmux), "worktree", worktree_dir], check=False)

    if previous_branch:
        suffix = f" ({previous_sha})" if previous_sha else ""
        print(f"Previous branch preserved: {previous_branch}{suffix}")


if __name__ == "__main__":
    main()
PY
