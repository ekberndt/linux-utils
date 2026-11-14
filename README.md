# linux-utils

Bootstrap and configuration sync for Ubuntu workstations, headless GPU nodes, and macOS machines.

## Quickstart

`just install` installs what is missing and upgrades what is already installed: system and Homebrew packages, global npm/pnpm/pip/pipx packages, uv tools, agent CLIs, and Cargo crates. A re-run within the hour skips index refreshes and checks cheaply before upgrading anything.

```bash
just install                 # Default profile (workstation on Linux, Homebrew + config on macOS)
just install datacenter      # Headless GPU host (root-owned, leaves image NVIDIA/CUDA drivers intact)
just install agy uv zoxide   # Individual cross-platform or OS-specific components
just config                  # Sync tracked shell, editor, tmux, and agent configs only
just install list            # List all profiles and components
just install plan datacenter # Preview resolved installation steps without mutating the host
```

Before `just` is installed (`cargo` component), invoke the entry point directly:

```bash
bash installers/installer.sh <profile-or-component>...
bash installers/config/install.sh --dry-run
```

Once config is synced, `resync` brings the machine in line with `main` from any directory, so a change merged from one machine reaches the others: it fast-forwards this checkout to `origin/main`, then runs the installer with the same targets (default `workstation`; `resync config` syncs config only). `resync plan` and `resync list` leave the checkout as it is. It stops when the checkout is off `main` or a fast-forward would discard local work, and falls back to the last fetched `origin/main` offline. `just install` installs a checkout as it stands, for testing a branch.

## Profiles

| Target | OS | Scope |
| --- | --- | --- |
| `workstation` | Ubuntu | APT, Snap and Flatpak upgrades, global npm/pnpm/pip/pipx packages, recommended NVIDIA driver, Docker + NVIDIA runtime, Homebrew, `uv`, `netron`, `wandb`, `cargo`, `bazelisk`, `buildtools`, `gh`, `claude`, `codex`, `grok`, `agy`, `opencode`, `herdr-core`, `zoxide`, `ollama`, `tailscale`, `openrgb`, `lazyvim`, `tmux`, `robotics`, `config`. Append `desktop-apps` for personal GUI apps and `herdr` for the Herdr app. |
| `datacenter` | Ubuntu | Headless root-owned GPU host. Installs Docker + NVIDIA runtime, toolchains, agent CLIs, `herdr-core`, LazyVim, tmux persistence, and `config`; skips GUI apps, Homebrew, and host NVIDIA driver changes. |
| `install` | macOS | Installs Homebrew formulae/casks from [`macos/brew.txt`](macos/brew.txt), upgrades everything Homebrew holds and every cross-platform component already installed, and runs `config`. Naming a cross-platform component (`uv`, `wandb`, `opencode`, `claude`, `codex`, `grok`, `agy`, `herdr`, `herdr-core`, `zoxide`, `cargo`, `npm`, `pnpm`, `pip`, `pipx`) installs it. |

See [`installers/installers.md`](installers/installers.md) for profile contracts and [`macos/README.md`](macos/README.md) for macOS AeroSpace prerequisites.

## Tracked Config

Files rewritten by agents at runtime are merged via [`scripts/inject-config`](scripts/inject-config) (tracked keys win, machine-local keys survive, prior files are backed up with a timestamp). Static files are symlinked.

| Source | Target | Method |
| --- | --- | --- |
| [`.bash_aliases`](.bash_aliases) | `~/.bash_aliases` | symlink |
| [`scripts/resync`](scripts/resync) | `~/.local/bin/resync` (on PATH via `~/.bash_aliases`, or a line in `~/.zshrc` for zsh users) | symlink |
| `.env` (copy [`.env.example`](.env.example)) | `user.name`, `user.email` in `~/.gitconfig` | `git config --global` |
| [`ssh/config`](ssh/config) | `~/.ssh/config` | SSH config merge |
| [`scripts/`](scripts/) | `~/.agents/scripts/` | symlink |
| [`agents/instructions.md`](agents/instructions.md) | `~/.claude/CLAUDE.md` (Grok and OpenCode read it too), `~/.codex/AGENTS.md`, `~/.gemini/config/AGENTS.md` | symlink |
| [`skills/`](skills/) | `~/.agents/skills/`, `~/.claude/skills/`, `~/.gemini/config/skills/` | symlink |
| [`agents/permissions.json`](agents/permissions.json) + [`claude/settings.json`](claude/settings.json) | `~/.claude/settings.json` | JSON merge |
| [`opencode/config.jsonc`](opencode/config.jsonc) | `~/.config/opencode/opencode.jsonc` | JSON merge |
| [`codex/config.toml`](codex/config.toml) | `~/.codex/config.toml` | TOML merge |
| [`grok/config.toml`](grok/config.toml), [`grok/hooks/`](grok/hooks/) | `~/.grok/config.toml`, `~/.grok/hooks/` | TOML merge + symlink |
| [`agy/settings.json`](agy/settings.json), [`agy/hooks.json`](agy/hooks.json) | `~/.gemini/antigravity-cli/settings.json`, `~/.gemini/config/hooks.json` | JSON merge |
| [`tmux/tmux.conf`](tmux/tmux.conf) | `~/.config/tmux/tmux.conf` | symlink |
| [`herdr/`](herdr/) (agent-tree mod and layout, see [`herdr/README.md`](herdr/README.md)) | `~/.config/herdr-app/mods/agent-tree/`, `~/.config/herdr-app/layouts/agent-tree.json` | symlink |
| [`installers/lazyvim/plugins/`](installers/lazyvim/plugins/) | `~/.config/nvim/lua/plugins/` | symlink |
| [`macos/.aerospace.toml`](macos/.aerospace.toml) + `macos/app-workspaces.cfg` | `~/.aerospace.toml` (macOS) | generated |
| [`macos/warp-settings.toml`](macos/warp-settings.toml) | `~/.warp/settings.toml` (macOS) | TOML merge |
| [`installers/config/screenshots.sh`](installers/config/screenshots.sh) | `~/Pictures/screenshots` (macOS) | `defaults write` |
| [`installers/config/{gnome,power,kernel,ssh}.sh`](installers/config/) | GNOME dock/idle, CPU governor, kernel `sysctl` limits, key-only `sshd` (Linux) | system config |

## Tmux & Agent Integration

Agent hooks call [`scripts/agent-tmux`](scripts/agent-tmux) on lifecycle transitions to rename tmux windows after their branch and render live status glyphs without polling:

| Glyph | State | Keybinding / Transition |
| --- | --- | --- |
| `○` | `idle` | Session start, or after viewing a `done` window |
| `◐` | `busy` | Turn in progress |
| `◇` | `monitor` | `agent-tmux state monitor` (background wait; skipped by `prefix a`) |
| `◆` | `waiting` | Permission prompt or user input needed |
| `●` | `done` | Turn completed |
| `✖` | `error` | Turn failed |

- `prefix a`: Jump to the next window in `waiting`, `done`, or `error`.
- `prefix A`: Open an interactive picker across all agent windows with elapsed time in state.
- `prefix ]`: Import client clipboard via OSC 52 and paste into pane (see [`tmux/tmux.conf`](tmux/tmux.conf) for OSC 52 and `tmux-resurrect` / `tmux-save.timer` details).

## Herdr Sessions

Asking an agent for a "new session" runs the [`session`](skills/session/SKILL.md) skill: it writes a self-contained brief and starts a separate agent with [`scripts/agent-session`](scripts/agent-session), which opens it in a new tab of the Herdr space the caller is shown in, so it appears in the app's left panel.

## Utilities & Development

- **Chassis & GPU RGB (Linux):** `just rgb status|off|on [RRGGBB]|install|doctor` ([`scripts/rgb`](scripts/rgb)).
- **USB Rubber Ducky Ubuntu Bootstrap:** `just ducky-flash` ([`ducky/README.md`](ducky/README.md)).
- **Tests & Linting:** `just test` (`bash tests/run.sh`) and `just lint` (`pre-commit run --all-files`).
- **Maintenance:** [`MAINTENANCE.md`](MAINTENANCE.md) lists what drifts and how to bring it back; the [`maintenance`](skills/maintenance/SKILL.md) skill runs a pass.
