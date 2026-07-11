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
./installer.sh --homebrew               # Homebrew only
./installer.sh -u                       # uv only
./installer.sh -t                       # Tailscale only
./installer.sh -r                       # Cargo packages only
```

### Command options

- `-a, --apt` — Install APT packages
- `-f, --flatpak` — Install Flatpak packages
- `-s, --snap` — Install Snap packages
- `-H, --homebrew` — Install [Homebrew](https://brew.sh/) for Linux
- `-u, --uv` — Install [uv](https://github.com/astral-sh/uv) (Python package manager / toolchain)
- `-b, --bazelisk` — Install bazelisk (Bazel version manager)
- `-t, --tailscale` — Install [Tailscale](https://tailscale.com/) (VPN / mesh networking)
- `-c, --claude` — Install [Claude Code](https://docs.claude.com/en/docs/claude-code) CLI (Anthropic)
- `-x, --codex` — Install [Codex](https://github.com/openai/codex) CLI (OpenAI, via npm)
- `-r, --cargo` — Install Cargo packages via Rustup
- `-l, --lazyvim` — Install [LazyVim](https://www.lazyvim.org/) (Neovim + starter config)
- `-C, --config` — Sync tracked config files (Claude, Codex, shared scripts, skills, Neovim plugin specs, tmux) via symlinks; skips the `apt update` phase when run alone
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

Before running the selected installers, `installer.sh` runs `sudo apt-get update` (package index only — not a full system upgrade).

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

### Cargo packages

Rust binaries installed via Cargo. To modify the install list, edit [cargo/cargo_packages.txt](cargo/cargo_packages.txt).

**Format**: `PACKAGE_NAME # DESCRIPTION`

The Cargo installer ensures Rustup and the stable Rust toolchain are available, then runs `cargo install <package>` for each listed package. It also adds `~/.cargo/bin` to `~/.profile` and `~/.bashrc` so future shells can find the installed binaries.

### Homebrew

The Homebrew installer lives at [homebrew/install.sh](homebrew/install.sh). It first installs the Debian/Ubuntu build prerequisites (`build-essential`, `procps`, `curl`, `file`, `git`), then runs the official install script with `NONINTERACTIVE=1` so it works under the dashboard. It refuses to run as root (Homebrew does too).

Homebrew installs to `/home/linuxbrew/.linuxbrew` by default and is not on `PATH` for new shells until its `shellenv` is sourced. The installer verifies a runnable `brew` binary from standard Homebrew prefixes, then adds the appropriate shellenv line to `~/.profile` and `~/.bashrc` so future shells can find it.

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

1. Installs Neovim and runtime deps via apt: `neovim`, `ripgrep`, `fd-find`, `build-essential`, `unzip`, `curl`, `git`, `fontconfig`, `xclip`. On Debian/Ubuntu `fd-find` ships its binary as `fdfind`; the installer symlinks `/usr/local/bin/fd` so Telescope and LazyVim find it.
2. Backs up any existing `~/.config/nvim`, `~/.local/share/nvim`, `~/.local/state/nvim`, and `~/.cache/nvim` with a timestamped suffix.
3. Clones the [LazyVim starter](https://github.com/LazyVim/starter) into `~/.config/nvim` and drops the starter's `.git` so you can `git init` your own.
4. Symlinks plugin specs from [lazyvim/plugins/](lazyvim/plugins/) into `~/.config/nvim/lua/plugins/`. Currently bundled: [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator) for seamless `C-h/j/k/l` between Neovim splits and tmux panes (pairs with bindings in [tmux/tmux.conf](../tmux/tmux.conf)). The universal `--config` sync re-applies the same symlinks idempotently.

It also installs the Homebrew cask `font-jetbrains-mono-nerd-font` and selects it for GNOME Terminal when possible; run `--homebrew` first or use `--all`.

**Note:** older Ubuntu LTS releases ship an older Neovim in apt. LazyVim wants `>=0.9` — if `nvim --version` reports older, grab a current build from the [Neovim releases](https://github.com/neovim/neovim/releases) page.

Not installed (handle separately): `lazygit` (optional, off by default in the starter), Node.js (use the codex installer or NodeSource on demand).

### Config sync

The config installer lives at [config/install.sh](config/install.sh). It is invoked as `installer.sh -C` / `--config` and orchestrates per-tool sync scripts. Most tracked config is symlinked into its user-config location; the two settings files that their tools rewrite at runtime are instead **merged** into real files (see "Merged settings" below).

Structure mirrors the per-tool installer pattern:

```text
installers/config/
  install.sh   # orchestrator: runs each tool in TOOLS
  lib.sh       # shared link helpers: apply_link (mkdir + symlink + backup), apply_skill_links
  bash.sh      # .bash_aliases -> ~/.bash_aliases + ~/.bashrc source block
  agents.sh    # shared scripts/** -> ~/.agents/ and remove per-tool script dirs
  claude.sh    # claude/settings.json (merged) + skills/** -> ~/.claude/
  codex.sh     # codex/config.toml (merged) -> ~/.codex/, skills/** -> ~/.agents/skills/
  nvim.sh      # installers/lazyvim/plugins/*.lua               -> ~/.config/nvim/lua/plugins/
  tmux.sh      # tmux/tmux.conf                               -> ~/.config/tmux/tmux.conf
```

Each directory under [../skills/](../skills/) is symlinked whole into `~/.claude/skills/` and Codex's user-scope `~/.agents/skills/`, while [../scripts/](../scripts/) is linked once into `~/.agents/scripts/`. Claude Code's `statusLine.command` points at `~/.agents/scripts/statusline-worktree`, while Codex reads its TUI status-line order from [../codex/config.toml](../codex/config.toml). `agent-fanout --codex` or `agent-fanout --claude` chooses the agent. Add a skill by creating `skills/<name>/SKILL.md`, or a tool by dropping a `<name>.sh` that sources `lib.sh` next to `install.sh` and appending `<name>` to `TOOLS`.

**Merged settings.** `~/.claude/settings.json` and `~/.codex/config.toml` are not symlinked — Claude Code and Codex rewrite those files at runtime, which would either clobber the repo (via a symlink) or strand machine-local keys. Instead [../scripts/inject-claude-config](../scripts/inject-claude-config) and [../scripts/inject-codex-config](../scripts/inject-codex-config) overlay the repo's keys onto the existing file: repo keys win, your own keys (and Codex tables like `[mcp_servers.*]`) are preserved, and the file is left as a normal file the tool can keep editing. Both back up the previous file before any change and are no-ops when nothing meaningful differs (the Claude one compares parsed JSON, so Claude's key reordering doesn't trigger churn). Note: the Claude injector only adds and overrides, so removing a key from the repo does not remove it from your live `settings.json`.

Conflicting non-symlink files at a symlink target are backed up with a `.bak.<timestamp>` suffix (one timestamp per orchestrator run, shared across all tools); the merged settings files are backed up the same way. Pass `--dry-run` to preview without making changes:

```bash
bash installers/config/install.sh --dry-run
```

Each per-tool script is also runnable standalone:

```bash
DRY_RUN=true bash installers/config/claude.sh
```

The top-level orchestrator skips its `sudo apt-get update` step when only `--config` is selected, so running config-only sync is fast and password-free.

## Notes

- All installers skip empty lines and comments (lines starting with `#`)
- The master installer runs `apt-get update` before installing packages (index refresh only)
- APT / Flatpak / Snap installers batch missing packages into one transaction when possible
- Each sub-installer can be run standalone (e.g., `bash installers/uv/install.sh`)
