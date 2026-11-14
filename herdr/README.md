# Herdr agent tree

The `agent-tree` mod draws the Herdr app's agents list as a file tree: each
computer, the repos its sessions work in, then the sessions, with the
sub-agents each one started beneath it.

```text
[monitor] macbook                                          v
└─ [folder] herdr-mods                                     v
   └─ [claude] Tidy mods                             12m   o
[server] volskaya                                          v
├─ [folder] linux-utils                                    v
│  ├─ [claude] Session skill                   [pin] 3m  Needs you
│  └─ [claude] Herdr installer and agents tree   v  <1m   ⟳
│     └─ [claude] review                                   o
└─ [folder] mach                                           v
   └─ [codex] Explain project tracking | mach        40m   ⟳
```

`[...]` are icons (each agent's is the one Herdr's own list shows), `v` the
fold chevron, `o` the idle ring, `⟳` the working spinner.

- **Computer**: the machine name from the agent's address (`volskaya/t7`), or
  this computer's own name from `hc server status`. Session rows never repeat it.
- **Repo**: `git rev-parse --git-common-dir` in the session's folder, run on its
  machine, so worktrees sit under the repo they belong to. A folder outside any
  repo is its own group (`~`, `/srv/data`). Repos sort by name.
- **Session**: the agent's icon, the tab's name if someone named it, else the
  agent's own title, else where it is (`scalar / 3`); time in its current
  state, a pin when pinned, and Herdr's status mark (spinner, Needs you, done
  dot, idle ring). Hover pins or unpins it; a click focuses it. Pinned sessions
  come first in their repo.

Every row with children folds; a folded row shows how many agents it hides and
the most urgent one's color. On the narrow sidebar rail the list becomes one
numbered status per session, and `»` widens it again.

## Using it

`bash installers/installer.sh config` links `mods/agent-tree/` and
`layouts/agent-tree.json` into `~/.config/herdr-app`, the app's home on macOS
and Linux alike. Pick **agent-tree** in Settings > Look, or press
`ctrl-shift-l` to cycle layouts; Herdr's own layouts stay as shipped.

Herdr loads the mod from the repo through the link and rechecks mod folders
about every 10 seconds, so a pull or an edit shows up without a restart. It
writes its editor typings (`gpui-kit.d.ts`, `jsconfig.json`) into the mod
folder; git ignores them. Clicks such as sizes and theme picks stay in
`~/.config/herdr-app/layouts/.state/`, but a structural edit to the layout
(`layout.set`) is written through the link into the repo's file.

The layout is Herdr 0.1.15's `main` layout with this mod in place of the
`agents` block, as `layout.clone` would make it. Herdr does not update clones,
so a later change to `main` reaches it only when it is copied again.

Herdr documents mods and layouts in `~/.config/herdr-app/AGENTS.md`, rewritten
on every start ([source](https://github.com/herdrdev/herdr-app/blob/main/defaults/AGENTS.md)).
Check an edit with `herdr-app check ~/.config/herdr-app/mods/agent-tree`; the
tests render the mod under node (`tests/test_herdr_agent_tree.sh`).
