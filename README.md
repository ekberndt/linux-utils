# linux-utils

`linux-utils` is a collection of utilities built for (mostly Ubuntu) Linux systems, with an emphasis on machine learning.

## Package Installers

The `installers/` directory contains automated package installation scripts for multiple package managers:

### Supported package managers

- **APT**: System packages via Ubuntu/Debian package manager
- **Flatpak**: Sandboxed applications from Flathub
- **Snap**: Universal packages from Snap Store
- **uv**: Python toolchain / package manager (installed via the official script; see [installers/installers.md](installers/installers.md))
- **Tailscale**: VPN / mesh networking (installed via the official script; see [installers/installers.md](installers/installers.md))

See [installers/installers.md](installers/installers.md) for detailed documentation and package lists.

## Synced config (`installers/installer.sh -C`)

The `-C, --config` flag runs `installers/config/install.sh`, which symlinks tracked config files into their user-config locations so edits in either place stay in sync. Currently covers:

- **Shared LLM skills** (`skills/`): `new-branch`, `pr` -> `~/.claude/skills/` and `~/.codex/skills/`
- **Shared scripts** (`scripts/`): `agent-fanout`, `statusline-worktree` -> tool-specific script names under `~/.claude/scripts/` and `~/.codex/scripts/`
- **Claude Code** (`claude/`): `settings.json` -> `~/.claude/settings.json`
- **Codex** (`codex/`): `config.toml` -> `~/.codex/config.toml`
- **Neovim** (`installers/lazyvim/plugins/`): LazyVim plugin specs -> `~/.config/nvim/lua/plugins/`
- **tmux** (`tmux/`): `tmux.conf` -> `~/.cache/tmux/tmux.conf`

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
