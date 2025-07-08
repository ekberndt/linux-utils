# Package Installers

Guide to using the package installers in the `installers/` directory.

## Usage

### Install All Packages

```bash
./installer.sh --all
```

### Install Specific Package Types

```bash
./installer.sh -a -f                    # APT and Flatpak only
./installer.sh --apt --snap             # APT and Snap only
```

### Command Options

- `-a, --apt` - Install APT packages
- `-f, --flatpak` - Install Flatpak packages
- `-s, --snap` - Install Snap packages
- `--all` - Install all package types
- `-h, --help` - Show help

## Package Lists

### APT Packages

System packages via Ubuntu/Debian package manager. To modify the install list, edit [apt/apt_packages.txt](apt/apt_packages.txt).

**Format**: `PACKAGE_NAME # DESCRIPTION`

**Note**: If a package requires a PPA, it can be specified with `PACKAGE_NAME [|ppa:USER/REPO] # DESCRIPTION`

### Flatpak Packages

Sandboxed desktop applications from Flathub remote. To modify the install list, edit [flatpak/flatpaks.txt](flatpak/flatpaks.txt).

**Format**: `APP_ID # DESCRIPTION`

**Note**: Only Flathub remote is supported. All packages are installed from `flathub`.

### Snap Packages

Universal packages from Snap Store. To modify the install list, edit [snap/snaps.txt](snap/snaps.txt).

**Format**: `PACKAGE_NAME # DESCRIPTION`

**Note**: Add `--classic` after the package name for classic confinement if required.

## Notes

- All installers skip empty lines and comments (lines starting with #)
- The master installer updates the system before installing packages
