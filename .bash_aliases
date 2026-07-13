# shellcheck shell=bash
# Description: This file contains aliases and functions to be used as commands in the terminal.

alias vim='nvim'

# Sources the setup.bash file for ROS2 Humble.
alias shumble='source /opt/ros/humble/setup.bash'
# Sources the install/setup.bash file for the current ROS2 workspace.
alias si='source install/setup.bash'

# -----------------------------------------------------------------------------
# linux-utils helpers
# Repo root: LINUX_UTILS_ROOT, else directory owning the ~/.bash_aliases symlink.
# just/config installers run in subprocesses and cannot load aliases into this
# shell — call linux-utils-config (or source ~/.bash_aliases) after syncing.
# -----------------------------------------------------------------------------
_linux_utils_root() {
  local root aliases_path

  if [[ -n "${LINUX_UTILS_ROOT:-}" ]]; then
    root="${LINUX_UTILS_ROOT}"
  else
    aliases_path="${HOME}/.bash_aliases"
    if [[ ! -e "$aliases_path" ]]; then
      printf 'linux-utils: %s not found; set LINUX_UTILS_ROOT\n' "$aliases_path" >&2
      return 1
    fi
    root="$(dirname "$(readlink -f "$aliases_path")")"
  fi

  if [[ ! -f "$root/justfile" ]]; then
    printf 'linux-utils: no justfile in %s; set LINUX_UTILS_ROOT\n' "$root" >&2
    return 1
  fi
  if [[ ! -d "$root/.git" && ! -f "$root/.git" ]]; then
    printf 'linux-utils: not a git checkout: %s; set LINUX_UTILS_ROOT\n' "$root" >&2
    return 1
  fi

  printf '%s\n' "$root"
}

# Reload tracked aliases/functions into the current shell (not a subprocess).
_linux_utils_source_aliases() {
  local aliases_path="${HOME}/.bash_aliases"
  if [[ ! -f "$aliases_path" ]]; then
    printf 'linux-utils: %s missing after config sync\n' "$aliases_path" >&2
    return 1
  fi
  # shellcheck disable=SC1090
  . "$aliases_path"
  printf 'linux-utils: sourced %s\n' "$aliases_path"
}

# Sync tracked configs (same as `just config`), then source aliases here.
# Usage: linux-utils-config
linux-utils-config() {
  local root
  root="$(_linux_utils_root)" || return 1

  if ! command -v just >/dev/null 2>&1; then
    printf 'linux-utils-config: just not on PATH (install via: just install --cargo)\n' >&2
    return 1
  fi

  just --justfile "$root/justfile" --working-directory "$root" config || return 1
  _linux_utils_source_aliases
}

# Fast-forward main and run `just install` from anywhere; re-source aliases after.
# Usage:
#   linux-utils-install                 # just install --all (default)
#   linux-utils-install --apt --cargo
#   LINUX_UTILS_ROOT=~/src/linux-utils linux-utils-install --config
linux-utils-install() {
  local root
  root="$(_linux_utils_root)" || return 1

  # Subshell: never leave the caller's cwd changed.
  (
    set -euo pipefail
    cd "$root"

    if ! command -v git >/dev/null 2>&1; then
      printf 'linux-utils-install: git not on PATH\n' >&2
      exit 1
    fi
    if ! command -v just >/dev/null 2>&1; then
      printf 'linux-utils-install: just not on PATH (install via: just install --cargo)\n' >&2
      exit 1
    fi

    printf 'linux-utils-install: fast-forwarding main in %s\n' "$root"
    git fetch origin main
    git switch main
    git pull --ff-only origin main

    printf 'linux-utils-install: running just install'
    if (($#)); then
      printf ' %s' "$@"
    fi
    printf '\n'
    # just runs recipes with the justfile directory as cwd; -f keeps that
    # explicit if the working directory ever diverges.
    just --justfile "$root/justfile" --working-directory "$root" install "$@"
  ) || return 1

  # Install/config may have refreshed the symlink; load it in this shell.
  _linux_utils_source_aliases
}

# -----------------------------------------------------------------------------
# Function: updateall
# Description: TUI-styled update of installed system/global package managers.
#   Streams each step's output live (so sudo prompts work). Usage: updateall
# -----------------------------------------------------------------------------
_updateall_as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

_updateall_apt() {
  _updateall_as_root apt-get update &&
    _updateall_as_root apt-get upgrade -y &&
    _updateall_as_root apt-get autoremove -y
}

_updateall_flatpak() {
  _updateall_as_root flatpak update -y
}

_updateall_snap() {
  _updateall_as_root snap refresh
}

_updateall_brew() {
  brew update &&
    brew upgrade &&
    brew cleanup
}

_updateall_pnpm() {
  pnpm update -g
}

_updateall_npm() {
  _updateall_as_root npm update -g
}

_updateall_pip() {
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    printf 'Skipping pip user packages: active virtual environment (%s).\n' "$VIRTUAL_ENV"
    return 0
  fi

  if ! python3 -m pip --version >/dev/null 2>&1; then
    printf 'Skipping pip user packages: python3 -m pip is unavailable.\n'
    return 0
  fi

  python3 - <<'PY'
import json
import subprocess
import sys

outdated = subprocess.run(
    [sys.executable, "-m", "pip", "list", "--user", "--outdated", "--format=json"],
    check=True,
    stdout=subprocess.PIPE,
    text=True,
)
packages = [package["name"] for package in json.loads(outdated.stdout)]

if not packages:
    print("pip user packages are already current.")
    raise SystemExit(0)

for package in packages:
    subprocess.check_call(
        [sys.executable, "-m", "pip", "install", "--user", "--upgrade", package]
    )
PY
}

_updateall_pipx() {
  pipx upgrade-all
}

_updateall_uv() {
  uv self update ||
    printf 'Skipping uv self update: this uv install may be managed externally.\n'
  uv tool upgrade --all
}

_updateall_rustup() {
  rustup update
}

_updateall_cargo_installs() {
  if command -v cargo-install-update >/dev/null 2>&1; then
    cargo install-update -a
  else
    printf 'Skipping Cargo-installed binaries: install cargo-update to enable updates.\n'
  fi
}

_updateall_init_ui() {
  if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    _UA_RED=$(tput setaf 1 2>/dev/null; tput bold 2>/dev/null)
    _UA_GREEN=$(tput setaf 2 2>/dev/null; tput bold 2>/dev/null)
    _UA_CYAN=$(tput setaf 6 2>/dev/null; tput bold 2>/dev/null)
    _UA_DIM=$(tput setaf 8 2>/dev/null)
    _UA_BOLD=$(tput bold 2>/dev/null)
    _UA_RESET=$(tput sgr0 2>/dev/null)
    _UA_COLS=$(tput cols 2>/dev/null || echo 80)
  else
    _UA_RED=""
    _UA_GREEN=""
    _UA_CYAN=""
    _UA_DIM=""
    _UA_BOLD=""
    _UA_RESET=""
    _UA_COLS=80
  fi

  if ! [[ "$_UA_COLS" =~ ^[0-9]+$ ]] || ((_UA_COLS < 40)); then
    _UA_COLS=80
  fi
}

_updateall_rule() {
  local width="${1:-$_UA_COLS}" ch="${2:-─}"
  local line
  printf -v line '%*s' "$width" ''
  printf '%s\n' "${line// /$ch}"
}

_updateall_header() {
  local title=" update-all "
  local left right

  printf '%s' "$_UA_CYAN$_UA_BOLD"
  _updateall_rule "$_UA_COLS" "═"
  left=$(( (_UA_COLS - ${#title}) / 2 ))
  right=$((_UA_COLS - ${#title} - left))
  printf '%*s%s%*s\n' "$left" '' "$title" "$right" ''
  _updateall_rule "$_UA_COLS" "═"
  printf '%s' "$_UA_RESET"
}

_updateall_queue() {
  local i key label

  printf '%sQueued steps%s\n' "$_UA_BOLD" "$_UA_RESET"
  for i in "${!_UA_KEYS[@]}"; do
    key="${_UA_KEYS[$i]}"
    label="${_UA_LABELS[$i]}"
    if [[ "${_UA_STATUS[$key]}" == skipped ]]; then
      printf '  %s○%s %s %s(skipped)%s\n' "$_UA_DIM" "$_UA_RESET" "$label" "$_UA_DIM" "$_UA_RESET"
    else
      printf '  %s·%s %s\n' "$_UA_DIM" "$_UA_RESET" "$label"
    fi
  done
}

_updateall_step_begin() {
  local label="$1" index="$2" total="$3"

  printf '\n%s●%s %s%s%s  %s(%d/%d)%s\n' \
    "$_UA_CYAN$_UA_BOLD" "$_UA_RESET" \
    "$_UA_BOLD" "$label" "$_UA_RESET" \
    "$_UA_CYAN" "$index" "$total" "$_UA_RESET"
  printf '%s' "$_UA_DIM"
  _updateall_rule "$_UA_COLS" "─"
  printf '%s' "$_UA_RESET"
}

_updateall_step_end() {
  local label="$1" ok="$2"

  if ((ok)); then
    printf '  %s✓%s %s\n' "$_UA_GREEN" "$_UA_RESET" "$label"
  else
    printf '  %s✗%s %s\n' "$_UA_RED" "$_UA_RESET" "$label"
  fi
}

_updateall_summary() {
  local -n _done=$1 _failed=$2 _skipped=$3
  local key

  printf '\n'
  printf '%s' "$_UA_CYAN$_UA_BOLD"
  _updateall_rule "$_UA_COLS" "═"
  printf ' summary\n'
  _updateall_rule "$_UA_COLS" "═"
  printf '%s' "$_UA_RESET"

  for key in "${_done[@]}"; do
    printf '  %s✓%s %s\n' "$_UA_GREEN" "$_UA_RESET" "$key"
  done
  for key in "${_failed[@]}"; do
    printf '  %s✗%s %s\n' "$_UA_RED" "$_UA_RESET" "$key"
  done
  for key in "${_skipped[@]}"; do
    printf '  %s○%s %s %s(skipped)%s\n' "$_UA_DIM" "$_UA_RESET" "$key" "$_UA_DIM" "$_UA_RESET"
  done
}

updateall() {
  local -a failures=() done_labels=() failed_labels=() skipped_labels=()
  local i key cmd label fn
  local active_total=0 step_index=0 status

  _UA_KEYS=(apt flatpak snap brew pnpm npm pip pipx uv rustup cargo)
  _UA_LABELS=(
    "APT packages"
    "Flatpak packages"
    "Snap packages"
    "Homebrew packages"
    "pnpm global packages"
    "npm global packages"
    "pip user packages"
    "pipx apps"
    "uv tools"
    "Rust toolchains"
    "Cargo-installed binaries"
  )
  _UA_CMDS=(apt-get flatpak snap brew pnpm npm python3 pipx uv rustup cargo)
  _UA_FUNCS=(
    _updateall_apt
    _updateall_flatpak
    _updateall_snap
    _updateall_brew
    _updateall_pnpm
    _updateall_npm
    _updateall_pip
    _updateall_pipx
    _updateall_uv
    _updateall_rustup
    _updateall_cargo_installs
  )

  # Global so helpers can read status if needed (bash locals are not nested).
  declare -gA _UA_STATUS=()

  _updateall_init_ui

  for i in "${!_UA_KEYS[@]}"; do
    key="${_UA_KEYS[$i]}"
    cmd="${_UA_CMDS[$i]}"
    label="${_UA_LABELS[$i]}"
    if command -v "$cmd" >/dev/null 2>&1; then
      _UA_STATUS[$key]=pending
      active_total=$((active_total + 1))
    else
      _UA_STATUS[$key]=skipped
      skipped_labels+=("$label")
    fi
  done

  _updateall_header
  _updateall_queue

  for i in "${!_UA_KEYS[@]}"; do
    key="${_UA_KEYS[$i]}"
    [[ "${_UA_STATUS[$key]}" == skipped ]] && continue

    label="${_UA_LABELS[$i]}"
    fn="${_UA_FUNCS[$i]}"
    step_index=$((step_index + 1))
    status=0

    _updateall_step_begin "$label" "$step_index" "$active_total"
    # Run in the foreground with a live TTY so sudo prompts and progress show.
    "$fn" || status=$?

    if ((status == 0)); then
      _UA_STATUS[$key]=done
      done_labels+=("$label")
      _updateall_step_end "$label" 1
    else
      _UA_STATUS[$key]=failed
      failed_labels+=("$label")
      failures+=("$key")
      _updateall_step_end "$label" 0
    fi
  done

  _updateall_summary done_labels failed_labels skipped_labels

  if ((${#failures[@]})); then
    printf '\n%s✗ Update completed with failures: %s%s\n' "$_UA_RED" "${failures[*]}" "$_UA_RESET" >&2
    return 1
  fi

  printf '\n%s✓ All available package managers updated successfully.%s\n' "$_UA_GREEN" "$_UA_RESET"
  return 0
}

alias update-all='updateall'

# -----------------------------------------------------------------------------
# Function: cuda
# Description: Sets the environment variables required for using a specific
#   version of the CUDA toolkit.
# Parameters:
#   $1 - CUDA version number
# Usage: cuda <version_number>
# Returns:
#   1 - if the specified CUDA version is not found in /usr/local/
# -----------------------------------------------------------------------------
cuda() {
  # Check the version exists in /usr/local/
  if [ ! -d "/usr/local/cuda-$1" ]; then
    echo "CUDA-$1 not found in /usr/local/"
    return 1
  fi

  # Remove any existing CUDA paths from the PATH variable
  PATH=$(echo "$PATH" | awk -v RS=: -v ORS=: '/cuda/ {next} {print}' | sed 's/:$//')
  # Remove any existing CUDA paths from the LD_LIBRARY_PATH variable
  LD_LIBRARY_PATH=$(echo "$LD_LIBRARY_PATH" | awk -v RS=: -v ORS=: '/cuda/ {next} {print}' | sed 's/:$//')

  # Set the environment variables for the specified CUDA version
  export PATH="/usr/local/cuda-$1/bin:$PATH"
  export LD_LIBRARY_PATH="/usr/local/cuda-$1/lib64:$LD_LIBRARY_PATH"
  export CUDA_TOOLKIT_ROOT_DIR="/usr/local/cuda-$1"
  # Env Variables for CMAKE
  export CUDA_HOME="/usr/local/cuda-$1"

  # Display the CUDA version
  nvcc --version
}

# -----------------------------------------------------------------------------
# Function: tensorrt
# Description: Sets the environment variable required for using a specific
#   version of TensorRT (assuming the user installed it in ~/libs/ using the
#   tar package installer and not the deb package).
# Parameters:
#   $1 - TensorRT version number
# Usage: tensorrt <version_number>
# -----------------------------------------------------------------------------
tensorrt() {
  # Check the version exists in ~/libs/
  if [ ! -d "$HOME/libs/TensorRT-$1" ]; then
    echo "TensorRT-$1 not found in ~/libs/"
    return 1
  fi

  # Remove any existing TensorRT paths from the LD_LIBRARY_PATH variable
  LD_LIBRARY_PATH=$(echo "$LD_LIBRARY_PATH" | awk -v RS=: -v ORS=: '/tensorrt/ {next} {print}' | sed 's/:$//')

  # Set the LD_LIBRARY_PATH variable for the specified TensorRT version
  export LD_LIBRARY_PATH="$HOME/libs/TensorRT-$1/lib:$LD_LIBRARY_PATH"

  # Display the TensorRT version
  echo "Using TensorRT version: $1"
}

# -----------------------------------------------------------------------------
# Function: sys_monitor
# Description: Brings up nvtop and htop in a tmux session for system
#   monitoring.
# Parameters: None
# Usage: sys_monitor
# -----------------------------------------------------------------------------
sys_monitor() {
  DIR="$HOME"
  # Only run this function if tmux if the session doesn't exist
  if ! tmux has-session -t sys_monitor; then
    # Create a new session called sys_monitor
    echo "Creating new tmux session: sys_monitor"
    tmux new-session -s sys_monitor -n sys_monitor -d -c "$DIR"

    # Split the window into 2 panes
    tmux split-window -v -t sys_monitor:0.0 -c "$DIR"
    tmux select-layout -t sys_monitor:0.0 even-horizontal
    tmux select-pane -t sys_monitor:0.0

    # Open nvtop in the first pane
    tmux send-keys -t sys_monitor:0.0 'nvtop' C-m
    # Open htop in the second pane
    tmux send-keys -t sys_monitor:0.1 'htop' C-m

    # Attach to the session
    tmux attach -t sys_monitor
  else
    echo "Session already exists: sys_monitor"

    # Attach to the session
    tmux attach -t sys_monitor
  fi
}

# -----------------------------------------------------------------------------
# Function: theme_mode
# Description: Switches between light and dark mode on the computer, updates
#   the terminal color scheme accordingly, and updates the VSCode theme.
# Parameters: None
# Usage: theme_mode
# -----------------------------------------------------------------------------
theme_mode() {
  # Define the light and dark theme names
  LIGHT_THEME="Yaru-light"
  DARK_THEME="Yaru-dark"

  # Define the UUIDs for the custom terminal profiles
  LIGHT_PROFILE_UUID="9c60621a-81a9-41a3-82a7-b0a0d6c57de7"
  DARK_PROFILE_UUID="b1dcc9dd-5262-4d8d-a863-c897e6d979b9"

  # Define VSCode themes
  VSCODE_LIGHT_THEME="Default Light Modern"
  VSCODE_DARK_THEME="Default Dark Modern"

  # Path to VSCode settings.json file
  VSCODE_SETTINGS_FILE="$HOME/.config/Code/User/settings.json"

  # Get the current GTK theme
  CURRENT_THEME=$(gsettings get org.gnome.desktop.interface gtk-theme)

  # Check the current theme and switch to the opposite theme
  if [[ $CURRENT_THEME == "'$LIGHT_THEME'" ]]; then
    gsettings set org.gnome.desktop.interface gtk-theme "$DARK_THEME"
    gsettings set org.gnome.Terminal.ProfilesList default "$DARK_PROFILE_UUID"
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

    # Update the VSCode theme
    jq --arg theme "$VSCODE_DARK_THEME" '.["workbench.colorTheme"] = $theme' "$VSCODE_SETTINGS_FILE" >temp.json && mv temp.json "$VSCODE_SETTINGS_FILE"

    echo "Switched to dark mode."
  else
    gsettings set org.gnome.desktop.interface gtk-theme "$LIGHT_THEME"
    gsettings set org.gnome.Terminal.ProfilesList default "$LIGHT_PROFILE_UUID"
    gsettings set org.gnome.desktop.interface color-scheme 'default'
    echo "Switched to light mode."

    # Update the VSCode theme
    jq --arg theme "$VSCODE_LIGHT_THEME" '.["workbench.colorTheme"] = $theme' "$VSCODE_SETTINGS_FILE" >temp.json && mv temp.json "$VSCODE_SETTINGS_FILE"
  fi
}

# -----------------------------------------------------------------------------
# Function: hyphenate
# Description: Takes a string and replaces spaces with hyphens while removing
#   any special characters that the UNIX file system doesn't like. Then
#   prints the hyphenated string and set $HYPHENATED to the hyphenated string.
# Parameters:
#   $1 - The string to be hyphenated
# Usage: hypenate <string>
# -----------------------------------------------------------------------------
hyphenate() {
  # Replace spaces with hyphens, then strip characters unsafe for filenames
  HYPHENATED=${1// /-}
  HYPHENATED=${HYPHENATED//[^a-zA-Z0-9-]/}
  echo "$HYPHENATED"
}

# -----------------------------------------------------------------------------
# Function: unzipall
# Description: Recursively unzips all .zip files in the current directory without
#   recreating archived paths.
# Parameters:
#   $1 - Optional flag to run in parallel mode
#   $2 - Optional number of threads (default: all available threads) when using
#        parallel mode
# Usage: unzipall [-p|--parallel] [number_of_threads]
# Examples:
#   unzipall             # Run in serial mode
#   unzipall -p          # Run in parallel mode with all available threads
#   unzipall -p 8        # Run in parallel mode with 8 threads
#   unzipall --parallel 12  # Run in parallel mode with 12 threads
# -----------------------------------------------------------------------------
unzipall() {
  if [[ "$1" == "-p" || "$1" == "--parallel" ]]; then
    # Default to the number of CPU cores
    default_threads=$(nproc)
    threads=$default_threads
    if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
      threads=$2
    elif [[ -n "$2" && ! "$2" =~ ^[0-9]+$ ]]; then
      echo "Warning: Invalid thread count '$2'. Using default ($default_threads)."
    fi

    echo "Unzipping in parallel mode with $threads threads..."
    find . -type f -name "*.zip" -print0 | xargs -0 -P "$threads" -I{} unzip -j {}
  else
    echo "Unzipping in serial mode..."
    find . -type f -name "*.zip" -exec unzip -j {} \;
  fi
}

# -----------------------------------------------------------------------------
# Function: cpu_governors
# Description: Prints the current CPU governors for all CPUs.
# Parameters: None
# Usage: cpu_governors
# -----------------------------------------------------------------------------
cpu_governors() {
  cpu_dirs=$(ls -dv /sys/devices/system/cpu/cpu[0-9]*)

  for cpu in $cpu_dirs; do
    cpu_id="${cpu##*/}"
    echo -n "$cpu_id: "
    cat "$cpu/cpufreq/scaling_governor"
  done
}

# -----------------------------------------------------------------------------
# Function: set_cpu_governors
# Description: Set all CPU governors to the specified governor.
# Parameters:
#   $1 - The governor to set all CPUs to
# Usage: set_cpu_governors <governor>
# -----------------------------------------------------------------------------
set_cpu_governors() {
  # Check if governor argument is provided
  if [ -z "$1" ]; then
    echo "Usage: set_cpu_governors <governor>"
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors ]; then
      echo "Available governors for cpu0: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors)"
    else
      echo "Could not read available governors for cpu0. Defaulting to common options."
      echo "Available governors usually include: performance, powersave, schedutil, ondemand, conservative, userspace"
    fi
    return 1
  fi

  cpu_dirs=$(ls -dv /sys/devices/system/cpu/cpu[0-9]*)

  # Check if the governor is available for all CPUs
  for cpu in $cpu_dirs; do
    cpu_id="${cpu##*/}"
    if ! grep -q "$1" "$cpu/cpufreq/scaling_available_governors"; then
      echo "Error: Governor '$1' is not available for $cpu_id"
      echo "Available governors include: $(cat "$cpu/cpufreq/scaling_available_governors")"
      return 1
    fi
  done

  # Set the governor for all CPUs
  for cpu in $cpu_dirs; do
    cpu_id="${cpu##*/}"
    echo "$1" | sudo tee "$cpu/cpufreq/scaling_governor" >/dev/null
  done
}

# -----------------------------------------------------------------------------
# Function: cpu_frequencies
# Description: Prints the current CPU frequencies for all CPUs in GHz.
# Parameters: None
# Usage: cpu_frequencies
# -----------------------------------------------------------------------------
cpu_frequencies() {
  cpu_dirs=$(ls -dv /sys/devices/system/cpu/cpu[0-9]*)

  for cpu in $cpu_dirs; do
    cpu_id="${cpu##*/}"
    echo -n "$cpu_id: "
    cat "$cpu/cpufreq/scaling_cur_freq" | awk '{print $1/1000000}'
  done
}

# -----------------------------------------------------------------------------
# Function: coderemote
# Description: The remote equivalent of `code .`. Run it on any server you are
#   SSHing into and it prints a ready-to-run VS Code command that opens the
#   remote directory on local when run on the machine you connected from:
#
#     code --folder-uri "vscode-remote://ssh-remote+<host><path>"
#
#   A plain SSH shell cannot reach your local GUI, so the command is meant to be
#   run on your local machine. It is also copied to your local clipboard via the
#   OSC 52 escape sequence (when your terminal supports it) so you can paste and
#   run it without retyping.
#
#   <host> must match the `Host` entry in your local ~/.ssh/config. It defaults
#   to this server's short hostname; override it with $CODE_REMOTE_HOST when the
#   SSH alias differs from the hostname.
# Parameters:
#   $1 - Optional directory to open (default: current working directory)
# Usage:
#   coderemote                      # open the current directory
#   coderemote ~/dev/project        # open a specific directory
#   CODE_REMOTE_HOST=tracer coderemote
# -----------------------------------------------------------------------------
coderemote() {
  local host="${CODE_REMOTE_HOST:-$(hostname -s)}"

  # Resolve to an absolute, canonical path so the URI is valid from the local
  # machine, and fail loudly if the directory does not exist.
  local target
  if ! target=$(cd "${1:-$PWD}" 2>/dev/null && pwd); then
    echo "coderemote: no such directory: ${1:-$PWD}" >&2
    return 1
  fi

  local cmd="code --folder-uri \"vscode-remote://ssh-remote+${host}${target}\""
  printf '%s\n' "$cmd"

  # Best-effort: copy the command to the local machine's clipboard via OSC 52,
  # writing to the terminal directly so stdout (the command) stays clean for
  # piping. Through tmux this needs `set -g allow-passthrough on`.
  local payload
  payload=$(printf '%s' "$cmd" | base64 | tr -d '\n')
  # Group-redirect stderr so opening /dev/tty silently no-ops when there is no
  # controlling terminal (e.g. when the function output is piped in a script).
  {
    if [ -n "$TMUX" ]; then
      # Octal escapes: \033 ESC, \007 BEL, \134 backslash. Inner ESC is
      # doubled per tmux passthrough rules and the DCS is closed with ST.
      printf '\033Ptmux;\033\033]52;c;%s\007\033\134' "$payload" >/dev/tty
    else
      printf '\033]52;c;%s\007' "$payload" >/dev/tty
    fi
  } 2>/dev/null

  # The clipboard copy is best-effort; the printed command is the real result.
  return 0
}
