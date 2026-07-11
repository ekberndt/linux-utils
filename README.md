# linux-utils

`linux-utils` is a collection of utilities built for (mostly Ubuntu) Linux systems, with an emphasis on machine learning.

## Task runner (`just`)

The repo ships a [`justfile`](justfile) of convenience recipes. Install [`just`](https://github.com/casey/just) (it's in the apt list, so `installers/installer.sh -a` covers it) and run `just` to list recipes:

```bash
just                 # list all recipes
just install         # run the master installer with --all
just install -a -f   # forward flags to installer.sh (APT + Flatpak only)
just config          # sync tracked config via symlinks (installer.sh --config)
just lint            # run all pre-commit hooks over the repo
```

`install` is a thin passthrough to `installers/installer.sh`, so any flag that script accepts works (`just install --help`).

## Package Installers

The `installers/` directory contains automated package installation scripts for multiple package managers:

### Supported package managers

- **APT**: System packages via Ubuntu/Debian package manager
- **Docker Engine**: Docker's official Engine, CLI, containerd, Buildx, and Compose packages for Ubuntu
- **Flatpak**: Sandboxed applications from Flathub
- **Snap**: Universal packages from Snap Store
- **Homebrew**: The missing package manager for Linux (installed via the official script; see [installers/installers.md](installers/installers.md))
- **uv**: Python toolchain / package manager (installed via the official script; see [installers/installers.md](installers/installers.md))
- **Tailscale**: VPN / mesh networking (installed via the official script; see [installers/installers.md](installers/installers.md))
- **Ollama**: Local LLM runtime (official install script; `installers/installer.sh -o`)

See [installers/installers.md](installers/installers.md) for detailed documentation and package lists.

## Synced config (`installers/installer.sh -C`)

The `-C, --config` flag runs `installers/config/install.sh`, which syncs tracked config into their user-config locations. Most files are symlinked so edits in either place stay in sync; the two settings files that their tools rewrite at runtime (`settings.json`, `config.toml`) are instead **merged** into real files so your machine-local keys survive and the tool never writes back into the repo. Currently covers:

- **Bash aliases** (`.bash_aliases`): aliases/functions -> `~/.bash_aliases`, with an idempotent `~/.bashrc` source block (symlink)
- **Shared LLM skills** (`skills/`): every skill directory -> `~/.claude/skills/` and `~/.agents/skills/` (symlink)
- **Shared agent scripts** (`scripts/`): `agent-fanout`, `statusline-worktree` -> `~/.agents/scripts/` (symlink); Claude Code uses `statusline-worktree` for its command status line
- **Claude Code** (`claude/`): `settings.json` merged into `~/.claude/settings.json` (repo keys authoritative, your own keys preserved)
- **Codex** (`codex/`): `config.toml` merged into `~/.codex/config.toml` (repo keys authoritative, your own keys and tables preserved), including the shared TUI status-line segment order
- **Neovim** (`installers/lazyvim/plugins/`): LazyVim plugin specs -> `~/.config/nvim/lua/plugins/` (symlink)
- **tmux** (`tmux/`): `tmux.conf` -> `~/.config/tmux/tmux.conf` (symlink)

Install the Claude CLI with `installers/installer.sh -c`, Codex with `-x`, and Neovim with `-l`, then run `installers/installer.sh -C` (or `bash installers/config/install.sh --dry-run` to preview). Conflicting non-symlink files at a symlink target are backed up with a timestamp suffix; the merged settings files are likewise backed up before each change.

## Bash aliases (`.bash_aliases`)

Optional aliases and functions (including `vim='nvim'`, `updateall`/`update-all` for Ubuntu package managers and global tools, CUDA/TensorRT paths, CPU governor helpers, `unzipall`, GNOME/VS Code theme toggle, `coderemote`, and more). Run `installers/installer.sh -C` to link the tracked file into `~/.bash_aliases` and ensure Bash loads it from `~/.bashrc`.

## VS Code extensions helper

See [vscode/install_vscode_extensions.sh](vscode/install_vscode_extensions.sh) for a small helper that installs extensions listed in a VS Code `extensions.json` recommendations file.

## Static analysis

This project uses [pre-commit](https://pre-commit.com/) with [shellcheck](https://www.shellcheck.net/) and [markdownlint](https://github.com/DavidAnson/markdownlint). Install and enable the hooks:

```bash
pip install pre-commit
pre-commit install
```
