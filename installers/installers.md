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
./installer.sh -u                       # uv only
./installer.sh -t                       # Tailscale only
```

### Command options

- `-a, --apt` — Install APT packages
- `-f, --flatpak` — Install Flatpak packages
- `-s, --snap` — Install Snap packages
- `-u, --uv` — Install [uv](https://github.com/astral-sh/uv) (Python package manager / toolchain)
- `-b, --bazelisk` — Install bazelisk (Bazel version manager)
- `-t, --tailscale` — Install [Tailscale](https://tailscale.com/) (VPN / mesh networking)
- `-c, --claude` — Install [Claude Code](https://docs.claude.com/en/docs/claude-code) CLI (Anthropic)
- `-x, --codex` — Install [Codex](https://github.com/openai/codex) CLI (OpenAI, via npm)
- `-l, --lazyvim` — Install [LazyVim](https://www.lazyvim.org/) (Neovim + starter config)
- `--all` — Install all package types
- `-h, --help` — Show help

## Architecture

### Shared library (`lib/common.sh`)

All installer scripts source `lib/common.sh`, which provides:

- **Color codes** — `RED`, `GREEN`, `YELLOW`, `BLUE`, `NC`
- **`print_header`**, **`print_success`**, **`print_warning`**, **`print_error`** — Consistent colored output
- **`is_installed <cmd>`** — Check if a command exists (`command -v` wrapper)
- **`require_file <path>`** — Exit with error if a file doesn't exist
- **`read_package_list <file>`** — Output non-empty, non-comment lines from a package list
- **`detect_arch`** — Output `amd64` or `arm64` for the current machine

### Registry pattern (`installer.sh`)

The orchestrator uses an `INSTALLERS` array to drive CLI flag parsing, help text, and execution:

```bash
INSTALLERS=(
    "apt|a|apt|APT Packages"
    "flatpak|f|flatpak|Flatpak Packages"
    ...
)
```

Format: `directory_name|short_flag|long_flag|display_name`

### Adding a new installer

1. Create `installers/<name>/install.sh` with:

   ```bash
   #!/bin/bash
   # shellcheck source=../lib/common.sh
   source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
   # ... installation logic ...
   ```

2. Add one line to the `INSTALLERS` array in `installer.sh`:

   ```bash
   "name|x|name|Display Name"
   ```

That's it. CLI flags, help text, and execution are all handled automatically.

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

### Claude Code

The Claude Code installer lives at [claude/install.sh](claude/install.sh). It uses the official Anthropic install script (`curl -fsSL https://claude.ai/install.sh | bash`). After install, run `claude` to start.

### Codex

The Codex installer lives at [codex/install.sh](codex/install.sh). It installs `@openai/codex` globally via npm. If npm is missing, Node.js LTS is first installed from NodeSource (Ubuntu's default node package is often outdated).

### LazyVim

The LazyVim installer lives at [lazyvim/install.sh](lazyvim/install.sh). It:

1. Installs Neovim and runtime deps via apt: `neovim`, `ripgrep`, `fd-find`, `build-essential`, `unzip`, `curl`, `git`, `xclip`. On Debian/Ubuntu `fd-find` ships its binary as `fdfind`; the installer symlinks `/usr/local/bin/fd` so Telescope and LazyVim find it.
2. Backs up any existing `~/.config/nvim`, `~/.local/share/nvim`, `~/.local/state/nvim`, and `~/.cache/nvim` with a timestamped suffix.
3. Clones the [LazyVim starter](https://github.com/LazyVim/starter) into `~/.config/nvim` and drops the starter's `.git` so you can `git init` your own.
4. Copies plugin specs from [lazyvim/plugins/](lazyvim/plugins/) into `~/.config/nvim/lua/plugins/`. Currently bundled: [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator) for seamless `C-h/j/k/l` between Neovim splits and tmux panes (pairs with bindings in [tmux/tmux.conf](../tmux/tmux.conf)).

**Note:** older Ubuntu LTS releases ship an older Neovim in apt. LazyVim wants `>=0.9` — if `nvim --version` reports older, grab a current build from the [Neovim releases](https://github.com/neovim/neovim/releases) page.

Not installed (handle separately): `lazygit` (optional, off by default in the starter), Node.js (use the codex installer or NodeSource on demand), a Nerd Font like JetBrainsMono.

## Notes

- All installers skip empty lines and comments (lines starting with `#`)
- The master installer runs `apt update` and `apt upgrade` before installing packages
- Each sub-installer can be run standalone (e.g., `bash installers/uv/install.sh`)
