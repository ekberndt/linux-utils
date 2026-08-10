# shellcheck shell=bash

alias vim='nvim'
alias shumble='source /opt/ros/humble/setup.bash'
alias si='source install/setup.bash'

# Start ssh-agent when none is available yet (preserves agent-forwarded SSH).
[ -z "${SSH_AUTH_SOCK:-}" ] && eval "$(ssh-agent -s)"

# Repo root: LINUX_UTILS_ROOT, else the directory owning the ~/.bash_aliases
# symlink. Config installers run in subprocesses and cannot load aliases into
# this shell, so the wrappers below re-source them afterwards.
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

  if [[ ! -f "$root/installers/installer.sh" ]]; then
    printf 'linux-utils: no installer in %s; set LINUX_UTILS_ROOT\n' "$root" >&2
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

# Sync tracked configs, then source aliases into this shell.
linux-utils-config() {
  local root
  root="$(_linux_utils_root)" || return 1

  bash "$root/installers/installer.sh" config || return 1
  _linux_utils_source_aliases
}

# Fast-forward main and run the installer from anywhere, defaulting to the
# workstation profile; re-source aliases afterwards.
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
    printf 'linux-utils-install: fast-forwarding main in %s\n' "$root"
    git fetch origin main
    git switch main
    git pull --ff-only origin main

    printf 'linux-utils-install: running installer'
    if (($#)); then
      printf ' %s' "$@"
    fi
    printf '\n'
    if (($#)); then
      bash "$root/installers/installer.sh" "$@"
    else
      bash "$root/installers/installer.sh" workstation
    fi
  ) || return 1

  # Install/config may have refreshed the symlink; load it in this shell.
  _linux_utils_source_aliases
}

# Update every package manager present, streaming each step live so sudo
# prompts still work.
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
    brew upgrade -y &&
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
    if [[ "${_UA_STATUS[$key]}" == "skipped" ]]; then
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
      _UA_STATUS[$key]="pending"
      active_total=$((active_total + 1))
    else
      _UA_STATUS[$key]="skipped"
      skipped_labels+=("$label")
    fi
  done

  _updateall_header
  _updateall_queue

  for i in "${!_UA_KEYS[@]}"; do
    key="${_UA_KEYS[$i]}"
    [[ "${_UA_STATUS[$key]}" == "skipped" ]] && continue

    label="${_UA_LABELS[$i]}"
    fn="${_UA_FUNCS[$i]}"
    step_index=$((step_index + 1))
    status=0

    _updateall_step_begin "$label" "$step_index" "$active_total"
    # Run in the foreground with a live TTY so sudo prompts and progress show.
    "$fn" || status=$?

    if ((status == 0)); then
      _UA_STATUS[$key]="done"
      done_labels+=("$label")
      _updateall_step_end "$label" 1
    else
      _UA_STATUS[$key]="failed"
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

# Switch the shell to the CUDA toolkit installed at /usr/local/cuda-<version>.
cuda() {
  if [ ! -d "/usr/local/cuda-$1" ]; then
    echo "CUDA-$1 not found in /usr/local/"
    return 1
  fi

  # Drop any previously selected version before prepending this one.
  PATH=$(echo "$PATH" | awk -v RS=: -v ORS=: '/cuda/ {next} {print}' | sed 's/:$//')
  LD_LIBRARY_PATH=$(echo "$LD_LIBRARY_PATH" | awk -v RS=: -v ORS=: '/cuda/ {next} {print}' | sed 's/:$//')

  export PATH="/usr/local/cuda-$1/bin:$PATH"
  export LD_LIBRARY_PATH="/usr/local/cuda-$1/lib64:$LD_LIBRARY_PATH"
  # CMake reads both spellings depending on its version.
  export CUDA_TOOLKIT_ROOT_DIR="/usr/local/cuda-$1"
  export CUDA_HOME="/usr/local/cuda-$1"

  nvcc --version
}

# Switch the shell to a TensorRT unpacked from the tar release into ~/libs/.
tensorrt() {
  if [ ! -d "$HOME/libs/TensorRT-$1" ]; then
    echo "TensorRT-$1 not found in ~/libs/"
    return 1
  fi

  LD_LIBRARY_PATH=$(echo "$LD_LIBRARY_PATH" | awk -v RS=: -v ORS=: '/tensorrt/ {next} {print}' | sed 's/:$//')
  export LD_LIBRARY_PATH="$HOME/libs/TensorRT-$1/lib:$LD_LIBRARY_PATH"

  echo "Using TensorRT version: $1"
}

# Attach to a tmux session running nvtop beside htop, creating it if needed.
sys_monitor() {
  if ! tmux has-session -t sys_monitor; then
    echo "Creating new tmux session: sys_monitor"
    tmux new-session -s sys_monitor -n sys_monitor -d -c "$HOME"
    tmux split-window -v -t sys_monitor:0.0 -c "$HOME"
    tmux select-layout -t sys_monitor:0.0 even-horizontal
    tmux select-pane -t sys_monitor:0.0
    tmux send-keys -t sys_monitor:0.0 'nvtop' C-m
    tmux send-keys -t sys_monitor:0.1 'htop' C-m
  else
    echo "Session already exists: sys_monitor"
  fi

  tmux attach -t sys_monitor
}

# Toggle GTK, GNOME Terminal, and VS Code between light and dark together.
theme_mode() {
  local light_theme="Yaru-light" dark_theme="Yaru-dark"
  # GNOME Terminal profiles are addressed by UUID, not by name.
  local light_profile="9c60621a-81a9-41a3-82a7-b0a0d6c57de7"
  local dark_profile="b1dcc9dd-5262-4d8d-a863-c897e6d979b9"
  local settings_file="$HOME/.config/Code/User/settings.json"
  local mode theme profile scheme vscode_theme

  if [[ $(gsettings get org.gnome.desktop.interface gtk-theme) == "'$light_theme'" ]]; then
    mode=dark theme="$dark_theme" profile="$dark_profile" scheme='prefer-dark'
    vscode_theme="Default Dark Modern"
  else
    mode=light theme="$light_theme" profile="$light_profile" scheme='default'
    vscode_theme="Default Light Modern"
  fi

  gsettings set org.gnome.desktop.interface gtk-theme "$theme"
  gsettings set org.gnome.Terminal.ProfilesList default "$profile"
  gsettings set org.gnome.desktop.interface color-scheme "$scheme"

  if [[ -f $settings_file ]]; then
    local tmp
    tmp="$(mktemp)"
    if jq --arg theme "$vscode_theme" '.["workbench.colorTheme"] = $theme' \
      "$settings_file" >"$tmp"; then
      mv "$tmp" "$settings_file"
    else
      rm -f "$tmp"
      echo "theme_mode: could not update $settings_file" >&2
    fi
  fi

  echo "Switched to $mode mode."
}

# Turn a string into a filename-safe slug, also leaving it in $HYPHENATED.
hyphenate() {
  HYPHENATED=${1// /-}
  HYPHENATED=${HYPHENATED//[^a-zA-Z0-9-]/}
  echo "$HYPHENATED"
}

# Unzip every .zip below the current directory, flattening archived paths.
# Usage: unzipall [-p|--parallel [threads]]
unzipall() {
  local threads

  if [[ "${1:-}" != "-p" && "${1:-}" != "--parallel" ]]; then
    echo "Unzipping in serial mode..."
    find . -type f -name "*.zip" -exec unzip -j {} \;
    return
  fi

  threads=$(nproc)
  if [[ -n "${2:-}" ]]; then
    if [[ "$2" =~ ^[0-9]+$ ]]; then
      threads=$2
    else
      echo "Warning: Invalid thread count '$2'. Using default ($threads)."
    fi
  fi

  echo "Unzipping in parallel mode with $threads threads..."
  find . -type f -name "*.zip" -print0 | xargs -0 -P "$threads" -I{} unzip -j {}
}

# Print "cpuN: value" for one cpufreq attribute across every CPU.
_cpu_attr() {
  local cpu
  for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
    [ -r "$cpu/cpufreq/$1" ] || continue
    printf '%s: %s\n' "${cpu##*/}" "$(< "$cpu/cpufreq/$1")"
  done
}

cpu_governors() {
  _cpu_attr scaling_governor
}

cpu_frequencies() {
  _cpu_attr scaling_cur_freq | awk -F': ' '{ printf "%s: %.2f GHz\n", $1, $2 / 1000000 }'
}

# Set every CPU to <governor>, refusing unless all of them support it.
set_cpu_governors() {
  local cpu available

  if [ -z "${1:-}" ]; then
    echo "Usage: set_cpu_governors <governor>"
    available="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null)"
    echo "Available governors: ${available:-performance powersave schedutil ondemand conservative userspace}"
    return 1
  fi

  for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
    [ -r "$cpu/cpufreq/scaling_available_governors" ] || continue
    if ! grep -qw "$1" "$cpu/cpufreq/scaling_available_governors"; then
      echo "Error: Governor '$1' is not available for ${cpu##*/}"
      echo "Available governors: $(< "$cpu/cpufreq/scaling_available_governors")"
      return 1
    fi
  done

  for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
    [ -w "$cpu/cpufreq/scaling_governor" ] || [ -e "$cpu/cpufreq/scaling_governor" ] || continue
    echo "$1" | sudo tee "$cpu/cpufreq/scaling_governor" >/dev/null
  done
}

# The remote equivalent of `code .`: print (and OSC 52 copy) the VS Code command
# that opens this server's directory from the machine you connected from.
#
# A plain SSH shell cannot reach your local GUI, so the command has to run
# locally. <host> must match a `Host` entry in your local ~/.ssh/config; it
# defaults to this server's short hostname, overridable with $CODE_REMOTE_HOST.
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
