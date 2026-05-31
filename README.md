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
- **Flatpak**: Sandboxed applications from Flathub
- **Snap**: Universal packages from Snap Store
- **Homebrew**: The missing package manager for Linux (installed via the official script; see [installers/installers.md](installers/installers.md))
- **uv**: Python toolchain / package manager (installed via the official script; see [installers/installers.md](installers/installers.md))
- **Tailscale**: VPN / mesh networking (installed via the official script; see [installers/installers.md](installers/installers.md))

See [installers/installers.md](installers/installers.md) for detailed documentation and package lists.

## Synced config (`installers/installer.sh -C`)

The `-C, --config` flag runs `installers/config/install.sh`, which symlinks tracked config files into their user-config locations so edits in either place stay in sync. Currently covers:

- **Shared LLM skills** (`skills/`): `new-branch`, `pr` -> `~/.claude/skills/` and `~/.agents/skills/`
- **Shared agent scripts** (`scripts/`): `agent-fanout`, `statusline-worktree` -> `~/.agents/scripts/`
- **Claude Code** (`claude/`): `settings.json` -> `~/.claude/settings.json`
- **Codex** (`codex/`): `config.toml` -> `~/.codex/config.toml`
- **Neovim** (`installers/lazyvim/plugins/`): LazyVim plugin specs -> `~/.config/nvim/lua/plugins/`
- **tmux** (`tmux/`): `tmux.conf` -> `~/.config/tmux/tmux.conf`

Install the Claude CLI with `installers/installer.sh -c`, Codex with `-x`, and Neovim with `-l`, then run `installers/installer.sh -C` (or `bash installers/config/install.sh --dry-run` to preview). Conflicting non-symlink files at the target are backed up with a timestamp suffix.

## Shell helpers (`.bash_aliases`)

Optional aliases and functions (CUDA/TensorRT paths, CPU governor helpers, `unzipall`, GNOME/VS Code theme toggle, and more). To use them, source the file from your shell config, for example:

```bash
# In ~/.bashrc
source /path/to/linux-utils/.bash_aliases
```

## VS Code extensions helper

See [vscode/install_vscode_extensions.sh](vscode/install_vscode_extensions.sh) for a small helper that installs extensions listed in a VS Code `extensions.json` recommendations file.

## Static analysis

This project uses [pre-commit](https://pre-commit.com/) with [shellcheck](https://www.shellcheck.net/) and [markdownlint](https://github.com/DavidAnson/markdownlint). Install and enable the hooks:

```bash
pip install pre-commit
pre-commit install
```
