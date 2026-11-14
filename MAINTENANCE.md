# Maintenance

What in this repo drifts while nobody touches it, and how to bring it back.
Run a pass with the `maintenance` skill, which also defines this file's format.
A change that adds something that drifts adds its item here in the same PR; a
change that removes it deletes the item. `tests/test_maintenance.sh` fails when
an item names a repo path that no longer exists.

Installers that only download and install can be verified as root in a
throwaway container, the path the `datacenter` profile takes:

```bash
docker run --rm -v "$PWD:/repo:ro" ubuntu:24.04 bash -c 'apt-get update -qq &&
  apt-get install -y -qq curl ca-certificates git >/dev/null &&
  bash /repo/installers/installer.sh <component>...'
```

## Every pass

### pre-commit hooks

- **Where:** hook `rev`s in `.pre-commit-config.yaml`.
- **Check:** `~/.local/bin/uvx pre-commit autoupdate`; its diff is the update.
- **Update:** fix what a newer linter flags rather than disabling the rule.
- **Verify:** `~/.local/bin/uvx pre-commit run --all-files`.

### GitHub Actions

- **Where:** `uses:` lines in `.github/workflows/`.
- **Check:** each action's latest major
  (`gh api repos/<owner>/<action>/releases/latest --jq .tag_name`).
- **Update:** read the release notes for removed inputs before bumping `@vN`.
- **Verify:** both workflows pass on the PR.

### Docs that restate code

The code is the truth; fix the doc.

| Doc | Restates |
| --- | --- |
| `README.md` profile table | `installers/profiles/`, `MACOS_COMPONENTS` in `macos/install.sh` |
| `README.md` tracked-config table | `TOOLS` in `installers/config/install.sh` and the scripts beside it |
| `installers/installers.md` | profiles, component scripts, the registry fields `installers/installer.sh` parses, helpers in `installers/lib/`, `STEPS_*` in `installers/lib/steps.sh` |
| `macos/README.md` | `macos/install.sh`, `macos/brew.txt` |
| `ducky/README.md`, `ducky/payloads/ubuntu-install.txt` | `scripts/resync` and the profile names |
| `justfile` comments | `scripts/rgb`, installer targets |
| glyph tables in `README.md` and `tmux/tmux.conf` | `GLYPHS` in `scripts/agent-tmux` |

- **Check:** also that every URL still resolves (`git grep -ohE 'https?://[^ )>"]+' | sort -u`).
- **Verify:** pre-commit on the changed files; after payload edits,
  `python3 tests/test_ducky_encode.py`.

### Lists kept in two places

- Branch types: `skills/worktree/SKILL.md` and `CONVENTIONAL_PREFIXES` in
  `scripts/agent-tmux`. Verify: `bash tests/test_agent_tmux.sh`.
- Components that run on both OSes: `COMPONENTS` in `installers/installer.sh`
  and `MACOS_COMPONENTS` in `macos/install.sh`. Verify:
  `bash tests/test_macos_install.sh`.
- Install channels and upgrades: each component upgrades what it installed
  (the contract in `installers/installers.md`). A channel with no upgrade step
  is the finding; today that is Neovim under `/opt`, the root path of
  `installers/lazyvim/install.sh`, installed once and never upgraded.

### Agent CLI config

The CLIs update themselves. Note each one's `--version`, then check its config
against its current docs.

| Config | Check against |
| --- | --- |
| `claude/settings.json` + `agents/permissions.json` | its `$schema`, hooks and settings docs (the allow list's tool names); `claude doctor`; rules auto mode refuses (`/auto-mode-setup` drops them from the live file only, so diff the live `permissions` with `agents/permissions.json`) |
| `opencode/config.jsonc`, synced alone | OpenCode's `$schema` (it rejects unknown keys) and permissions docs: action names, wildcards, how `read` paths and `shell` commands match, last match wins. A matching change redoes the read-rule translation below. |
| `codex/config.toml`, `.codex/config.toml` | `codex features list` (flags for stable or removed features), the config reference for renamed keys and new hook events |
| `grok/config.toml`, `grok/hooks/agent-tmux.json` | `grok doctor`, Grok's hook docs |
| `agy/settings.json`, `agy/hooks.json` | Antigravity's settings and hook docs |
| `scripts/statusline-worktree` | Claude's status-line payload docs, for each field it reads |
| `skills/` frontmatter, `skills/land/scripts/next_check.py` | each CLI's skill docs and discovery dirs; `gh pr view --json` field values |

- **Update:** models (`model` in `claude/settings.json`, `codex/config.toml`,
  `agy/settings.json`) are the user's call; propose, don't switch.
- **Verify:** `python3 tests/test_inject_config.py`, `bash tests/test_agy.sh`,
  `python3 tests/test_statusline_worktree.py`, `python3 tests/test_next_check.py`;
  on a synced machine, start each CLI and watch its tmux window glyph change.

### Same intent in every CLI

Each CLI reads deny rules and turn-state hooks from its own hand-written file;
nothing renders one source into every format, because the formats change
every few weeks and the CLIs differ in meaning, not only syntax. A change to
one file goes to the rest of its row in the same PR. The empty cells are
deliberate (Codex, Grok and Antigravity run with full access; OpenCode has no
hook wiring); ask the user before filling one.

| Intent | Claude Code | OpenCode | Codex | Grok | Antigravity |
| --- | --- | --- | --- | --- | --- |
| Deny rules | `agents/permissions.json` | `opencode/config.jsonc` | none | none | none |
| Turn-state hooks for `scripts/agent-tmux` | `claude/settings.json` | none | `codex/config.toml` | `grok/hooks/agent-tmux.json` | `agy/hooks.json` |

- **Check:** shell denies match apart from OpenCode's own `gh pr` denies:

  ```bash
  diff <(jq -r '.permissions.deny[] | select(startswith("Bash(")) | .[5:-1]' agents/permissions.json | sort) \
    <(jq -r '.permissions[] | select(.action == "shell") | .resource' opencode/config.jsonc | sort)
  ```

  Read denies match after translation (`Read(...)` rules against
  `.action == "read"` resources): OpenCode's `*` crosses `/`, so Claude's
  `dir/**` is `dir/*`, `**/*.ext` is `*.ext`, and `**/name` is both `name` and
  `*/name`. Each hook file reports every turn state
  (`grep -oE 'agent-tmux state [a-z]+( --soft)?'`) except the gaps its CLI
  has no event for: Codex `error` and soft `waiting`, Grok soft `waiting`,
  Antigravity `error` and `clear`.
- **Update:** change every file in the row, each in its CLI's own format.
- **Verify:** `python3 tests/test_inject_config.py`,
  `bash tests/test_macos_install.sh`, `bash tests/test_agent_tmux.sh`,
  `bash tests/test_agy.sh`.

### OpenRGB AppImage pin

- **Where:** `OPENRGB_VERSION`, `OPENRGB_COMMIT`, `OPENRGB_RELEASE_URL` and the
  per-arch SHA-256s in `installers/openrgb/install.sh`.
- **Check:** the newest release at
  `https://codeberg.org/api/v1/repos/OpenRGB/OpenRGB/releases?limit=3` (assets
  `OpenRGB_<version>_<arch>_<commit>.AppImage`); and whether Ubuntu's package
  now lights NVIDIA Founders Edition cards, which would retire the AppImage.
- **Update:** version, commit and tag from the asset names; the checksums need
  a download, so give the user the `curl … | sha256sum` commands.
- **Verify:** on a workstation, `bash installers/openrgb/install.sh`, then
  `just rgb doctor`.

### Latest-release downloads

- **Where:** `installers/lazyvim/install.sh` (`nvim-linux-<arch>.tar.gz`, root
  only), `installers/bazelisk/install.sh` (`bazelisk-linux-<arch>`),
  `installers/buildtools/install.sh` (buildifier, buildozer, unused-deps).
- **Check:** each project's latest release still publishes those asset names
  (`gh api repos/<owner>/<repo>/releases/latest --jq '.assets[].name'`).
- **Verify:** the container with `bazelisk buildtools lazyvim`.

### Vendor install scripts

- **Where:** every `install_from_web_script` call under `installers/`, plus
  Homebrew (`installers/homebrew/install.sh`) and rustup
  (`installers/cargo/install.sh`).
- **Check:** the vendor doc linked in each script's header still gives the
  same URL, binary, location and flags, and has not moved to another install
  method.
- **Verify:** the container with the component; `bash tests/test_install_steps.sh`.

### Third-party APT repositories

- **Where:** Docker and the NVIDIA Container Toolkit in
  `installers/docker/install.sh` (keys, sources, `DOCKER_PACKAGES`, and
  `CONFLICTING_PACKAGES`, a copy of Docker's "Uninstall old versions" list);
  RealSense in `installers/robotics/install.sh`; NodeSource `setup_lts.x` in
  `installers/lazyvim/install.sh`; PPAs in the manifests (`git grep 'ppa:' installers/`).
- **Check:** each vendor's current Ubuntu instructions (linked in the script
  header), and that each repository publishes the codenames the machines run
  (`dists/<codename>/Release`).
- **Verify:** on a GPU workstation, `bash installers/installer.sh docker robotics`,
  then `docker run --rm --gpus all ubuntu nvidia-smi`.

### Package manifests

- **Where:** `installers/apt/`, `installers/desktop-apps/` (APT, snaps,
  Flatpaks), `installers/homebrew/brew_packages.txt`, `macos/brew.txt`,
  `installers/cargo/cargo_packages.txt`. Nothing is pinned.
- **Check:** every entry still resolves: `apt-get -s install` in a container
  for each Ubuntu release the machines run, `brew info [--cask]`,
  `cargo search --limit 1`, `snap info` and `flatpak remote-info flathub` on
  amd64 (both stores filter by arch, and the installer skips amd64-only apps
  on arm64).
- **Update:** rename an entry and keep its `# description`; ask before removing one.
- **Verify:** `bash tests/test_packages.sh`; on a machine,
  `bash installers/installer.sh <component>`.

### tmux plugins and copied snippets

- **Where:** `installers/tmux/install.sh` fast-forwards tmux-resurrect and
  tmux-continuum on every run and works around their internals (continuum's
  systemd `ExecStop` save, its save job in `status-right`, `save.sh` writing an
  empty frame). `tmux/tmux.conf` copies tmux's default `status-right` (its last
  line) and vim-tmux-navigator's `vim_pattern` / `is_vim` snippet.
- **Check:** upstream commits since the last pass that touch those internals;
  `tmux -L m -f /dev/null start-server \; show-options -gv status-right` for
  each tmux the machines run, against our line; the navigator README against
  our snippet; on a new mosh release, the comments' claim that it forwards
  only OSC 0/1/2/8/52.
- **Update:** adjust the workaround, or delete it if upstream fixed the cause;
  copy upstream's text.
- **Verify:** `bash tests/test_tmux_install.sh`, `bash tests/test_agent_tmux.sh`,
  `python3 tests/test_tmux_osc52.py`.

### LazyVim

- **Where:** `installers/lazyvim/install.sh` (the LazyVim starter, detected by
  `lua/config/lazy.lua`; cask `font-jetbrains-mono-nerd-font`),
  `installers/lazyvim/plugins/vim-tmux-navigator.lua` (the plugin's commands),
  `installers/lazyvim/plugins/url-underline.lua` (captures
  `@string.special.url`, `@markup.link.url`).
- **Check:** the starter still has that file, the cask still exists,
  nvim-treesitter still defines those captures; `:LazyHealth` is clean on a
  workstation.
- **Verify:** `bash tests/test_lazyvim_font.sh`, `bash tests/test_nvim_config.sh`.

### herdr-core contract

- **Where:** `scripts/agent-session`, `skills/session/SKILL.md`, and the stub
  `hc` in `tests/test_agent_session.py` rely on `hc run --bg --json --no-parent
  --name --cwd --on --label`, `hc get`/`ls --json`, `exec`, `send`, `read`,
  `machine ls`, `$HC_TERMINAL_ID`, the labels `herdr.space`, `herdr.tab` and
  `where`, `foreground.argv`, and the `blocked` status.
- **Check:** `hc --version` against herdr-core's latest tag; its changelog and
  `hc run --help` / `hc get --help` for those flags and fields.
- **Update:** the script, the skill and the stub together.
- **Verify:** `python3 tests/test_agent_session.py`; start a session from a
  Herdr terminal.

### macOS app config (on the Mac)

- **Where:** `macos/warp-settings.toml` (merged into `~/.warp/settings.toml`);
  `macos/.aerospace.toml`, AeroSpace's default config with our edits.
- **Check:** Warp still honors each key; upstream's
  `docs/config-examples/default-config.toml` at the installed AeroSpace tag
  against ours.
- **Update:** take upstream's new keys and `config-version`; keep our edits.
- **Verify:** `bash tests/test_aerospace_config.sh`,
  `python3 tests/test_aerospace_workspaces.py`; `aerospace reload-config`.

## When Ubuntu ships a release the machines will run

Ask the user which releases their machines run. Run the manifest check and the
container on the new release first. Code written for particular releases, each
verified by its test under `tests/` or on a machine of that release:

- `installers/codex/install.sh` loads AppArmor's `bwrap-userns-restrict`
  because 24.04+ restricts unprivileged user namespaces, which Codex's
  bubblewrap sandbox needs. Delete it when Ubuntu loads an equivalent itself or
  Codex stops using bubblewrap.
- `installers/apt/apt_packages.txt` lists `libfuse2`, the 22.04 name;
  `missing_apt_packages` in `installers/lib/packages.sh` accepts 24.04's
  `libfuse2t64` for it. When 22.04 goes, list the new name and drop that branch.
- `installers/robotics/install.sh`: the RealSense codename allowlist.
- `installers/config/gnome.sh`: `hidden_favorites` desktop IDs
  (`gsettings get org.gnome.shell favorite-apps` on a fresh desktop).
- `installers/lazyvim/install.sh` and `theme_mode` in `.bash_aliases`
  configure GNOME Terminal. If the release ships another default terminal
  (Ptyxis), ask whether to retarget them.
- `installers/config/power.sh`: power-profiles-daemon, else cpufrequtils.
- `installers/config/ssh.sh`: `sshd_config.d` and socket-activated
  `ssh.service`; verify with `sudo sshd -t` and a key login.
- `installers/nvidia-driver/install.sh` parses `ubuntu-drivers devices` for
  the one recommended driver.
- `alias shumble` in `.bash_aliases` sources ROS 2 Humble, 22.04's ROS.

## On each machine, after `resync`

This pass replaces migration shims. A change that moves, renames or drops
something the repo installs (a link, a command, a skill, a program's install
channel) ships no code to remove the old one from other machines. Instead, on
each machine the user maintains, compare what is installed with what the repo
installs today, and remove or redo the difference. Run it after `resync`, and
whenever `resync` fails on something the repo no longer installs.

It changes the machine, not the repo. Work in the primary checkout (the first
line of `git worktree list`) on `main` and commit nothing. Start with
`bash <primary checkout>/scripts/resync config`, which relinks everything
config sync still manages; the `resync` on `PATH` may point into a deleted
worktree. Agents may not run `rm` or `sudo` (`agents/permissions.json`), so
hand each removal to the user as a `! <command>` line, saying what it deletes
and why.

### Links into a checkout

- **Where:** the `apply_link` and `apply_skill_links` calls in
  `installers/config/`, and files installers write outside a package manager
  (`/etc`, `/opt`, `/usr/local`).
- **Check:** links into any checkout of the repo (portable to macOS):
  `find ~ -xdev -maxdepth 6 \( -name .git -o -name node_modules -o -name .cache \) -prune -o -type l -exec ls -l {} + 2>/dev/null | grep -- '-> .*linux-utils'`.
  A link is stale when it dangles, points anywhere but the primary checkout (a
  worktree under `<repo>__worktrees/` or an older `<repo>-<branch>`), or no
  sync script makes it today. So is a system file an installer used to write
  (`git log -p -- installers/`), and a `*.bak.<timestamp>` backup sync left
  beside a file it replaced.
- **Update:** remove the stale ones; ask before removing a backup or anything
  not plainly the repo's.
- **Verify:** the `find` lists only links today's sync makes, all into the
  primary checkout.

### Agent instructions, skills and config

- **Where:** `installers/config/agents.sh` and the per-CLI scripts beside it:
  `agents/instructions.md` as each CLI's global instructions, `skills/` and
  `scripts/` under `~/.agents/` and each CLI's skill directory, and the live
  files `inject_config` merges into.
- **Check:** each is a link into the primary checkout, not a copy or a
  directory of per-file links, and no skill or script directory holds one the
  repo dropped. `inject_config` keeps keys it does not own, so a key the repo
  dropped or renamed lingers in the live file: read the source's history
  (`git log -p -- codex/config.toml`) against it.
- **Update:** `resync config` relinks; delete dropped keys from the live files.
- **Verify:** `resync config` finds everything already linked and merged; each
  CLI starts without config warnings.

### Shell

- **Where:** `installers/config/bash.sh` (links `.bash_aliases` and
  `scripts/resync`, and sources the aliases from `~/.bashrc`), and the rc
  lines other installers append (`installers/zoxide/install.sh`).
- **Check:** rc lines an earlier installer wrote that today's writes
  differently or not at all (`git log -p -S .bashrc -- installers/`), and
  commands in `~/.local/bin` that no sync makes now.
- **Update:** make the rc files match what today's installers write and
  remove the stale commands. Re-sourcing does not unset a dropped function, so
  tell the user which shells and tmux panes to restart.
- **Verify:** `bash -ic 'type -a resync'` starts without errors and finds one
  `resync`, linked into the primary checkout.

### Programs and install channels

- **Where:** each component's `install.sh` and manifest under `installers/`,
  and the APT sources and keyrings installers add.
- **Check:** for each command the machine's profile installs, `type -a` it and
  ask every manager that could hold another copy: `snap list`,
  `flatpak list --app`, `uv tool list`, `pipx list`, `cargo install --list`,
  `npm ls -g`, `brew list`, Mason (`~/.local/share/nvim/mason/packages/`).
  Stale: a copy from a channel its installer no longer uses (netron as a snap;
  a uv tool since #145), a program dropped from a manifest or with its
  component (`git log -p -- installers/`), an APT source or keyring no
  installer adds.
- **Update:** install through today's channel first
  (`bash installers/installer.sh <component>`), then hand over the old copy's
  removal (`! sudo snap remove netron`). Ask before removing a program the
  repo dropped; the user may still use it.
- **Verify:** `type -a <command>` finds one copy, from its installer's channel.

## When the user agrees to drop the migration shims

Code written before the machine pass to move machines off an old layout.
Delete each, with its test, once the user agrees; delete this section with the
last one.

| Shim | Added in |
| --- | --- |
| `retired_gh_sources` in `installers/installer.sh` | #87 |
| `LEGACY_SYS_LIB` in `installers/openrgb/install.sh` | #59 |
| the `remove_stale_path` calls in `installers/config/agents.sh` | #94 |
| `~/.local/bin/upkeep` removal in `installers/config/bash.sh` | #148 |
| per-file skill links (`is_repo_link_tree`) in `installers/config/lib.sh` | #42 |
| Codex `max_threads` alias in `scripts/inject-config` | #29 |
| zoxide PATH line insertion in `installers/zoxide/install.sh` | #82 |
| `remove_shadowed_treesitter_cli` in `installers/lazyvim/install.sh`; confirm LazyVim no longer asks Mason for it | #82 |

- **Verify:** `bash tests/run.sh`.
