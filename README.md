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
