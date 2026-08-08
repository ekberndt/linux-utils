#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../installers/lib/package_list.sh
source "$ROOT/installers/lib/package_list.sh"
# shellcheck source=../installers/lib/common.sh
source "$ROOT/installers/lib/common.sh"
# shellcheck source=../installers/lib/apt_packages.sh
source "$ROOT/installers/lib/apt_packages.sh"

failures=0
assert_eq() {
    local name="$1" got="$2" want="$3"
    if [[ "$got" != "$want" ]]; then
        echo "FAIL $name: got=$got want=$want" >&2
        failures=$((failures + 1))
    else
        echo "ok   $name"
    fi
}

assert_parse() {
    local name="$1" line="$2" want_pkg="$3" want_opt="$4" want_ppa="$5"
    package=""; optional=false; ppa=""
    if ! parse_package_line "$line"; then
        assert_eq "$name skip" "skipped" "parsed"
        return
    fi
    assert_eq "$name package" "$package" "$want_pkg"
    assert_eq "$name optional" "$optional" "$want_opt"
    assert_eq "$name ppa" "$ppa" "$want_ppa"
}

assert_contains() {
    local name="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "ok   $name"
    else
        echo "FAIL $name: missing '$needle'" >&2
        failures=$((failures + 1))
    fi
}

assert_not_contains() {
    local name="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "FAIL $name: found '$needle'" >&2
        failures=$((failures + 1))
    else
        echo "ok   $name"
    fi
}

package_file_entries() {
    sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$@"
}

echo "== installer profiles =="
installer_targets="$(bash "$ROOT/installers/installer.sh" list)"
workstation_plan="$(bash "$ROOT/installers/installer.sh" plan workstation)"
workstation_apps_plan="$(bash "$ROOT/installers/installer.sh" plan workstation desktop-apps)"
datacenter_plan="$(bash "$ROOT/installers/installer.sh" plan datacenter)"
extended_plan="$(bash "$ROOT/installers/installer.sh" plan datacenter ollama)"
assert_contains "installer lists workstation profile" "$installer_targets" "workstation"
assert_not_contains "installer removes personal profile" "$installer_targets" "  personal"
assert_contains "installer lists datacenter profile" "$installer_targets" "datacenter"
assert_not_contains "workstation excludes desktop apps by default" "$workstation_plan" \
    "Personal desktop apps"
assert_contains "workstation desktop apps remain opt-in" "$workstation_apps_plan" \
    "Personal desktop apps"
assert_contains "workstation includes recommended NVIDIA driver" "$workstation_plan" \
    "Recommended NVIDIA driver"
assert_contains "workstation includes Homebrew" "$workstation_plan" "Homebrew packages"
assert_contains "workstation includes tmux" "$workstation_plan" "tmux session persistence"
assert_not_contains "workstation excludes standalone empty Flatpak list" "$workstation_plan" \
    "· Flatpak packages"
assert_contains "components compose with a profile" "$extended_plan" "Ollama"

default_desktop_packages="$(package_file_entries \
    "$ROOT/installers/apt/apt_packages.txt" \
    "$ROOT/installers/flatpak/flatpaks.txt" \
    "$ROOT/installers/snap/snaps.txt")"
optional_desktop_packages="$(package_file_entries \
    "$ROOT/installers/desktop-apps/apt_packages.txt" \
    "$ROOT/installers/desktop-apps/flatpaks.txt" \
    "$ROOT/installers/desktop-apps/snaps.txt")"
personal_apps=(
    com.discordapp.Discord
    com.spotify.Client
    blender
    slack
    org.gimp.GIMP
    org.kde.krita
    md.obsidian.Obsidian
    com.obsproject.Studio
    vlc
    gnome-clocks
    gnome-software-plugin-flatpak
)
for app in "${personal_apps[@]}"; do
    assert_not_contains "default package lists exclude $app" \
        "$default_desktop_packages" "$app"
    assert_contains "personal package lists include $app" \
        "$optional_desktop_packages" "$app"
done
assert_contains "default package list keeps gprename" \
    "$default_desktop_packages" "gprename"
assert_not_contains "personal package lists exclude gprename" \
    "$optional_desktop_packages" "gprename"

echo "== parse_package_line =="
assert_parse "simple" "git # version control" "git" "false" ""
assert_parse "optional" "? sway # tiling" "sway" "true" ""
assert_parse "ppa" "foo | ppa:user/repo # desc" "foo" "false" "user/repo"
package=""; optional=false; ppa=""
if parse_package_line "# comment only"; then
    assert_eq "comment" "parsed" "skipped"
else
    assert_eq "comment" "skipped" "skipped"
fi
package=""; optional=false; ppa=""
if parse_package_line ""; then
    assert_eq "blank" "parsed" "skipped"
else
    assert_eq "blank" "skipped" "skipped"
fi

unset INSTALLER_INSTALL_OPTIONALS
if install_optionals_env; then
    assert_eq "APT optionals default" "installed" "skipped"
else
    assert_eq "APT optionals default" "skipped" "skipped"
fi
INSTALLER_INSTALL_OPTIONALS=1
if install_optionals_env; then
    assert_eq "APT optionals flag" "installed" "installed"
else
    assert_eq "APT optionals flag" "skipped" "installed"
fi
unset INSTALLER_INSTALL_OPTIONALS

echo "== datacenter installer =="
assert_contains "datacenter queues expected steps" "$datacenter_plan" "16 steps queued"
assert_contains "datacenter includes Docker" "$datacenter_plan" "Docker Engine"
assert_contains "datacenter includes uv" "$datacenter_plan" "uv Python toolchain"
assert_contains "datacenter includes W&B" "$datacenter_plan" "Weights & Biases"
assert_contains "datacenter includes Claude" "$datacenter_plan" "Claude Code"
assert_contains "datacenter includes Codex" "$datacenter_plan" "Codex CLI"
assert_contains "datacenter includes Grok" "$datacenter_plan" "Grok Build"
assert_contains "datacenter includes Rust" "$datacenter_plan" "Rust and Cargo packages"
assert_contains "datacenter includes Neovim" "$datacenter_plan" "Neovim and LazyVim"
assert_contains "datacenter includes tmux" "$datacenter_plan" "tmux session persistence"
assert_contains "datacenter includes config" "$datacenter_plan" "Tracked config"
assert_not_contains "datacenter excludes Homebrew" "$datacenter_plan" "Homebrew packages"
assert_not_contains "datacenter excludes desktop apps" "$datacenter_plan" "Personal desktop apps"
assert_not_contains "datacenter leaves image NVIDIA driver alone" "$datacenter_plan" \
    "Recommended NVIDIA driver"

workstation_profile="$(< "$ROOT/installers/profiles/workstation.conf")"
assert_contains "workstation installs NVIDIA driver before Docker" "$workstation_profile" \
    $'apt\n    nvidia-driver\n    docker'
workstation_packages="$(< "$ROOT/installers/apt/apt_packages.txt")"
assert_contains "workstation keeps Sway packages opt-in" \
    "$workstation_packages" $'\n? sway #'
assert_contains "workstation installs OpenSSH server" "$workstation_packages" \
    "openssh-server #"
assert_contains "workstation installs ubuntu-drivers" "$workstation_packages" \
    "ubuntu-drivers-common #"
nvidia_installer="$(< "$ROOT/installers/nvidia-driver/install.sh")"
assert_contains "NVIDIA installer selects Ubuntu recommendation" "$nvidia_installer" \
    "ubuntu-drivers install"
docker_installer="$(< "$ROOT/installers/docker/install.sh")"
assert_contains "Docker runtime follows NVIDIA hardware" "$docker_installer" \
    "if has_nvidia_gpu; then"

gh_installer="$(< "$ROOT/installers/gh/install.sh")"
assert_contains "GitHub CLI uses Ubuntu package" "$gh_installer" \
    "apt-get install -y gh"
assert_not_contains "GitHub CLI avoids external repository key" "$gh_installer" \
    "githubcli-archive-keyring"
installer_source="$(< "$ROOT/installers/installer.sh")"
apt_package_installer="$(< "$ROOT/installers/lib/apt_packages.sh")"
assert_not_contains "APT installer has no optional-package prompt" \
    "$apt_package_installer" "/dev/tty"
assert_contains "APT installer skips unrequested optionals" \
    "$apt_package_installer" '! install_optionals_env'
assert_contains "installer exposes the optional-package flag" "$installer_source" \
    "--optionals"
assert_contains "installer keeps sudo alive for the full run" "$installer_source" \
    "start_sudo_session"
common_source="$(< "$ROOT/installers/lib/common.sh")"
assert_contains "sudo keepalive never prompts again" "$common_source" "sudo -n -v"
assert_contains "installer removes retired GitHub CLI source" "$installer_source" \
    "/etc/apt/sources.list.d/github-cli.list"
power_config="$(< "$ROOT/installers/config/power.sh")"
assert_contains "config uses a 15-minute display idle timeout" "$power_config" \
    "display_idle_seconds=900"
assert_contains "config manages GNOME display idle" "$power_config" \
    "org.gnome.desktop.session idle-delay"
sshd_config="$(< "$ROOT/installers/config/sshd.conf")"
assert_contains "SSH config requires public keys" "$sshd_config" \
    "AuthenticationMethods publickey"
assert_contains "SSH config disables passwords" "$sshd_config" \
    "PasswordAuthentication no"
assert_contains "SSH config disables keyboard passwords" "$sshd_config" \
    "KbdInteractiveAuthentication no"
ssh_config_installer="$(< "$ROOT/installers/config/ssh.sh")"
assert_contains "SSH config enables and starts the server" "$ssh_config_installer" \
    "systemctl enable --now ssh.service"
assert_contains "SSH config reports server status" "$ssh_config_installer" \
    "systemctl status ssh.service --no-pager"
config_orchestrator="$(< "$ROOT/installers/config/install.sh")"
assert_contains "config applies GNOME preferences" "$config_orchestrator" $'    gnome\n'
assert_contains "config applies SSH policy" "$config_orchestrator" $'    ssh\n'

datacenter_packages="$(< "$ROOT/installers/apt/datacenter_packages.txt")"
assert_contains "datacenter includes Python venvs" "$datacenter_packages" "python3-venv #"
assert_not_contains "APT manifest leaves tmux to its component" "$datacenter_packages" "tmux #"
assert_not_contains "APT manifest leaves Neovim to its component" "$datacenter_packages" "neovim #"

aliases_source="$(< "$ROOT/.bash_aliases")"
# shellcheck disable=SC2016 # Assert the literal helper command in .bash_aliases.
assert_contains "linux-utils helper invokes Bash installer" "$aliases_source" \
    'bash "$root/installers/installer.sh"'
assert_not_contains "linux-utils helper does not require just" "$aliases_source" \
    "command -v just"
assert_contains "linux-utils helper defaults to workstation" "$aliases_source" \
    'installer.sh" workstation'

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    sudo() { return 1; }
    privilege_result="$(run_as_root printf direct)"
    assert_eq "root commands run directly" "$privilege_result" "direct"
else
    sudo() { printf 'elevated:%s' "$*"; }
    privilege_result="$(run_as_root printf direct)"
    assert_eq "user commands use sudo" "$privilege_result" "elevated:printf direct"
fi
unset -f sudo

if command -v unshare >/dev/null 2>&1 && unshare -Ur true 2>/dev/null; then
    common_lib="$ROOT/installers/lib/common.sh"
    # shellcheck disable=SC2016 # COMMON_LIB is expanded by the nested shell.
    privilege_result="$(COMMON_LIB="$common_lib" unshare -Ur env \
        COMMON_LIB="$common_lib" bash -c \
        'source "$COMMON_LIB"; sudo() { return 1; }; run_as_root printf direct')"
    assert_eq "UID 0 commands bypass sudo" "$privilege_result" "direct"
else
    echo "skip UID 0 privilege helper (user namespaces unavailable)"
fi

echo "== inject-grok/codex toml =="
if python3 "$ROOT/tests/test_inject_toml_config.py"; then
    echo "ok   inject toml config"
else
    echo "FAIL inject toml config" >&2
    failures=$((failures + 1))
fi

echo "== zoxide shell init =="
if bash "$ROOT/tests/test_zoxide_init.sh"; then
    echo "ok   zoxide shell init"
else
    echo "FAIL zoxide shell init" >&2
    failures=$((failures + 1))
fi

echo "== GNOME config =="
if bash "$ROOT/tests/test_gnome_config.sh"; then
    echo "ok   GNOME dock preferences"
else
    echo "FAIL GNOME dock preferences" >&2
    failures=$((failures + 1))
fi

echo "== ducky encode =="
if python3 "$ROOT/tests/test_ducky_encode.py"; then
    echo "ok   ducky encode"
else
    echo "FAIL ducky encode" >&2
    failures=$((failures + 1))
fi

echo "== babysit-pr next_check =="
if python3 "$ROOT/tests/test_next_check.py"; then
    echo "ok   next_check"
else
    echo "FAIL next_check" >&2
    failures=$((failures + 1))
fi

echo "== tmux clipboard config =="
tmux_conf="$(< "$ROOT/tmux/tmux.conf")"
assert_contains "tmux enables clipboard forwarding" "$tmux_conf" "set -s set-clipboard on"
assert_contains "tmux reads the external clipboard" "$tmux_conf" "set -s get-clipboard both"
assert_contains "tmux clears copy-command" "$tmux_conf" "set -su copy-command"
assert_contains "tmux defines osc52 copy command" "$tmux_conf" "set -g @osc52-copy-command"
assert_contains "tmux y mirrors osc52" "$tmux_conf" 'bind -T copy-mode-vi y send -X copy-selection-and-cancel \; run-shell -b "#{E:@osc52-copy-command}"'
assert_contains "tmux enter mirrors osc52" "$tmux_conf" 'bind -T copy-mode-vi Enter send -X copy-selection-and-cancel \; run-shell -b "#{E:@osc52-copy-command}"'
assert_contains "tmux mouse mirrors osc52" "$tmux_conf" 'bind -T copy-mode-vi MouseDragEnd1Pane send -X copy-selection-no-clear \; run-shell -b "#{E:@osc52-copy-command}"'
assert_contains "tmux mosh clipboard selector" "$tmux_conf" '*:Ms=\E]52;c;%p2%s\007'
assert_contains "tmux paste imports client clipboard" "$tmux_conf" \
    'bind ] run-shell -b "~/.agents/scripts/tmux-paste-clipboard'
assert_not_contains "tmux avoids recursive copy pipe" "$tmux_conf" "tmux load-buffer -w -"

if bash "$ROOT/tests/test_tmux_clipboard.sh"; then
    echo "ok   tmux imports and pastes the client clipboard"
else
    echo "FAIL tmux client clipboard paste" >&2
    failures=$((failures + 1))
fi
assert_contains "tmux guards the agent hook" "$tmux_conf" \
    "test ! -x ~/.agents/scripts/agent-tmux ||"
assert_not_contains "tmux does not force terminal features" "$tmux_conf" \
    'terminal-features ",*:usstyle"'

echo "== LazyVim runtime =="
lazyvim_installer="$(< "$ROOT/installers/lazyvim/install.sh")"
assert_contains "LazyVim installs stable Neovim and Treesitter" "$lazyvim_installer" \
    $'LAZYVIM_FORMULAE=(\n    neovim\n    tree-sitter-cli\n)'
assert_contains "LazyVim APT dependencies auto-confirm" "$lazyvim_installer" \
    $'DEBIAN_FRONTEND=noninteractive \\\n        apt-get install -y'
assert_not_contains "LazyVim leaves the desktop monospace font alone" "$lazyvim_installer" \
    "org.gnome.desktop.interface monospace-font-name"
assert_contains "root LazyVim uses official Neovim releases" "$lazyvim_installer" \
    "github.com/neovim/neovim/releases/latest/download/nvim-linux-\$asset_arch.tar.gz"
assert_contains "root LazyVim installs Treesitter with npm" "$lazyvim_installer" \
    'npm install -g tree-sitter-cli'
assert_not_contains "LazyVim avoids Neovim development PPA" "$lazyvim_installer" "neovim-ppa/unstable"
assert_contains "LazyVim removes shadowed Mason CLI" "$lazyvim_installer" \
    'mason_root/packages/tree-sitter-cli'

echo "== tmux session persistence =="
assert_contains "tmux restores on server start" "$tmux_conf" "set -g @continuum-restore 'on'"
# continuum only arms this itself when it believes no other tmux process
# exists, which is never true on a box where agents spawn tmux sessions.
assert_contains "tmux arms the periodic save" "$tmux_conf" \
    "set -g status-right '#(~/.tmux/plugins/tmux-continuum/scripts/continuum_save.sh)"
# run-shell PATH must match the server binary before plugins load, or brew vs
# apt clients fail every reload with "'….tmux' returned 1".
assert_contains "tmux aligns plugin PATH to the server" "$tmux_conf" \
    'tmux-align-path'
assert_contains "tmux ships PATH align helper" \
    "$(< "$ROOT/scripts/tmux-align-path")" \
    'set-environment -g PATH'
# Sourcing unconditionally errors on every reload until the plugins are cloned.
assert_contains "tmux guards resurrect" "$tmux_conf" \
    'if-shell "test -e ~/.tmux/plugins/tmux-resurrect/resurrect.tmux"'
assert_contains "tmux guards continuum" "$tmux_conf" \
    'if-shell "test -e ~/.tmux/plugins/tmux-continuum/continuum.tmux"'
# Unconditionally, the unit's ExecStop would kill every detached session at
# the last logout, because a non-lingering user manager stops with the login.
assert_contains "tmux gates boot support on lingering" "$tmux_conf" \
    '-p Linger --value 2>/dev/null)" = yes'
# A leading newline anchors this to column 0, where an unguarded set would sit;
# the guarded one is indented inside the if-shell.
assert_not_contains "tmux never arms boot unconditionally" "$tmux_conf" \
    $'\nset -g @continuum-boot'
# Both would grow ~/.tmux/resurrect without bound or relaunch paid agents.
assert_not_contains "tmux leaves pane capture off" "$tmux_conf" \
    "set -g @resurrect-capture-pane-contents 'on'"
assert_not_contains "tmux does not respawn agents" "$tmux_conf" "set -g @resurrect-processes"

echo "== agent-tmux state =="
# Drive the real script against a throwaway tmux server. Asserting on config
# text would not catch the failures that actually happen here: a format tmux
# refuses to parse, or a rename/option write aimed at the wrong window.
if ! command -v tmux >/dev/null 2>&1; then
    echo "skip agent-tmux (tmux not installed)"
else
    socket="linux-utils-agent-test-$$"
    tmux -L "$socket" kill-server 2>/dev/null || true
    tmux -L "$socket" new-session -d -s t -c "$ROOT" -x 80 -y 24
    trap 'tmux -L "$socket" kill-server 2>/dev/null || true' EXIT

    if tmux -L "$socket" source-file "$ROOT/tmux/tmux.conf" 2>/dev/null; then
        echo "ok   tmux.conf parses"
    else
        echo "FAIL tmux.conf parses" >&2
        failures=$((failures + 1))
    fi

    # The script talks to whichever server $TMUX names, exactly as it does when
    # an agent hook inherits the variable from its pane.
    test_socket_path="$(tmux -L "$socket" display-message -p '#{socket_path}')"
    test_server_pid="$(tmux -L "$socket" display-message -p '#{pid}')"
    TMUX="$test_socket_path,$test_server_pid,0"
    TMUX_PANE="$(tmux -L "$socket" display-message -p -t t:0 '#{pane_id}')"
    export TMUX TMUX_PANE
    agent_tmux() { bash "$ROOT/scripts/agent-tmux" "$@"; }
    win_opt() { tmux -L "$socket" display-message -p -t "${2:-t:0}" "#{$1}"; }
    # Formats render a flag option as 0/1; show reports it as on/off.
    win_flag() { tmux -L "$socket" show -wqv -t "${2:-t:0}" "$1"; }

    agent_tmux state waiting
    assert_eq "agent-tmux sets state" "$(win_opt @agent_state)" "waiting"
    assert_contains "agent-tmux renders glyph" "$(win_opt @agent_status)" "fg=colour214"
    # The bar has no room for the repo: several worktrees of one repo read the
    # same on every window. The branch, minus a type prefix that says nothing
    # about which window this is, is what distinguishes them.
    test_branch="$(git -C "$ROOT" branch --show-current 2>/dev/null)"
    test_branch="${test_branch#*/}"
    if (( ${#test_branch} > 20 )); then
        test_branch="${test_branch:0:19}…"
    fi
    assert_eq "agent-tmux names window by branch" \
        "$(win_opt window_name)" "$test_branch"
    assert_not_contains "agent-tmux omits the repo" "$(win_opt window_name)" "linux-utils"
    assert_eq "agent-tmux pins the name" "$(win_flag automatic-rename)" "off"

    # Reading a finished agent acknowledges it; a blocked one keeps asking.
    window_id="$(win_opt window_id)"
    agent_tmux seen "$window_id"
    assert_eq "seen keeps waiting" "$(win_opt @agent_state)" "waiting"
    agent_tmux state "done"
    agent_tmux seen "$window_id"
    assert_eq "seen clears done" "$(win_opt @agent_state)" "idle"

    # A parked agent goes on generating hook traffic: Stop when each turn ends,
    # the idle prompt a minute behind it. Both arrive --soft, and dragging the
    # window out of "monitoring" is exactly the bug this state exists to fix.
    agent_tmux state monitor
    assert_contains "monitor renders its own glyph" "$(win_opt @agent_status)" "fg=colour44"
    agent_tmux state "done" --soft
    agent_tmux state waiting --soft
    assert_eq "soft states yield to monitor" "$(win_opt @agent_state)" "monitor"
    # A permission prompt is not ambient; it takes the window whatever it is on.
    agent_tmux state waiting
    assert_eq "a real prompt outranks monitor" "$(win_opt @agent_state)" "waiting"
    # ...and it is only monitor that soft states yield to.
    agent_tmux state "done" --soft
    assert_eq "soft states otherwise apply" "$(win_opt @agent_state)" "done"
    agent_tmux state monitor

    tmux -L "$socket" new-window -t t: -c "$ROOT"
    tmux -L "$socket" new-window -t t: -c "$ROOT"
    tmux -L "$socket" set -w -t t:2 @agent_state "done"
    tmux -L "$socket" select-window -t t:0
    agent_tmux jump "$TMUX_PANE"
    assert_eq "jump reaches the waiting window" "$(win_opt window_index t:)" "2"
    # Window 0 is monitoring — blocked on a machine, not on you — so it is not a
    # stop on the walk, leaving window 2 as the only one to come back around to.
    agent_tmux jump "$(tmux -L "$socket" display-message -p -t t:2 '#{pane_id}')"
    assert_eq "jump skips a monitoring window and wraps" "$(win_opt window_index t:)" "2"

    # TMUX_PANE still names window 0, so that is the window clear must reset.
    agent_tmux state clear
    assert_eq "clear drops state" "$(win_opt @agent_state)" ""
    assert_eq "clear restores renaming" "$(win_flag automatic-rename)" "on"

    unset TMUX TMUX_PANE
    tmux -L "$socket" kill-server 2>/dev/null || true
    trap - EXIT
fi

if (( failures > 0 )); then
    echo "$failures test(s) failed" >&2
    exit 1
fi
echo "All tests passed."
