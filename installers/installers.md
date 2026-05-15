# Package Installers

Guide to using the package installers in the `installers/` directory.

## Usage

### Install all packages

```bash
./installer.sh --all
```

### Install specific package types

```bash
./installer.sh -a -f                    # APT and Flatpak only
./installer.sh --apt --snap             # APT and Snap only
./installer.sh -u                     # uv only (see below)
./installer.sh -t                     # Tailscale only (see below)
```

### Command options

- `-a, --apt` — Install APT packages
- `-f, --flatpak` — Install Flatpak packages
- `-s, --snap` — Install Snap packages
- `-u, --uv` — Install [uv](https://github.com/astral-sh/uv) (Python package manager / toolchain)
- `-b, --bazelisk` - Install bazelisk (Bazel version manager)
- `-t, --tailscale` — Install [Tailscale](https://tailscale.com/) (VPN / mesh networking)
- `--all` — Install all package types (APT, Flatpak, Snap, uv, Tailscale)
- `-h, --help` — Show help

## System update

Before running the selected installers, `installer.sh` runs `sudo apt update && sudo apt upgrade -y`.

## Package lists

### APT packages

System packages via Ubuntu/Debian package manager. To modify the install list, edit [apt/apt_packages.txt](apt/apt_packages.txt).

**Format**: `PACKAGE_NAME # DESCRIPTION`

**Note**: If a package requires a PPA, it can be specified with `PACKAGE_NAME [|ppa:USER/REPO] # DESCRIPTION`

### Flatpak packages

Sandboxed desktop applications from Flathub remote. To modify the install list, edit [flatpak/flatpaks.txt](flatpak/flatpaks.txt).

**Format**: `APP_ID # DESCRIPTION`

**Note**: Only Flathub remote is supported. All packages are installed from `flathub`.

### Snap packages

Universal packages from Snap Store. To modify the install list, edit [snap/snaps.txt](snap/snaps.txt).

**Format**: `PACKAGE_NAME # DESCRIPTION`

**Note**: Add `--classic` after the package name for classic confinement if required.

### uv

The uv installer lives at [uv/install.sh](uv/install.sh). It uses the official Astral install script (`curl … | sh`). Review [https://github.com/astral-sh/uv](https://github.com/astral-sh/uv) if you prefer a pinned or offline install.

### Tailscale

The Tailscale installer lives at [tailscale/install.sh](tailscale/install.sh). It uses the official install script (`curl -fsSL https://tailscale.com/install.sh | sh`), which detects the distro and configures the appropriate package repo. After install, run `sudo tailscale up` to authenticate and join your tailnet.

### Bazelisk

Bazel version manager installed from the latest GitHub release binary. Installed to `/usr/local/bin/bazelisk`.

## Notes

- All installers skip empty lines and comments (lines starting with `#`)
- The master installer runs `apt update` and `apt upgrade` before installing packages
