# Installer

## Usage

On macOS, `installer.sh` (and `just install` / `just config`) routes to
[`macos/install.sh`](../macos/install.sh): Homebrew packages from
[`macos/brew.txt`](../macos/brew.txt), then the same tracked config as Linux
plus AeroSpace. Linux-only profiles and components are rejected there.

On Linux, profiles are named targets:

```bash
bash installers/installer.sh datacenter
bash installers/installer.sh workstation
```

Components use the same interface and can extend a profile:

```bash
bash installers/installer.sh uv cargo config
bash installers/installer.sh datacenter ollama
```

Inspect the interface without changing the machine:

```bash
bash installers/installer.sh list
bash installers/installer.sh plan datacenter
```

Append `--optionals` to install APT entries prefixed with `?`; otherwise they
are skipped without prompting. The initial sudo authentication remains active
for the full run.

### Output

Each component prints one line: installed, updated, already current, skipped,
or failed, with its time and what changed. Warnings a component raises appear
under its line. Full output goes to a per-step log under
`~/.local/state/linux-utils/install/<run>/` (the run's directory is printed up
front; the newest 20 runs are kept), and a failed step prints the tail of its
log and the log's path. Components run with stdin closed, so a prompt that
would hang behind the log fails instead; sudo still prompts on the terminal.

## Profiles

Profile manifests live in [`profiles/`](profiles/). They contain an ordered
component list and the APT manifest for that machine class.

### `datacenter`

The datacenter profile targets root-owned, headless GPU instances. It installs:

- headless APT packages and Docker with the NVIDIA container runtime
- uv and W&B
- Rustup, stable Rust, and the configured Cargo tools
- GitHub CLI, Claude Code, Codex, Grok Build, and Antigravity CLI
- Bazelisk, buildtools, and zoxide
- current stable Neovim, LazyVim, and Tree-sitter CLI
- tmux persistence and all tracked config

UID 0 commands run directly; `sudo` and `just` are not bootstrap dependencies.
The instance image remains responsible for NVIDIA drivers and CUDA. Homebrew,
desktop apps, OpenRGB, Ollama, Tailscale, and RealSense are excluded.

### `workstation`

The workstation profile installs base packages, Ubuntu's recommended NVIDIA
driver when NVIDIA hardware is present, Docker and its NVIDIA runtime,
Homebrew tools, local AI and robotics tools, editor, tmux, and config. It also
installs OpenSSH server and configures public-key-only login. Personal desktop
apps are explicit: `bash installers/installer.sh workstation desktop-apps`.
The first driver installation needs a reboot before `nvidia-smi` or Docker GPU
workloads can use it.

## Components

[`installer.sh`](installer.sh) contains the component registry and its execution
order. Each component owns one `installers/<name>/install.sh`; it can also be
run directly. The runner continues through independent component failures and
reports failure at the end.

A re-run should cost only its checks. Each component tests whether its thing is
installed and current before touching the network or sudo, and reports what it
changed with `print_installed`, `print_updated`, or `print_skipped`; one that
reports nothing reads as already current, and one that reports an error with
`print_error` fails even if it exits 0. Only an APT install refreshes the
package index, and only when the last `apt-get update` (Ubuntu's
`/var/lib/apt/periodic/update-success-stamp`) is over an hour old, so a
converged machine never runs `apt-get update`. The installer never upgrades
what is already installed; `updateall` does that.

Notable component contracts:

- `docker` reuses Docker when present and configures the NVIDIA runtime when
  NVIDIA GPU hardware is present, including before a newly installed driver is
  loaded after reboot.
- `nvidia-driver` uses `ubuntu-drivers install` to select Ubuntu's recommended
  stable desktop driver, and only while that driver is missing: run with it
  installed, `ubuntu-drivers install` swaps in a different series.
- `wandb` installs the W&B SDK and CLI in an isolated uv tool environment.
- `netron` installs the Netron model viewer from PyPI as a uv tool, the one
  build upstream ships for every arch: its Linux desktop builds are amd64-only
  and its Snap is discontinued. `netron model.onnx` serves the viewer on
  `localhost:8080`; `-b` opens a browser.
- `cargo` ensures Rustup and stable Rust, then installs
  [`cargo/cargo_packages.txt`](cargo/cargo_packages.txt).
- `gh` installs Ubuntu's packaged GitHub CLI without adding an external APT
  repository or signing key, then the `gh-stack` extension. Installing an
  extension needs an authenticated `gh`, so on a machine that has not run
  `gh auth login` the component warns with the command to finish it.
- `lazyvim` uses Homebrew on a workstation. As root it installs Neovim's
  official Linux release under `/opt`, Tree-sitter CLI through NodeSource npm, and the
  LazyVim starter under `$HOME/.config/nvim`.
- `tmux` uses Homebrew for a workstation and APT as root, then installs
  tmux-resurrect and tmux-continuum.
- `config` links or merges Bash, agent, Neovim, and tmux config into `$HOME`,
  removes Help and App Center from GNOME favorites, applies power and kernel
  `sysctl` defaults, and installs the key-only SSH daemon policy. On macOS it
  also links AeroSpace; GNOME, power, kernel, and SSH server steps skip
  themselves.

## Package manifests

| Type | Files | Entry format |
| --- | --- | --- |
| APT | [`apt/`](apt/) | `package [\| ppa:user/repo] # description` |
| Cargo | [`cargo/cargo_packages.txt`](cargo/cargo_packages.txt) | `crate[:binary] # description` |
| Flatpak | [`flatpak/flatpaks.txt`](flatpak/flatpaks.txt) | `app.id # description` |
| Homebrew | [`homebrew/brew_packages.txt`](homebrew/brew_packages.txt) | `package [--cask] # description` |
| Desktop apps | [`desktop-apps/`](desktop-apps/) | APT, Flatpak, and Snap manifests |

Blank lines and comments are ignored. APT, Flatpak, Snap, and Homebrew batch
missing packages when possible.

## Adding a component

1. Add `installers/<name>/install.sh`.
2. Add `name|label|script|uses-sudo` to `COMPONENTS` in
   [`installer.sh`](installer.sh).
3. Add the name to any profile that owns it and test the resolved plan.

Shared shell helpers live in [`lib/common.sh`](lib/common.sh), which also loads
[`lib/packages.sh`](lib/packages.sh), so one `source` line is all a component
needs. The helpers worth reaching for:

| Helper | Use |
| --- | --- |
| `run_as_root` | System mutations; root runs directly, others go through `sudo` |
| `print_installed` / `print_updated` / `print_skipped` | Report what the step changed |
| `install_from_web_script` | A vendor's `curl \| sh` installer |
| `install_batch` | A package set, retried one at a time if the transaction fails |
| `missing_apt_packages` / `apt_install` | APT packages not yet installed; install them |
| `find_brew` | Homebrew off a non-login PATH |
| `configure_shell_rcs` | A line added to `.profile`/`.bashrc`/`.zprofile` |

## Config sync

Run `bash installers/installer.sh config`. Symlink targets are backed up before
replacement. Claude and Antigravity JSON and Codex/Grok TOML are merged instead of linked
because those tools rewrite their config; tracked keys win and machine-local
keys remain. One injector, [`scripts/inject-config`](../scripts/inject-config),
handles both formats and picks between them by file suffix. Preview only the
config layer with:

```bash
bash installers/config/install.sh --dry-run
```
