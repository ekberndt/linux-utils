# linux-utils

Ubuntu and macOS workstation setup, tracked shell/editor/agent config, and a
few workstation utilities.

## Install

`just install` and `just config` pick the OS themselves. On macOS, `just install`
installs Homebrew packages from [`macos/brew.txt`](macos/brew.txt) and agent
config (skills, AeroSpace, Warp OSC 52, editor, tmux). On Linux they run the
named profile or component.

### Ubuntu

```bash
bash installers/installer.sh workstation
bash installers/installer.sh datacenter
bash installers/installer.sh uv cargo config
```

### macOS

Install [Homebrew](https://brew.sh), then `just install`. `just config` later
refreshes AeroSpace, Warp OSC 52, and agent config without Homebrew.

See the [macOS guide](macos/README.md) for the AeroSpace prerequisite.

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
| [`macos/.aerospace.toml`](macos/.aerospace.toml) | `~/.aerospace.toml` (macOS) |
| [`macos/warp-settings.toml`](macos/warp-settings.toml) | merged into `~/.warp/settings.toml` (macOS) |
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

An agent launched in the main checkout stays there even after it creates a
worktree, so it names its window for the branch it moved to with `agent-tmux
worktree <path>`; the [new-worktree skill](skills/new-worktree) does this for
the worktree it just made. The name falls back to the pane's own checkout once
that worktree is deleted.

The terminal tab is the one thing the Mac cannot infer: it shows the host you
are typing on, plus one `●` per window elsewhere in the session that wants you.
iTerm2 keeps prepending the local `mosh …` job until you turn off Job Name in
Settings → Profiles → General → Title.

## tmux clipboard

OSC 52 is a terminal escape sequence (`ESC ] 52 ; c ; <base64> BEL`) that tells
the *local* emulator to put text on the system clipboard. The remote process
writes those bytes to its tty; SSH (or mosh) carries them unchanged; Warp or
iTerm2 on the Mac decodes them and calls `pbcopy`. No X11 forwarding, no
shared filesystem — the clipboard is the escape sequence. A trailing `?`
instead of the payload is a read: tmux asks the emulator for its current
clipboard and, if the emulator answers, loads it as a paste buffer.

Copying out is one clipboard: whatever you copy on the remote lands on the
macOS clipboard, whether it came from tmux copy mode (`y`, Enter, mouse drag)
or from an application that sets the clipboard itself (nvim, Grok, the other
agent CLIs). Both travel as OSC 52. Apps that see `$TMUX` wrap the sequence in
DCS (`ESC P tmux; … ESC \`); tmux 3.3+ drops that unless `allow-passthrough`
is enabled (`all`, so a window that isn't on screen still copies). That is
the `terminal.dcs-passthrough` finding in `grok doctor`.

Coming back the other way, use `Cmd-V` — the emulator types the Mac clipboard
as keystrokes, so no escape sequence has to survive the link. `prefix ]`
pastes tmux's own buffer after first requesting the Mac clipboard over OSC 52;
the two diverge only when you last copied in a different Mac app and the
client will not answer that query.

`Cmd-C` copies the emulator's *own* selection, not tmux's. With `mouse on`
tmux captures the drag, so the emulator has nothing selected — hold **⌥
Option** (iTerm2) or **Shift** (Warp) while dragging for a native selection.
Dragging without the modifier is the shorter path: tmux copies it and mirrors
it to the Mac for you.

Over mosh only the explicit `ESC ] 52 ; c ;` form survives, and OSC 52
*queries* are never answered, so `prefix ]` cannot read the Mac clipboard
there and falls back to the latest tmux buffer. Do not paper over the
selection byte with a terminfo `Ms` override: a capability that hardcodes `c`
and never references `%p1` expands to nothing and silently disables every
clipboard write tmux makes, application forwarding included.
`tests/test_tmux_osc52.py` holds the raw, copy-mode, and DCS-wrapped paths
down.

The Mac still has to accept the sequence. Warp's default is `deny` — copies
leave tmux and die at the emulator. `just config` on the Mac merges
`osc52_clipboard_access = "read_write"` into `~/.warp/settings.toml`. Until
that lands, set **Settings → Features → Terminal → OSC 52 clipboard access**
to **Read and write**. iTerm2 3.5+ needs **Settings → General → Selection →
Applications in terminal may access clipboard**.

`grok doctor` may still recommend `grok wrap ssh` over SSH: Grok does not
treat Warp as a verified OSC 52 sink, so it cannot confirm delivery. With
passthrough on and Warp's OSC 52 access enabled, wrap is optional. Reload
with `prefix r` after config sync; clients pick up terminal capability
changes on their next attach.

## tmux persistence

```bash
bash installers/installer.sh tmux
```

tmux-resurrect saves the layout and tmux-continuum restores it into a new
server. A systemd --user timer saves every 5 minutes whether or not a client is
attached — continuum's own save only runs while one is, which on a box of
detached agent sessions meant never. `prefix C-s` saves now and `prefix C-r`
restores. Pane history and agent processes are intentionally not restored.

## Shell helpers

Config sync installs two functions that locate the checkout through the
`~/.bash_aliases` symlink or `LINUX_UTILS_ROOT`:

```bash
linux-utils-install
linux-utils-install datacenter
linux-utils-install uv cargo
linux-utils-config
```

`linux-utils-install` fast-forwards `main`, then runs the installer (workstation
on Linux, Homebrew packages plus tracked config on macOS) when called without
targets, and reloads aliases. First-time setup:

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

iTerm2 and GNOME Terminal treat a dotted quad like `100.52.62.2` as a URL and
underline it. JetBrains Mono's x-height is tall enough that the underline cuts
through the digits and looks like strikethrough — in nvim, Grok, and a bare
shell, because none of them draw the line. In iTerm2, raise the last Font value
(line height) under Settings → Profiles → Text until the line sits below the
glyphs, and set Settings → Advanced → "Underline OSC 8 Hyperlinks" to No. GNOME
Terminal has no switch for URL matching; the same font is what the LazyVim
installer selects locally.

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
