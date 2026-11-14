#!/usr/bin/env bash
# cleanup_worktrees.sh: remove the worktrees an agent has finished with, and the
# branches that only existed to hold them.
#
# Usage: cleanup_worktrees.sh [--dry-run] [--self] [--post-hook CMD]
set -euo pipefail
exec python3 - "$@" <<'PY'
import contextlib
import json
import os
import re
import shutil
import subprocess
import sys

USAGE = """\
cleanup_worktrees.sh: remove the worktrees an agent has finished with, and the
branches that only existed to hold them.

Usage: cleanup_worktrees.sh [--dry-run] [--self] [--post-hook CMD]"""


def die(msg: str) -> "NoReturn":
    print(f"Error: {msg}", file=sys.stderr)
    sys.exit(1)


def git(cwd: str | None, *args: str) -> subprocess.CompletedProcess[str]:
    cmd = ["git", *args] if cwd is None else ["git", "-C", cwd, *args]
    return subprocess.run(cmd, text=True, capture_output=True, check=False)


def keep(path: str, reason: str) -> None:
    print(f"keep    {path}: {reason}")


def parse_args(argv: list[str]) -> tuple[bool, bool, str]:
    dry_run = False
    include_self = False
    post_hook = ""
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--dry-run":
            dry_run = True
        elif arg == "--self":
            include_self = True
        elif arg == "--post-hook":
            i += 1
            if i >= len(argv):
                die("--post-hook needs a command")
            post_hook = argv[i]
        elif arg in ("-h", "--help"):
            print(USAGE)
            sys.exit(0)
        else:
            die(f"unknown option: {arg}")
        i += 1
    return dry_run, include_self, post_hook


def parse_worktrees(porcelain: str) -> list[tuple[str, str, bool]]:
    worktrees: list[tuple[str, str, bool]] = []
    path = ""
    branch = ""
    bare = False
    for line in (porcelain + "\n").splitlines():
        if line.startswith("worktree "):
            path = line[len("worktree ") :]
            branch = ""
            bare = False
        elif line.startswith("branch refs/heads/"):
            branch = line[len("branch refs/heads/") :]
        elif line == "bare":
            bare = True
        elif line == "" and path:
            worktrees.append((path, branch, bare))
            path = ""
            branch = ""
            bare = False
    return worktrees


def tmux_folders() -> list[tuple[set[str], str]]:
    """Each tmux pane's folder and each window's agent checkout, with the pids
    of the panes' programs there."""
    if not shutil.which("tmux"):
        return []
    fmt = "#{window_id}\t#{pane_pid}\t#{pane_current_path}\t#{@agent_dir}"
    res = subprocess.run(["tmux", "list-panes", "-a", "-F", fmt], text=True, capture_output=True, check=False)
    panes = [line.split("\t") for line in res.stdout.splitlines()]
    # @agent_dir is set on the window, so it is every one of its panes'.
    window_pids: dict[str, set[str]] = {}
    for window, pid, _, _ in panes:
        window_pids.setdefault(window, set()).add(pid)
    return [({pid}, path) for _, pid, path, _ in panes if path] + [
        (window_pids[window], agent_dir) for window, _, _, agent_dir in panes if agent_dir
    ]


def herdr_folders() -> list[tuple[set[str], str]]:
    """Each live Herdr terminal's folders on this machine, with the pid of its
    program: where that program runs (`foreground.cwd`; the top-level `cwd` is
    only where it started), and the checkout the worktree helper labeled it
    with, since an agent that makes its worktree after starting stays put."""
    # Agent shells inherit the Herdr core's PATH, which lacks ~/.local/bin,
    # where hc links itself.
    hc = shutil.which("hc") or shutil.which("hc", path=os.path.expanduser("~/.local/bin"))
    if not hc:
        return []
    # Fails when no core runs here; then no terminal is anywhere.
    live = subprocess.run([hc, "ls", "--json"], text=True, capture_output=True, check=False)
    if live.returncode:
        return []
    folders: list[tuple[set[str], str]] = []
    for summary in json.loads(live.stdout)["terminals"]:
        get = [hc, "get", summary["address"], "--json"]
        # A terminal that ended since the listing has no foreground, or is gone.
        terminal = json.loads(subprocess.run(get, text=True, capture_output=True, check=False).stdout or "{}")
        if foreground := terminal.get("foreground"):
            paths = (foreground.get("cwd"), terminal["labels"].get("agent_dir"))
            folders.extend(({str(terminal["pid"])}, path) for path in paths if path)
    return folders


def own_pids() -> set[str]:
    """This process and its ancestors, among them the program of the terminal running it."""
    pids: set[str] = set()
    pid = str(os.getpid())
    while pid not in ("", "0"):
        pids.add(pid)
        pid = subprocess.run(["ps", "-o", "ppid=", "-p", pid], text=True, capture_output=True, check=False).stdout.strip()
    return pids


def in_use(path: str, busy_paths: list[str]) -> bool:
    prefix = path + "/"
    return any(b == path or b.startswith(prefix) for b in busy_paths)


def stashed(path: str, branch: str) -> bool:
    head = git(path, "rev-parse", "HEAD").stdout.strip()
    stash_out = git(path, "stash", "list", "--format=%H %gs").stdout
    for entry in stash_out.splitlines():
        if not entry:
            continue
        oid, _, subject = entry.partition(" ")
        if branch and subject.startswith((f"WIP on {branch}:", f"On {branch}:")):
            return True
        if not branch and subject.startswith(("WIP on (no branch):", "On (no branch):")):
            parent = git(path, "rev-parse", "--verify", "--quiet", f"{oid}^1").stdout.strip()
            if head and parent == head:
                return True
    return False


def committed_here(reflog: str) -> bool:
    # Whitelist of reflog actions that prove this branch held commits of its own.
    # `rebase` is excluded because rebasing a fresh branch onto a newer base
    # writes a reflog entry without adding any branch-owned commits.
    prefixes = ("commit:", "commit (", "am:", "cherry-pick:", "revert:")
    for line in reflog.splitlines():
        _, _, subject = line.partition(" ")
        if subject.startswith(prefixes) or ": Merge made by " in subject:
            return True
    return False


def reflog_landed(path: str, reflog: str, base_ref: str) -> bool:
    seen: set[str] = set()
    for line in reflog.splitlines():
        parts = line.split()
        if not parts:
            continue
        oid = parts[0]
        if oid in seen:
            continue
        seen.add(oid)
        if git(path, "merge-base", "--is-ancestor", oid, base_ref).returncode != 0:
            return False
    return True


def has_precious_ignored(path: str) -> str:
    for name in ("data", "outputs"):
        candidate = os.path.join(path, name)
        if not os.path.islink(candidate) and os.path.isdir(candidate):
            try:
                if os.listdir(candidate):
                    return name
            except OSError:
                return name
    return ""


class PrTracker:
    def __init__(self, primary: str, base_ref: str) -> None:
        self.primary = primary
        self.base_ref = base_ref
        self._loaded = False
        self.by_head: dict[str, list[dict]] = {}
        self.open_oids: set[str] = set()
        self.merged_oids: set[str] = set()
        self.main_subjects: set[str] = set()
        self._pr_commits: dict[int, tuple[set[str], set[str]]] = {}

    def _ensure_loaded(self) -> None:
        if self._loaded:
            return
        self._loaded = True
        log_out = git(self.primary, "log", self.base_ref, "--format=%s").stdout
        for line in log_out.splitlines():
            m = re.match(r"^(.+?)\s*\(#\d+\)\s*$", line)
            if m:
                s = m.group(1).strip()
                if len(s) >= 15:
                    self.main_subjects.add(s)

        if not shutil.which("gh"):
            return
        res = subprocess.run(
            [
                "gh",
                "pr",
                "list",
                "--state",
                "all",
                "--limit",
                "1000",
                "--json",
                "number,title,state,headRefName,headRefOid",
            ],
            cwd=self.primary,
            text=True,
            capture_output=True,
            check=False,
        )
        if res.returncode != 0 or not res.stdout.strip():
            return
        try:
            prs = json.loads(res.stdout)
        except ValueError:
            return
        for pr in prs:
            head_name = pr.get("headRefName") or ""
            head_oid = pr.get("headRefOid") or ""
            state = pr.get("state") or ""
            title = (pr.get("title") or "").strip()
            if head_name:
                self.by_head.setdefault(head_name, []).append(pr)
            if state == "OPEN" and head_oid:
                self.open_oids.add(head_oid)
            elif state == "MERGED":
                if head_oid:
                    self.merged_oids.add(head_oid)
                if len(title) >= 15:
                    self.main_subjects.add(title)

    def _prs_for_branch(self, branch: str) -> list[dict]:
        self._ensure_loaded()
        if not branch or not shutil.which("gh"):
            return []
        if branch in self.by_head:
            return self.by_head[branch]
        res = subprocess.run(
            [
                "gh",
                "pr",
                "list",
                "--head",
                branch,
                "--state",
                "all",
                "--limit",
                "10",
                "--json",
                "number,title,state,headRefName,headRefOid",
            ],
            cwd=self.primary,
            text=True,
            capture_output=True,
            check=False,
        )
        if res.returncode != 0 or not res.stdout.strip():
            self.by_head[branch] = []
            return []
        try:
            prs = json.loads(res.stdout)
        except ValueError:
            prs = []
        self.by_head[branch] = prs
        for pr in prs:
            head_oid = pr.get("headRefOid") or ""
            state = pr.get("state") or ""
            title = (pr.get("title") or "").strip()
            if state == "OPEN" and head_oid:
                self.open_oids.add(head_oid)
            elif state == "MERGED":
                if head_oid:
                    self.merged_oids.add(head_oid)
                if len(title) >= 15:
                    self.main_subjects.add(title)
        return prs

    def _commits_for_pr(self, number: int) -> tuple[set[str], set[str]]:
        if number in self._pr_commits:
            return self._pr_commits[number]
        oids: set[str] = set()
        headlines: set[str] = set()
        if shutil.which("gh"):
            res = subprocess.run(
                ["gh", "pr", "view", str(number), "--json", "commits"],
                cwd=self.primary,
                text=True,
                capture_output=True,
                check=False,
            )
            if res.returncode == 0 and res.stdout.strip():
                try:
                    data = json.loads(res.stdout)
                    for c in data.get("commits", []):
                        if oid := c.get("oid"):
                            oids.add(oid)
                            self.merged_oids.add(oid)
                        if h := (c.get("messageHeadline") or "").strip():
                            if len(h) >= 15:
                                headlines.add(h)
                                self.main_subjects.add(h)
                except ValueError:
                    pass
        self._pr_commits[number] = (oids, headlines)
        return oids, headlines

    def candidate_branches(self, path: str, branch: str) -> list[str]:
        if not branch:
            return []
        names = [branch, f"{branch}-2"]
        merge_ref = git(path, "config", f"branch.{branch}.merge").stdout.strip()
        if merge_ref.startswith("refs/heads/"):
            up = merge_ref.removeprefix("refs/heads/")
            if up and up not in names and f"refs/remotes/origin/{up}" != self.base_ref:
                names.append(up)
        slug = re.sub(r"^(feat|fix|perf|refactor|chore|docs|test|ci)/", "", branch)
        if slug != branch:
            pr_branch = f"pr/{slug}"
            if pr_branch not in names:
                names.append(pr_branch)
        return names

    def evaluate(self, path: str, branch: str, head_now: str, ahead: int) -> tuple[str, str]:
        """Return ('MERGED' | 'OPEN' | 'NONE', reason_if_not_merged)."""
        self._ensure_loaded()
        candidates = self.candidate_branches(path, branch)
        prs: list[dict] = []
        seen_nums: set[int] = set()
        for b in candidates:
            for pr in self._prs_for_branch(b):
                num = pr.get("number", 0)
                if num not in seen_nums:
                    seen_nums.add(num)
                    prs.append(pr)

        if head_now in self.open_oids or any(p.get("state") == "OPEN" for p in prs):
            return "OPEN", "its PR is open, not merged — still being worked on"

        if head_now in self.merged_oids:
            return "MERGED", ""

        merged_prs = [p for p in prs if p.get("state") == "MERGED"]
        for pr in merged_prs:
            if pr.get("headRefOid") == head_now:
                return "MERGED", ""
            oids, _ = self._commits_for_pr(pr["number"])
            if head_now in oids:
                return "MERGED", ""

        if ahead > 0 and self.merged_oids:
            log_out = git(path, "log", "--no-merges", f"{self.base_ref}..HEAD", "--format=%H\t%s").stdout.strip()
            commits = [line.split("\t", 1) for line in log_out.splitlines() if "\t" in line]
            if commits:
                def commit_landed(oid: str, subj: str) -> bool:
                    s = subj.strip()
                    return oid in self.merged_oids or (len(s) >= 15 and s in self.main_subjects)

                if all(commit_landed(oid, subj) for oid, subj in commits):
                    return "MERGED", ""

        if merged_prs:
            for pr in merged_prs:
                head_oid = pr.get("headRefOid") or ""
                if head_oid and git(path, "merge-base", "--is-ancestor", head_oid, "HEAD").returncode == 0:
                    return "NONE", "commits made after its PR merged — they exist nowhere else"
            return "NONE", "a PR by this branch's name merged, but not these commits"

        return "NONE", ""


def find_hook(primary: str, primary_bare: bool) -> str:
    if primary_bare and not os.path.isdir(os.path.join(primary, ".git")):
        return ""
    for rel in ("tools/cleanup-hook.sh", ".cleanup-hook"):
        candidate = os.path.join(primary, rel)
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return ""


def run_hook(label: str, cmd: list[str], primary: str, removed: int) -> None:
    print(f"hook    {label}", flush=True)
    env = os.environ.copy()
    env["CLEANUP_PRIMARY"] = primary
    env["CLEANUP_REMOVED"] = str(removed)
    try:
        res = subprocess.run(cmd, cwd=primary, env=env, timeout=1800, check=False)
        rc = res.returncode
    except subprocess.TimeoutExpired:
        rc = 124
    if rc != 0:
        print(
            f"failed  {label}: exited {rc}; the cleanup itself succeeded",
            file=sys.stderr,
        )


def main() -> None:
    dry_run, include_self, post_hook = parse_args(sys.argv[1:])

    if git(None, "rev-parse", "--git-dir").returncode != 0:
        die("not inside a git repository")

    worktrees = parse_worktrees(git(None, "worktree", "list", "--porcelain").stdout)
    if not worktrees:
        die("could not resolve the main worktree")
    primary, _, primary_bare = worktrees[0]
    current = git(None, "rev-parse", "--show-toplevel").stdout.strip()

    git(None, "fetch", "--quiet", "--prune", "origin")

    symref = git(None, "symbolic-ref", "--short", "refs/remotes/origin/HEAD").stdout.strip()
    base = symref.removeprefix("origin/") if symref else "main"
    base_ref = f"refs/remotes/origin/{base}"
    if git(None, "rev-parse", "--verify", "--quiet", base_ref).returncode != 0:
        die(f"no {base_ref} to compare against; fetch origin first")

    log_updates = git(None, "config", "--bool", "core.logAllRefUpdates").stdout.strip()
    if log_updates == "false":
        print(
            "note    reflogs are off (core.logAllRefUpdates=false); only a merged PR can retire a worktree",
            file=sys.stderr,
        )

    folders = tmux_folders() + herdr_folders()
    busy_paths = [path for _, path in folders]
    # --self retires the worktree the caller's own terminal is in, not one
    # another terminal is in: a shell opened beside an agent starts where the
    # agent is.
    mine = own_pids()
    others_paths = [path for pids, path in folders if not pids & mine]
    prs = PrTracker(primary, base_ref)

    def consider(path: str, branch: str, busy_paths: list[str]) -> bool:
        if git(path, "status", "--porcelain").stdout.strip():
            keep(path, "uncommitted changes")
            return False
        if precious := has_precious_ignored(path):
            keep(path, f"non-empty {precious}/ directory — move or delete it first")
            return False
        if stashed(path, branch):
            keep(path, "a stash is parked on it — git status does not show one")
            return False
        if in_use(path, busy_paths):
            keep(path, "a tmux pane or Herdr terminal is still in it")
            return False

        reflog_ref = f"refs/heads/{branch}" if branch else "HEAD"
        reflog = git(path, "reflog", "show", "--format=%H %gs", reflog_ref).stdout.strip()
        head_now = git(path, "rev-parse", "HEAD").stdout.strip()
        ahead_str = git(path, "rev-list", "--count", f"{base_ref}..HEAD").stdout.strip()
        ahead = int(ahead_str) if ahead_str.isdigit() else 0

        if ahead == 0:
            if committed_here(reflog):
                if not reflog_landed(path, reflog, base_ref):
                    keep(
                        path,
                        f"a commit in its reflog is not on {base} — this branch is the last pointer to it",
                    )
                    return False
            elif reflog:
                keep(path, "no commits of its own — a fresh checkout is not finished work")
                return False
            else:
                state, _ = prs.evaluate(path, branch, head_now, ahead=0)
                if state != "MERGED":
                    keep(
                        path,
                        "no commits of its own on record — its reflog is gone, so nothing can say work landed here",
                    )
                    return False
        else:
            state, reason = prs.evaluate(path, branch, head_now, ahead=ahead)
            if state == "MERGED":
                pass
            elif state == "OPEN":
                keep(path, reason)
                return False
            elif reason:
                keep(path, reason)
                return False
            else:
                if not git(path, "branch", "-r", "--contains", "HEAD").stdout.strip():
                    keep(path, "commits that are on no remote — they exist nowhere else")
                else:
                    keep(path, f"work that has not landed on {base}")
                return False

        suffix = f" ({branch})" if branch else ""
        if dry_run:
            print(f"would remove {path}{suffix}")
            return True

        if git(primary, "worktree", "remove", path).returncode != 0:
            print(
                f"failed  {path}: git would not remove it; delete the directory by hand",
                file=sys.stderr,
            )
            return False
        if branch:
            git(primary, "branch", "-D", branch)
        print(f"removed {path}{suffix}")
        return True

    gone: list[str] = []
    kept = 0
    self_entry: tuple[str, str] | None = None

    for path, branch, _ in worktrees:
        if path == primary:
            keep(path, "the main checkout")
            kept += 1
        elif path == current:
            self_entry = (path, branch)
        elif consider(path, branch, busy_paths):
            gone.append(path)
        else:
            kept += 1

    if self_entry is not None:
        self_path, self_branch = self_entry
        if not include_self:
            keep(self_path, "you are working in it; --self retires it too")
            kept += 1
        else:
            os.chdir(primary)
            if consider(self_path, self_branch, others_paths):
                gone.append(self_path)
                if not dry_run:
                    print(
                        f"note    your shell is still in a directory that is gone; cd {primary}"
                    )
            else:
                kept += 1

    # The worktree skill puts new worktrees in one folder beside the primary
    # checkout; it goes with its last worktree so a finished repo leaves nothing
    # behind.
    container = f"{primary}__worktrees"
    if os.path.isdir(container) and all(
        os.path.join(container, name) in gone for name in os.listdir(container)
    ):
        if dry_run:
            print(f"would remove {container}")
        else:
            # rmdir refuses the folder if another agent just started a worktree in it.
            with contextlib.suppress(OSError):
                os.rmdir(container)
                print(f"removed {container}")

    hook_label = ""
    hook_cmd: list[str] = []
    if post_hook:
        hook_label = post_hook
        hook_cmd = ["bash", "-c", post_hook]
    elif hook_path := find_hook(primary, primary_bare):
        hook_label = hook_path
        hook_cmd = [hook_path]

    if not hook_label:
        if dry_run:
            print(f"hook    none (no executable tools/cleanup-hook.sh in {primary})")
    elif os.environ.get("CLEANUP_NO_HOOK"):
        print(f"hook    skipped, CLEANUP_NO_HOOK is set: {hook_label}")
    elif dry_run:
        print(f"would run {hook_label}")
    else:
        run_hook(hook_label, hook_cmd, primary, len(gone))

    print(f"{len(gone)} removed, {kept} kept")


if __name__ == "__main__":
    main()
PY
