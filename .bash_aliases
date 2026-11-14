# shellcheck shell=bash

alias vim='nvim'
alias shumble='source /opt/ros/humble/setup.bash'
alias si='source install/setup.bash'

# Shells use one stable agent path. A tmux session outlives the SSH or mosh login
# that set SSH_AUTH_SOCK, and mosh never forwards an agent, so an inherited path
# is often already gone. Desktop sockets (gpg-agent, gcr, gnome-keyring) are
# skipped: systemd --user exports S.gpg-agent.ssh into tmux.service, and both
# gpg-agent and gcr-ssh-agent route passphrase prompts to a local GUI display
# that fails over mosh/SSH with "agent refused operation". Each new shell
# repoints the link for every pane: a live forwarded agent first, then whatever
# the link still reaches, else a new ssh-agent that later shells reuse.
_ssh_agent_link() {
  local link="${XDG_RUNTIME_DIR:-$HOME/.ssh}/ssh-agent.sock" sock=""

  case "${SSH_AUTH_SOCK:-}" in
    */gnupg/*|*/gcr/*|*/keyring/*) ;;
    *) sock="${SSH_AUTH_SOCK:-}" ;;
  esac

  for sock in "$sock" "$link"; do
    [[ -S "$sock" ]] && break
  done
  if [[ ! -S "$sock" ]]; then
    eval "$(ssh-agent -s)" >/dev/null
    sock="$SSH_AUTH_SOCK"
  fi

  [[ "$sock" == "$link" ]] || ln -sfn "$sock" "$link"
  export SSH_AUTH_SOCK="$link"
}
_ssh_agent_link

# resync and other user commands live in ~/.local/bin. Ubuntu's ~/.profile adds
# it only if it existed at login, and root's and macOS's profiles never do.
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# Switch the shell to the CUDA toolkit installed at /usr/local/cuda-<version>.
cuda() {
  if [ -z "${1:-}" ] || [ ! -d "/usr/local/cuda-$1" ]; then
    echo "CUDA-${1:-} not found in /usr/local/" >&2
    return 1
  fi

  # Drop any previously selected version before prepending this one.
  PATH=$(printf '%s' "${PATH:-}" | awk -v RS=: 'NF && $0 !~ /cuda/ { printf "%s%s", sep, $0; sep=":" }')
  LD_LIBRARY_PATH=$(printf '%s' "${LD_LIBRARY_PATH:-}" | awk -v RS=: 'NF && $0 !~ /cuda/ { printf "%s%s", sep, $0; sep=":" }')

  export PATH="/usr/local/cuda-$1/bin${PATH:+:$PATH}"
  # Omit the separator when LD_LIBRARY_PATH is empty: a trailing colon in
  # LD_LIBRARY_PATH instructs ld.so to search the current working directory.
  export LD_LIBRARY_PATH="/usr/local/cuda-$1/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  # CMake reads both spellings depending on its version.
  export CUDA_TOOLKIT_ROOT_DIR="/usr/local/cuda-$1"
  export CUDA_HOME="/usr/local/cuda-$1"

  nvcc --version
}

# Switch the shell to a TensorRT unpacked from the tar release into ~/libs/.
tensorrt() {
  if [ -z "${1:-}" ] || [ ! -d "$HOME/libs/TensorRT-$1" ]; then
    echo "TensorRT-${1:-} not found in ~/libs/" >&2
    return 1
  fi

  LD_LIBRARY_PATH=$(printf '%s' "${LD_LIBRARY_PATH:-}" | awk -v RS=: 'NF && tolower($0) !~ /tensorrt/ { printf "%s%s", sep, $0; sep=":" }')
  export LD_LIBRARY_PATH="$HOME/libs/TensorRT-$1/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

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
