# Herdr agent tree layout

`herdr/layouts/agent-tree.json` and the mods under `herdr/mods/` replace
Herdr's default `main` chrome with a compact layout whose sidebar is dedicated
entirely to `computer > repo/folder > session` (no `Spaces` panel and no
brand banner):

```text
Sessions                                  [search] [+] [sidebar]
[monitor] macbook                                            v
└─ [folder] herdr-mods                                       v
   └─ [claude] Tidy mods                               12m   o
[server] volskaya                                            v
├─ [folder] linux-utils                                      v
│  ├─ [claude] Session skill                      [pin] 3m  Needs you
│  └─ [claude] Herdr installer and agents tree       v <1m   ⟳
│     └─ [claude] review                                     o
└─ [folder] mach                                             v
   └─ [codex] Explain project tracking | mach          40m   ⟳
```

`[...]` are icons (each agent's is from Herdr's program table), `v` the fold
chevron, `o` the idle ring, `⟳` the working spinner.

- **Computer**: the machine name from the agent's address (`volskaya/t7`), or
  this computer's own name from `hc server status`. Connected computers appear
  even before their first terminal.
- **Repo / folder**: `git rev-parse --git-common-dir` in the session's folder,
  run on its machine, so git worktrees group under the repo they belong to. A
  folder outside any repo is its own group (`~`, `/srv/data`). Sorted by name.
- **Session**: plain terminal tabs appear alongside agents. For an agent: its icon, the tab's name if someone named it, else the
  agent's live title, else where it is (`scalar / 3`); time in its current
  state, a pin when pinned, and Herdr's status mark (spinner, `Needs you`, done
  dot, idle ring). Hover pins or unpins it; a click focuses its pane. Pinned
  sessions sort first in their repo; sub-agents nest beneath their parent.

Every row with children folds; a folded row shows how many sessions it hides and
the most urgent one's color. On the narrow sidebar rail the list becomes one
numbered status per session, and `»` widens it again.

## Start work from the sidebar

- **Add machine** in the footer opens Herdr's SSH host picker.
- **Right-click a computer or repo** (or click an empty computer's **+**)
  to choose **New terminal tab** or an installed agent on that computer.
  The sidebar header's **+** uses the active space instead.
- **Open repo or folder…** opens a separate space with a terminal. Enter a
  path on the selected computer, or **Browse…** on the local computer. **Open** uses
  an existing directory, **Create folder** makes a directory, and **New Git
  repo** initializes one with Git. Relative paths start in the folder shown;
  `~/` means that computer's home. No Spaces panel is needed.
- Click a terminal or agent in the tree to switch back to it.

## Mods

- **`agent-tree`** (`herdr/mods/agent-tree/`): full-height sidebar tree with
  `Search`, `+`, and sidebar-collapse controls in its top bar. Right-clicking a
  computer or repo/folder row opens `session-menu` to start a new terminal tab
  or coding agent session directly on that machine or in that repo's primary
  checkout; right-clicking a session opens its tab menu.
- **`session-menu`** (`herdr/mods/session-menu/`): popup menu for starting a new
  terminal tab or installed coding agent in the targeted repo, folder, or
  computer (replacing Herdr's `new-menu` so no built-in Herdr worktree actions
  are shown; agents create worktrees through the `worktree` skill).
- **`open-folder`**: path dialog for opening or creating a project on the
  selected computer.
- **`tab-bar`**, **`pane-header`**, **`sidebar-footer`**, **`status-bar`**:
  compact adaptations of Herdr's top tab bar (`+` opens `session-menu`, plus
  per-space `Files` / `Changes` panel toggles), framed pane header, sidebar
  footer, and bottom status bar. Herdr's shipped `files`, `changes`, `menu`, and
  `picker` mods are used as-is.

## Installing and switching

`just install` and `just config` (via `installers/config/herdr.sh`) symlink
every mod in `herdr/mods/` and layout file in `herdr/layouts/` into
`~/.config/herdr-app`, prune links to mods or layouts removed from the repo,
validate each mod with `herdr-app check` when `herdr-app` is installed, and
switch Herdr to `agent-tree` whenever it is still on the shipped `main` layout
(live via `herdr-app do layout.switch` when open, or in `shared.json` when
closed). Explicit picks such as `win98` or `terminals` stay untouched.

If a block says it did not load after a pull, run `bash installers/config/herdr.sh`
from the checkout: the linked layout updates immediately, but newly added mod
folders need their own links.

Switch manually at any time in **Settings > Look**, with `ctrl-shift-l`, or via:

```bash
herdr-app do layout.switch '{"name":"agent-tree"}'
```

## Developing and verifying

Herdr loads linked mods directly from the checkout and hot-reloads edits. It
writes `gpui-kit.d.ts` and `jsconfig.json` into loaded mod folders (gitignored)
and documents the host API in `~/.config/herdr-app/AGENTS.md`, rewritten on
every start ([source](https://github.com/herdrdev/herdr-app/blob/main/defaults/AGENTS.md)).

- Node render tests: `bash tests/test_herdr_agent_tree.sh`
- Installer and activation tests: `bash tests/test_herdr_install.sh`
- Host check: `herdr-app check ~/.config/herdr-app/mods/<mod>`
