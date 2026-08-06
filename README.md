# linux-utils

Ubuntu installer, tracked shell/editor/agent config, and a few workstation
utilities.

## Install

```bash
bash installers/installer.sh workstation
bash installers/installer.sh datacenter
bash installers/installer.sh uv cargo config
```

`workstation` installs the full development environment, Ubuntu's recommended
NVIDIA driver when the machine has an NVIDIA GPU, Docker with its NVIDIA
runtime, and a key-only OpenSSH server. Personal desktop applications remain
opt-in:

```bash
bash installers/installer.sh workstation desktop-apps
```

Reboot after the first NVIDIA driver installation before verifying `nvidia-smi`
or Docker GPU access. Add an authorized key before relying on remote access;
the managed SSH policy does not permit password login.

`datacenter` is a root-owned, headless GPU host with:

- Docker and the NVIDIA container runtime
- uv, W&B, Rustup/Cargo, Bazelisk, buildtools, and GitHub CLI
- Claude Code, Codex, and Grok Build
- current Neovim with LazyVim, tmux persistence, and tracked config

The datacenter installer runs system commands directly as UID 0, needs neither
`sudo` nor `just`, and leaves image-provided NVIDIA drivers and CUDA alone. It
excludes Homebrew, desktop apps, OpenRGB, Ollama, Tailscale, and RealSense. Add
components when wanted:

```bash
bash installers/installer.sh datacenter ollama tailscale
```

Discover or preview targets without changing the machine:

```bash
bash installers/installer.sh list
bash installers/installer.sh plan datacenter
```

Optional APT entries (`? package`) are skipped unless you pass `--optionals`.
See [the installer guide](installers/installers.md) for profile contracts and
package manifests.

## Optional `just` commands

The bootstrap path is plain Bash. The Cargo component installs `just` for these
shortcuts:

```bash
just install
just install datacenter
just install workstation desktop-apps
just install uv cargo config
just config
just test
just lint
```

## Tracked config

```bash
bash installers/installer.sh config
bash installers/config/install.sh --dry-run
```

| Source | Destination |
| --- | --- |
| [`.bash_aliases`](.bash_aliases) | `~/.bash_aliases` |
| [`scripts/`](scripts/) | `~/.agents/scripts/` |
| [`skills/`](skills/) | `~/.claude/skills/`, `~/.agents/skills/` |
| [`claude/settings.json`](claude/settings.json) | merged into `~/.claude/settings.json` |
| [`codex/config.toml`](codex/config.toml) | merged into `~/.codex/config.toml` |
| [`grok/`](grok/) | merged/linked under `~/.grok/` |
| [`installers/lazyvim/plugins/`](installers/lazyvim/plugins/) | `~/.config/nvim/lua/plugins/` |
| [`tmux/tmux.conf`](tmux/tmux.conf) | `~/.config/tmux/tmux.conf` |

Files that agents rewrite are merged rather than symlinked. Tracked keys win;
machine-local keys remain. Conflicting targets are timestamp-backed up.
Config sync also sets GNOME's display blank timeout to 15 minutes and selects
the performance power profile and CPU governor when the machine supports them.
It removes Help and App Center from GNOME dock favorites without changing the
other pinned applications, and configures OpenSSH for public-key-only login.

## Agent state in tmux

Agent hooks rename each window to its branch and show its state without polling.

| Glyph | State |
| --- | --- |
| `○` | idle |
| `◐` | working |
| `◇` | monitoring |
| `◆` | needs input |
| `●` | finished |
| `✖` | API error |

`prefix a` jumps to the next window needing attention; `prefix A` opens a
picker. A long-running watcher can opt out of attention with
`agent-tmux state monitor` and return with `agent-tmux state busy`.

## tmux clipboard

Copy mode's `y`, Enter, and mouse selection update tmux and the iTerm2/macOS
clipboard over SSH or mosh. `prefix ]` pastes into the active pane from, in
order: the local system clipboard (`wl-paste` / `xclip`), an OSC 52 client
query (iTerm2), then the latest tmux buffer. `Cmd-V` / middle-click remain
direct terminal pastes.

OSC 52 reads need iTerm2 3.5+ and **Settings → General → Selection →
Applications in terminal may access clipboard**. mosh often cannot answer that
query, so paste falls back to the last tmux buffer. Reload with `prefix r`
after config sync.

## tmux persistence

```bash
bash installers/installer.sh tmux
```

tmux-resurrect and tmux-continuum save layouts every 15 minutes and restore a
new server. `prefix C-s` saves now and `prefix C-r` restores. Pane history and
agent processes are intentionally not restored.

## Shell helpers

Config sync installs two functions that locate the checkout through the
`~/.bash_aliases` symlink or `LINUX_UTILS_ROOT`:

```bash
linux-utils-install
linux-utils-install datacenter
linux-utils-install uv cargo
linux-utils-config
```

`linux-utils-install` fast-forwards `main`, installs the workstation profile when
called without targets, then reloads aliases. First-time setup:

```bash
bash installers/installer.sh config
source ~/.bash_aliases
```

## Neovim over SSH

The SSH client renders fonts. For iTerm2, install and select JetBrainsMono Nerd
Font Mono on the Mac:

```bash
brew install --cask font-jetbrains-mono-nerd-font
```

## Other utilities

- [`scripts/rgb`](scripts/rgb) controls OpenRGB-supported hardware. Install with
  `just install openrgb`, then `just rgb install`.
- [`vscode/install_vscode_extensions.sh`](vscode/install_vscode_extensions.sh)
  installs extensions from a VS Code recommendations file.
- [`ducky/`](ducky/) contains the Ubuntu USB Rubber Ducky bootstrap.

## Development

```bash
pre-commit run --all-files
bash tests/run.sh
```
