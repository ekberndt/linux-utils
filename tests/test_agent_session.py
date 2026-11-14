#!/usr/bin/env python3
"""Drive scripts/agent-session against a stub hc that keeps terminals in a JSON file."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "agent-session"

STUB_HC = r"""#!/usr/bin/env python3
import json, os, subprocess, sys
from pathlib import Path

state_path = Path(os.environ["HC_STUB_STATE"])
terminals = json.loads(state_path.read_text())
cmd, *args = sys.argv[1:]
with open(os.environ["HC_STUB_CALLS"], "a") as log:
    log.write(json.dumps([cmd, *args]) + "\n")

if cmd == "get":
    print(json.dumps(next(t for t in terminals if args[0] in (t["address"], t["name"]))))
elif cmd == "ls":
    print(json.dumps({"terminals": [{"address": t["address"]} for t in terminals]}))
elif cmd == "exec":
    # The caller's environment stands in for the core's, which hc exec uses.
    opts, argv = args[: args.index("--")], args[args.index("--") + 1 :]
    cwd = opts[opts.index("--cwd") + 1] if "--cwd" in opts else None
    env = os.environ | dict(v.split("=", 1) for k, v in zip(opts, opts[1:]) if k == "--env")
    sys.exit(subprocess.run(argv, cwd=cwd, env=env).returncode)
elif cmd == "run":
    opts, argv = args[: args.index("--")], args[args.index("--") + 1 :]
    labels = dict(v.split("=", 1) for k, v in zip(opts, opts[1:]) if k == "--label")
    name = opts[opts.index("--name") + 1]
    if any(t["name"] == name for t in terminals):
        sys.exit(f"hc: a live terminal is already named {name}")
    # Stand in for the app, which names the tab once it adopts the terminal.
    labels["where"] = f"{labels['herdr.space']} / {len(terminals)}"
    address = f"t{100 + len(terminals)}"
    terminals.append({"address": address, "name": name, "labels": labels, "foreground": {"argv": argv}})
    state_path.write_text(json.dumps(terminals))
    print(json.dumps({"address": address}))
"""

BRIEF = "Fix it.\nKeep \"quotes\", 'apostrophes' and $dollars as written.\n"


def terminal(address: str, name: str | None, labels: dict[str, str], argv: list[str]) -> dict:
    return {"address": address, "name": name, "labels": labels, "foreground": {"argv": argv}}


class AgentSessionTests(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        bin_dir = self.tmp / "bin"
        bin_dir.mkdir()
        (bin_dir / "hc").write_text(STUB_HC)
        (bin_dir / "hc").chmod(0o755)

        # The agent is reachable only through the login profile, as ~/.local/bin
        # is for the Herdr core.
        self.home = self.tmp / "home"
        self.agent = self.home / "agents" / "claude"
        self.agent.parent.mkdir(parents=True)
        self.agent.write_text("#!/bin/sh\n")
        self.agent.chmod(0o755)
        (self.home / ".profile").write_text(f'PATH="{self.agent.parent}:$PATH"\n')

        self.brief = self.tmp / "brief.md"
        self.brief.write_text(BRIEF)
        self.state = self.tmp / "terminals.json"
        self.calls = self.tmp / "calls.jsonl"
        self.calls.touch()

    def launch(
        self, terminals: list[dict], *extra: str, name: str = "helper", cwd: str = "/work", tmux_pane: str = ""
    ) -> subprocess.CompletedProcess[str]:
        self.state.write_text(json.dumps(terminals))
        env = {
            "PATH": f"{self.tmp / 'bin'}:/usr/bin:/bin",
            "HOME": str(self.home),
            "HC_TERMINAL_ID": terminals[0]["address"],
            "HC_STUB_STATE": str(self.state),
            "HC_STUB_CALLS": str(self.calls),
            "TMUX_PANE": tmux_pane,
        }
        argv = ["--name", name, "--cwd", cwd, "--brief", str(self.brief), *extra, "--", "claude", "--verbose"]
        return subprocess.run(["python3", str(SCRIPT), *argv], env=env, text=True, capture_output=True)

    def clone(self) -> Path:
        """A clone with an origin to branch from, and the worktree skill where agents find it."""
        git = ["git", "-c", "user.email=t@t", "-c", "user.name=t"]
        origin, seed, repo = self.tmp / "origin.git", self.tmp / "seed", self.tmp / "repo"
        for args in (
            ["init", "-q", "--bare", "-b", "main", origin],
            ["init", "-q", "-b", "main", seed],
            ["-C", seed, "commit", "-q", "--allow-empty", "-m", "init"],
            ["-C", seed, "push", "-q", origin, "main"],
            ["clone", "-q", origin, repo],
        ):
            subprocess.run([*git, *args], check=True)

        agents = self.home / ".agents"
        (agents / "scripts").mkdir(parents=True)
        (agents / "skills").symlink_to(ROOT / "skills")
        # Records the tmux pane whose window the skill would rename.
        self.renamed = self.tmp / "renamed"
        tmux = agents / "scripts" / "agent-tmux"
        tmux.write_text(f'#!/bin/sh\necho "${{TMUX_PANE:-none}}" >> "{self.renamed}"\n')
        tmux.chmod(0o755)
        return repo

    def calls_to(self, cmd: str) -> list[list[str]]:
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        return [call[1:] for call in calls if call[0] == cmd]

    def started_labels(self) -> list[dict[str, str]]:
        return [dict(v.split("=", 1) for k, v in zip(run, run[1:]) if k == "--label") for run in self.calls_to("run")]

    def test_space_from_own_labels(self) -> None:
        me = terminal("t1", None, {"herdr.space": "spA", "herdr.tab": "tbmine"}, ["claude"])
        res = self.launch([me])

        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(res.stdout, "t101 (helper) is in Herdr tab: spA / 1\n")
        self.assertEqual(self.started_labels()[0]["herdr.space"], "spA")
        (run,) = self.calls_to("run")
        # Independent of the caller: no notes into its context, no dying with it.
        self.assertIn("--no-parent", run)
        self.assertIn("--bg", run)
        self.assertEqual(run[run.index("--name") + 1 : run.index("--name") + 4], ["helper", "--cwd", "/work"])

    def test_space_from_the_tab_attached_to_it(self) -> None:
        for target in ("worker", "t19"):
            with self.subTest(attached_by=target):
                self.calls.write_text("")
                me = terminal("t19", "worker", {}, ["claude"])
                other = terminal("t1c", None, {"herdr.space": "spC"}, ["hc", "attach", "someone-else"])
                viewer = terminal("t1b", None, {"herdr.space": "spB"}, ["/home/u/.local/bin/hc", "attach", target])
                res = self.launch([me, other, viewer])

                self.assertEqual(res.returncode, 0, res.stderr)
                self.assertEqual(self.started_labels()[0]["herdr.space"], "spB")

    def test_no_space_fails_before_starting(self) -> None:
        me = terminal("t1", "loner", {}, ["claude"])
        res = self.launch([me, terminal("t2", None, {"herdr.space": "spA"}, ["bash"])])

        self.assertNotEqual(res.returncode, 0)
        self.assertIn("no Herdr space shows t1", res.stderr)
        self.assertEqual(self.calls_to("run"), [])

    def test_agent_runs_by_absolute_path_with_brief_last(self) -> None:
        res = self.launch([terminal("t1", None, {"herdr.space": "spA"}, ["claude"])])

        self.assertEqual(res.returncode, 0, res.stderr)
        (run,) = self.calls_to("run")
        self.assertEqual(run[run.index("--") + 1 :], [str(self.agent), "--verbose", BRIEF])

    def test_each_launch_opens_a_new_tab(self) -> None:
        me = terminal("t1", None, {"herdr.space": "spA", "herdr.tab": "tbmine"}, ["claude"])
        self.launch([me], name="first")
        self.launch(json.loads(self.state.read_text()), name="second")

        tabs = [labels["herdr.tab"] for labels in self.started_labels()]
        self.assertEqual(len(set(tabs + ["tbmine"])), 3)
        for tab in tabs:
            self.assertRegex(tab, r"^tb[0-9a-f]{32}$")

    def test_machine_resolves_and_runs_there(self) -> None:
        res = self.launch([terminal("t1", None, {"herdr.space": "spA"}, ["claude"])], "--on", "vps")

        self.assertEqual(res.returncode, 0, res.stderr)
        for cmd in ("exec", "run"):
            (call,) = self.calls_to(cmd)
            self.assertEqual(call[call.index("--on") + 1], "vps", cmd)


    def test_agent_starts_in_its_new_worktree(self) -> None:
        repo = self.clone()
        me = terminal("t1", None, {"herdr.space": "spA"}, ["claude"])
        res = self.launch([me], "--worktree", "feat/new-task", cwd=str(repo), tmux_pane="%9")

        self.assertEqual(res.returncode, 0, res.stderr)
        worktree = Path(f"{repo}__worktrees/feat-new-task")
        branch = subprocess.run(["git", "-C", worktree, "branch", "--show-current"], text=True, capture_output=True)
        self.assertEqual(branch.stdout, "feat/new-task\n")
        (run,) = self.calls_to("run")
        self.assertEqual(run[run.index("--cwd") + 1], str(worktree))
        self.assertIn(f"Created worktree: {worktree}\n", res.stdout)
        self.assertTrue(res.stdout.endswith("t101 (helper) is in Herdr tab: spA / 1\n"), res.stdout)
        # A tmux pane or Herdr tab the core inherited keeps its name and labels.
        self.assertEqual(self.renamed.read_text(), "none\n")
        self.assertEqual(self.calls_to("label"), [])

    def test_worktree_that_cannot_be_made_starts_nothing(self) -> None:
        repo = self.clone()
        me = terminal("t1", None, {"herdr.space": "spA"}, ["claude"])
        self.launch([me], "--worktree", "feat/taken", cwd=str(repo))
        res = self.launch(json.loads(self.state.read_text()), "--worktree", "feat/taken", cwd=str(repo), name="again")

        self.assertNotEqual(res.returncode, 0)
        self.assertIn("branch 'feat/taken' already exists locally", res.stderr)
        self.assertEqual([run[run.index("--name") + 1] for run in self.calls_to("run")], ["helper"])

    def test_session_that_cannot_start_leaves_no_worktree(self) -> None:
        repo = self.clone()
        me = terminal("t1", None, {"herdr.space": "spA"}, ["claude"])
        self.launch([me], "--worktree", "feat/first-task", cwd=str(repo))
        res = self.launch(json.loads(self.state.read_text()), "--worktree", "feat/second-task", cwd=str(repo))

        self.assertNotEqual(res.returncode, 0)
        self.assertIn("already named helper", res.stderr)
        self.assertFalse(Path(f"{repo}__worktrees/feat-second-task").exists())
        branches = subprocess.run(["git", "-C", repo, "branch", "--format=%(refname:short)"], text=True, capture_output=True)
        self.assertEqual(branches.stdout.split(), ["feat/first-task", "main"])

    def test_missing_agent_makes_no_worktree(self) -> None:
        repo = self.clone()
        self.agent.unlink()
        me = terminal("t1", None, {"herdr.space": "spA"}, ["claude"])
        res = self.launch([me], "--worktree", "feat/new-task", cwd=str(repo))

        self.assertEqual(res.returncode, 127)
        self.assertFalse(Path(f"{repo}__worktrees").exists())

    def test_worktree_is_made_on_the_machine_that_runs_the_agent(self) -> None:
        repo = self.clone()
        me = terminal("t1", None, {"herdr.space": "spA"}, ["claude"])
        res = self.launch([me], "--worktree", "feat/new-task", "--on", "vps", cwd=str(repo))

        self.assertEqual(res.returncode, 0, res.stderr)
        (made,) = [call for call in self.calls_to("exec") if "--cwd" in call]
        self.assertEqual(made[made.index("--on") + 1], "vps")
        self.assertEqual(made[made.index("--cwd") + 1], str(repo))
        self.assertEqual(made[made.index("--timeout") + 1], "600")


if __name__ == "__main__":
    unittest.main()
