# linux-utils

`linux-utils` is a collection of utilities built for (mostly Ubuntu) Linux systems, with an emphasis on machine learning.

## Task runner (`just`)

The repo ships a [`justfile`](justfile) of convenience recipes. Install [`just`](https://github.com/casey/just) via the **Cargo** installer (`just install --cargo` / `installers/installer.sh -r`) — it is not in Ubuntu 22.04 apt — then:

```bash
just                 # list all recipes
just install         # run the master installer with --all
just install -a -f   # forward flags to installer.sh (APT + Flatpak only)
just install --all --optionals   # also auto-install apt optional packages
just config          # sync tracked config via symlinks (installer.sh --config)
just test            # package-list / stream-filter unit tests
just lint            # pre-commit hooks + unit tests
```

`install` is a thin passthrough to `installers/installer.sh`, so any flag that script accepts works (`just install --help`).

## Package Installers

The `installers/` directory contains automated package installation scripts for multiple package managers and tools.

### Supported installers

- **APT**: System packages via Ubuntu/Debian (`apt-get`)
- **Docker Engine**: Official Engine, CLI, containerd, Buildx, and Compose
- **Flatpak**: Sandboxed apps from Flathub (user scope)
- **Snap**: Snap Store packages
- **Homebrew**: Official Linuxbrew install script
- **uv**: Python toolchain / package manager
- **Tailscale**: VPN / mesh networking
- **bazelisk / buildtools**: Bazel tooling
- **GitHub CLI (`gh`)**: Official GitHub apt repository
- **Claude Code / Codex / Grok Build**: Agent CLIs (Anthropic, OpenAI, xAI)
- **Ollama**: Local LLM runtime (`installers/installer.sh -o`)
- **Cargo**: Rustup + crates (`just`, `dust`, `just-lsp`, …)
- **zoxide**: Smarter `cd` (`z` / `zi`) via official install script + Bash init
- **OpenRGB (`-R`)**: RGB AppImage in `~/Applications` + `/usr/local/bin/openrgb` wrapper (SHA-256 pinned; NVIDIA FE)
- **LazyVim**: Neovim + starter config
- **Config sync (`-C`)**: Symlink/merge tracked configs

See [installers/installers.md](installers/installers.md) for flags, package lists, and architecture notes.

### Optional APT packages

Lines in `apt_packages.txt` prefixed with `?` are optional. Under `just install` (non-interactive) they are **skipped** unless you pass `--optionals` or set `INSTALLER_INSTALL_OPTIONALS=1`. Interactive runs of `installers/apt/install.sh` still prompt on a real TTY.

## Synced config (`installers/installer.sh -C`)

The `-C, --config` flag runs `installers/config/install.sh`, which syncs tracked config into their user-config locations. Most files are symlinked so edits in either place stay in sync; the settings files that tools rewrite at runtime (`settings.json`, `config.toml`) are instead **merged** into real files so your machine-local keys survive and the tool never writes back into the repo. Currently covers:

- **Bash aliases** (`.bash_aliases`): aliases/functions -> `~/.bash_aliases`, with an idempotent `~/.bashrc` source block (symlink)
- **Shared LLM skills** (`skills/`): every skill directory -> `~/.claude/skills/` and `~/.agents/skills/` (symlink; Grok reads the latter via its managed `[skills].paths`)
- **Shared agent scripts** (`scripts/`): `agent-fanout`, `statusline-worktree` -> `~/.agents/scripts/` (symlink); Claude Code uses `statusline-worktree` for its command status line
- **Claude Code** (`claude/`): `settings.json` merged into `~/.claude/settings.json` (repo keys authoritative, your own keys preserved)
- **Codex** (`codex/`): `config.toml` merged into `~/.codex/config.toml` (repo keys authoritative, your own keys and tables preserved), including the shared TUI status-line segment order
- **Grok Build** (`grok/`): `config.toml` merged into `~/.grok/config.toml` (repo keys authoritative; prefers `~/.agents/skills`)
- **Neovim** (`installers/lazyvim/plugins/`): LazyVim plugin specs -> `~/.config/nvim/lua/plugins/` (symlink)
- **tmux** (`tmux/`): `tmux.conf` -> `~/.config/tmux/tmux.conf` (symlink)

Install the Claude CLI with `installers/installer.sh -c`, Codex with `-x`, Grok Build with `-k`, and Neovim with `-l`, then run `installers/installer.sh -C` (or `bash installers/config/install.sh --dry-run` to preview). Conflicting non-symlink files at a symlink target are backed up with a timestamp suffix; the merged settings files are likewise backed up before each change.

## Bash aliases (`.bash_aliases`)

Optional aliases and functions (including `vim='nvim'`, `updateall`/`update-all` for Ubuntu package managers and global tools, CUDA/TensorRT paths, CPU governor helpers, `unzipall`, GNOME/VS Code theme toggle, `coderemote`, and more). Run `installers/installer.sh -C` to link the tracked file into `~/.bash_aliases` and ensure Bash loads it from `~/.bashrc`.

`just config` only updates files (symlink + bashrc block). It runs in a subprocess, so it **cannot** load aliases into your current shell. After `just config`, either open a new shell or:

```bash
source ~/.bash_aliases
# or, once the helpers are loaded once:
linux-utils-config    # just config + source ~/.bash_aliases in this shell
```

### `linux-utils-install` / `linux-utils-config` (from anywhere)

After config sync, `~/.bash_aliases` is a symlink into this repo. These shell functions use that link (or `LINUX_UTILS_ROOT`) to find the checkout:

```bash
linux-utils-install                 # pull main, just install --all, re-source aliases
linux-utils-install --apt --cargo   # same, with scoped installer flags
linux-utils-config                  # just config, then source aliases in this shell
LINUX_UTILS_ROOT=~/src/linux-utils linux-utils-install --config
```

Requires `git` and `just` on `PATH`. First-time bootstrap: `just config && source ~/.bash_aliases`.

## VS Code extensions helper

See [vscode/install_vscode_extensions.sh](vscode/install_vscode_extensions.sh) for a small helper that installs extensions listed in a VS Code `extensions.json` recommendations file. Not wired into the master installer registry; run standalone.

## Chassis RGB (`scripts/rgb`)

Full control of motherboard / RAM / ARGB / NZXT AIO + HUE+ strip / **NVIDIA Founders Edition GPU** (e.g. RTX 4090 FE) without vendor GUIs.

```bash
# OpenRGB binary (AppImage → ~/Applications; PATH wrapper → /usr/local/bin/openrgb)
just install --openrgb
# or: bash installers/installer.sh -R

# rgb helper: udev (group rgb), /usr/local/bin/rgb, boot-off service
just rgb install

# day-to-day (after re-login so group "rgb" applies)
rgb off
rgb on ff0044
rgb status
```

OpenRGB is installed via `installers/openrgb/` (`just install -R`): the AppImage lives in **`~/Applications/OpenRGB.AppImage`** (normal AppImage location); **`/usr/local/bin/openrgb`** is only a thin wrapper that `exec`s that file with `--appimage-extract-and-run`. The `rgb` script does not download OpenRGB. Optional: `pipx install liquidctl` for NZXT HUE+ strip hard-off.

## Static analysis

This project uses [pre-commit](https://pre-commit.com/) with [shellcheck](https://www.shellcheck.net/) and [markdownlint](https://github.com/DavidAnson/markdownlint). Install and enable the hooks:

```bash
pip install pre-commit
pre-commit install
just lint
```
