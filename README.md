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

## Passphrase-free warm restarts

Keep LUKS passphrase-only while allowing remote userspace restarts:

```bash
bash installers/installer.sh warm-reboot
sudo warm-reboot
```

`warm-reboot` uses systemd's soft reboot, so the running kernel and unlocked
root filesystem remain in place while userspace restarts. A power loss or real
reboot still starts from the LUKS passphrase prompt. Kernel and firmware updates
require a real reboot and its passphrase; this command does not enroll a TPM
unlock key.

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

Optional APT entries (`? package`) are skipped unless you pass `--optionals`;
they never prompt interactively. After the initial sudo password, the installer
keeps the credential active through long-running components. See the
[installer guide](installers/installers.md) for profile contracts and package
manifests.

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

Files that agents rewrite are merged rather than symlinked, by
[`scripts/inject-config`](scripts/inject-config) for both JSON and TOML.
Tracked keys win; machine-local keys remain. Conflicting targets are
timestamp-backed up.
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

Copying out is one clipboard: whatever you copy on the remote lands on the
macOS clipboard, whether it came from tmux copy mode (`y`, Enter, mouse drag)
or from an application that sets the clipboard itself (nvim, the agent CLIs).
Both travel to the terminal as OSC 52.

Coming back the other way, use `Cmd-V` — iTerm2 sends it as keystrokes, so no
escape sequence has to survive the link. `prefix ]` pastes tmux's own buffer,
which after any tmux copy holds the same text as the Mac clipboard; the two
diverge only when you last copied in a different Mac app.

`Cmd-C` copies iTerm2's *own* selection, not tmux's. With `mouse on` tmux
captures the drag, so iTerm2 has nothing selected — hold **⌥ Option** while
dragging for a native selection. Dragging without Option is the shorter path:
tmux copies it and mirrors it to the Mac for you.

Over mosh only the explicit `ESC ] 52 ; c ;` form survives, and OSC 52 *queries*
are never answered, so `prefix ]` cannot read the Mac clipboard there and falls
back to the latest tmux buffer. Do not paper over the selection byte with a
terminfo `Ms` override: a capability that hardcodes `c` and never references
`%p1` expands to nothing and silently disables every clipboard write tmux makes,
application forwarding included. `tests/test_tmux_osc52.py` guards that.

OSC 52 reads (plain ssh, not mosh) need iTerm2 3.5+ and **Settings → General →
Selection → Applications in terminal may access clipboard**. Reload with
`prefix r` after config sync; clients pick up terminal capability changes on
their next attach.

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

`tests/run.sh` runs every `tests/test_*.sh` and `tests/test_*.py`; add a file
and it is picked up. Tests drive the real scripts — the installer's plan
resolution, a throwaway tmux server, a scratch `$HOME` — rather than asserting
on source text, so they survive refactors and catch what actually breaks. Both
suites run in CI.
