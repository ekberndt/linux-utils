# Installer

## Usage

`just install` installs what is missing and upgrades what is installed; there
is no separate update command. On macOS, `installer.sh` (and `just install` /
`just config`) routes to [`macos/install.sh`](../macos/install.sh): Homebrew
packages from [`macos/brew.txt`](../macos/brew.txt) and an upgrade of
everything Homebrew holds, an upgrade of every cross-platform component already
installed (uv, the agent CLIs, zoxide, Rust and Cargo, and the global npm,
pnpm, pip, and pipx packages), then the same tracked config as Linux plus
AeroSpace. Naming a cross-platform component installs it. Linux-only profiles
and components are rejected there.

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
- uv and W&B, and upgrades of global npm, pnpm, pip, and pipx packages
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
Homebrew tools, local AI and robotics tools, editor, tmux, and config, and
upgrades snaps, Flatpak apps, and global npm, pnpm, pip, and pipx packages. It
also installs OpenSSH server and configures public-key-only login. Personal desktop
apps are explicit: `bash installers/installer.sh workstation desktop-apps`.
The first driver installation needs a reboot before `nvidia-smi` or Docker GPU
workloads can use it.

## Components

[`installer.sh`](installer.sh) contains the component registry and its execution
order. Each component owns one `installers/<name>/install.sh`; it can also be
run directly. The runner continues through independent component failures and
reports failure at the end.

Each component installs its thing when missing and upgrades it when installed.
A re-run with nothing to upgrade should cost only its checks: a component asks
cheaply, and without sudo, whether anything is outdated (an `apt-get -s`
simulation, `brew outdated`, `snap refresh --list`, a version comparison)
before it upgrades, and asks again after: what left the outdated list is
reported with `print_updated` (old -> new where the manager says), and what a
manager declined while exiting 0 (a hold, a pin) is a warning. Installs report
with `print_installed`, and an inapplicable step with `print_skipped`; one
that reports nothing reads as already current, and one that reports an error
with `print_error` fails even if it exits 0. A check that cannot reach its
index fails rather than reading as current; pip, which reads an unreachable
index as nothing newer, is asked for its own versions to tell the two apart.

Package indexes follow an hourly rule: `apt-get update` runs only when the last
one (Ubuntu's `/var/lib/apt/periodic/update-success-stamp`) is over an hour
old, and `brew update` only when Homebrew's own stamp, its repository's
`FETCH_HEAD`, is. So a re-run within the hour touches neither. A refresh in
which any source fails to fetch fails the step and leaves the stamp alone
(`apt-get update --error-on=any`, apt 2.1.16 or Ubuntu 22.04 and later).

Notable component contracts:

- `apt` installs the profile's manifest, then runs `apt-get upgrade` and
  `apt-get autoremove` over the whole machine. Like `apt-get upgrade`, it
  leaves held-back packages (an upgrade that needs a new package or a removal)
  for a manual `apt-get full-upgrade`. dpkg keeps a locally edited conffile
  rather than prompting.
- `snap` and `flatpak` install nothing (`desktop-apps` does); they refresh
  every snap and Flatpak installed, and `flatpak` updates both the user and the
  system scope. `homebrew` upgrades everything brew holds, not only its
  manifest.
- `npm`, `pnpm`, `pip`, and `pipx` install nothing; each upgrades the global
  (or `--user`) packages its manager already holds, as `npm update -g`,
  `pnpm update -g`, `pip install --user --upgrade`, and `pipx upgrade-all` do,
  and does nothing on a machine without that manager. `pip` skips itself while
  a virtualenv is active.
- `uv` runs `uv self update` for a standalone install and upgrades every uv
  tool, W&B among them. The agent CLIs (`claude`, `codex`, `grok`, `agy`,
  `opencode`) run their own updaters. Ollama and zoxide have none, so their
  components re-run the vendor script when the latest GitHub release is newer
  than the installed version; `bazelisk` and `buildtools` replace their
  binaries the same way.
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
- `cargo` ensures Rustup and stable Rust and runs `rustup update` when
  `rustup check` finds one. It installs what is missing from
  [`cargo/cargo_packages.txt`](cargo/cargo_packages.txt), leaving a binary
  another manager installed to it, then runs `cargo install` once per crate
  cargo installed from crates.io, with the options it was installed with
  (features, a `--version` pin). `cargo install` rebuilds only a crate with a
  newer release; git and path installs are left alone.
- `gh` installs Ubuntu's packaged GitHub CLI without adding an external APT
  repository or signing key (the `apt` component upgrades it), upgrades
  installed extensions, then installs the `gh-stack` extension. Installing an
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
| Flatpak | [`desktop-apps/flatpaks.txt`](desktop-apps/flatpaks.txt) | `app.id # description` |
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
| `install_or_update` | A vendor's `curl \| sh` install, or the CLI's own updater once installed |
| `reinstall_if_outdated` | The updater for a CLI without one: compare with the latest GitHub release |
| `update_cli` | Run an updater and report the version it moved to |
| `report_upgraded` | Report an upgrade by asking the manager what is still outdated |
| `report_version_changes` | Report what moved between two `name version` listings |
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
