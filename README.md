# linux-utils

`linux-utils` is a collection of utilities for built for (mostly ubuntu) linux systems with an emphasis on machine learning.

## Package Installers

The `installers/` directory contains automated package installation scripts for multiple package managers:

### Supported Package Managers

- **APT**: System packages via Ubuntu/Debian package manager
- **Flatpak**: Sandboxed applications from Flathub
- **Snap**: Universal packages from Snap Store

See [installers](installers/installers.md) for detailed documentation and package lists.

## Static Analysis

This project uses [markdownlint](https://github.com/DavidAnson/markdownlint) and [shellcheck](https://www.shellcheck.net/). Install them as follows:

```bash
npm install markdownlint-cli2 --global
sudo apt install shellcheck
```

The linters can be run with `make lint`.
