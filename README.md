# linux-utils

Bootstrap and configuration sync for Ubuntu workstations, headless GPU nodes, and macOS machines.

## Quickstart

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

After syncing config, `linux-utils-install [targets]` and `linux-utils-config` are available in interactive shells from any directory.

## Profiles

| Target | OS | Scope |
| --- | --- | --- |
| `workstation` | Ubuntu | APT/Snap/Flatpak, recommended NVIDIA driver, Docker + NVIDIA runtime, Homebrew, `uv`, `wandb`, `cargo`, `bazelisk`, `gh`, `claude`, `codex`, `grok`, `agy`, `opencode`, `zoxide`, `ollama`, `openrgb`, `lazyvim`, `tmux`, `robotics`, `config`. Append `desktop-apps` for personal GUI apps. |
| `datacenter` | Ubuntu | Headless root-owned GPU host. Installs Docker + NVIDIA runtime, toolchains, agent CLIs, LazyVim, tmux persistence, and `config`; skips GUI apps, Homebrew, and host NVIDIA driver changes. |
| `install` | macOS | Installs Homebrew formulae/casks from [`macos/brew.txt`](macos/brew.txt) and runs `config`. Cross-platform components (`uv`, `wandb`, `opencode`, `claude`, `codex`, `grok`, `agy`, `zoxide`) can also be targeted individually. |

See [`installers/installers.md`](installers/installers.md) for profile contracts and [`macos/README.md`](macos/README.md) for macOS AeroSpace prerequisites.

## Tracked Config

Files rewritten by agents at runtime are merged via [`scripts/inject-config`](scripts/inject-config) (tracked keys win, machine-local keys survive, prior files are backed up with a timestamp). Static files are symlinked.

| Source | Target | Method |
| --- | --- | --- |
| [`.bash_aliases`](.bash_aliases) | `~/.bash_aliases` | symlink |
| `.env` (copy [`.env.example`](.env.example)) | `user.name`, `user.email` in `~/.gitconfig` | `git config --global` |
| [`scripts/`](scripts/) | `~/.agents/scripts/` | symlink |
| [`skills/`](skills/) | `~/.agents/skills/`, `~/.claude/skills/`, `~/.gemini/config/skills/` | symlink |
| [`agents/permissions.json`](agents/permissions.json) + [`claude/settings.json`](claude/settings.json) | `~/.claude/settings.json` | JSON merge |
| [`agents/permissions.json`](agents/permissions.json) + [`opencode/config.jsonc`](opencode/config.jsonc) | `~/.config/opencode/opencode.jsonc` | JSON merge |
| [`codex/config.toml`](codex/config.toml) | `~/.codex/config.toml` | TOML merge |
| [`grok/config.toml`](grok/config.toml), [`grok/hooks/`](grok/hooks/) | `~/.grok/config.toml`, `~/.grok/hooks/` | TOML merge + symlink |
| [`agy/settings.json`](agy/settings.json), [`agy/hooks.json`](agy/hooks.json) | `~/.gemini/antigravity-cli/settings.json`, `~/.gemini/config/hooks.json` | JSON merge |
| [`tmux/tmux.conf`](tmux/tmux.conf) | `~/.config/tmux/tmux.conf` | symlink |
| [`installers/lazyvim/plugins/`](installers/lazyvim/plugins/) | `~/.config/nvim/lua/plugins/` | symlink |
| [`macos/.aerospace.toml`](macos/.aerospace.toml) + `macos/app-workspaces.cfg` | `~/.aerospace.toml` (macOS) | generated |
| [`macos/warp-settings.toml`](macos/warp-settings.toml) | `~/.warp/settings.toml` (macOS) | TOML merge |
| [`installers/config/screenshots.sh`](installers/config/screenshots.sh) | `~/Pictures/screenshots` (macOS) | `defaults write` |
| [`installers/config/{gnome,power,ssh}.sh`](installers/config/) | GNOME dock/idle, CPU governor, key-only `sshd` (Linux) | system config |

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

## Utilities & Development

- **Chassis & GPU RGB (Linux):** `just rgb status|off|on [RRGGBB]|install|doctor` ([`scripts/rgb`](scripts/rgb)).
- **USB Rubber Ducky Ubuntu Bootstrap:** `just ducky-flash` ([`ducky/README.md`](ducky/README.md)).
- **Tests & Linting:** `just test` (`bash tests/run.sh`) and `just lint` (`pre-commit run --all-files`).
