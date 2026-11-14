#!/bin/bash
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

PLUGIN_DIR="${TMUX_PLUGIN_DIR:-$HOME/.tmux/plugins}"
PLUGINS=(
    "tmux-resurrect|https://github.com/tmux-plugins/tmux-resurrect"
    "tmux-continuum|https://github.com/tmux-plugins/tmux-continuum"
)

install_tmux() {
    local brew_path

    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        if is_installed tmux; then
            print_success "tmux already installed ($(tmux -V))"
            return 0
        fi
        echo "Installing tmux via apt..."
        if apt_install tmux; then
            print_installed "tmux ($(tmux -V))"
            return 0
        fi
        print_error "Failed to install tmux"
        return 1
    fi

    local -a installed=()
    if ! brew_path="$(find_brew)"; then
        print_error "Homebrew is required to install tmux. Run 'installers/installer.sh homebrew' first."
        return 1
    fi

    mapfile -t installed < <("$brew_path" list --formula 2>/dev/null)
    eval "$("$brew_path" shellenv)"
    hash -r
    if contains_item tmux "${installed[@]}"; then
        print_success "tmux already installed via Homebrew ($(tmux -V))"
    elif "$brew_path" install tmux; then
        hash -r
        print_installed "tmux ($(tmux -V))"
    else
        print_error "Failed to install tmux"
        return 1
    fi
}

# write_if_changed <path> <content>
# Succeeds only when it wrote, so systemd reloads for real changes only. A
# write that fails ends the run: the unit on disk is the stale one.
write_if_changed() {
    local path="$1" content="$2"
    [[ -f "$path" && "$(< "$path")" == "$content" ]] && return 1
    if ! mkdir -p "$(dirname "$path")" || ! printf '%s\n' "$content" > "$path"; then
        print_error "could not write $path"
        exit 1
    fi
}

# continuum writes this unit once and never revisits it, so a tmux that moved
# from apt to Homebrew leaves ExecStart pointing at a binary that is gone. Worse,
# its template ends with ExecStop=<resurrect>/save.sh, and systemd runs ExecStop
# after the main process has already died on its own: save.sh finds no server,
# dumps nothing, and repoints "last" at the empty file it just wrote. That is how
# this machine lost its frame on 2026-08-11 and again on 2026-08-22, both times
# to an OOM kill. tmux-save.timer is the saver now, so this unit only starts and
# stops the server. The whole file is compared and rewritten rather than
# patched, because the content is a pure function of the tmux path and the bad
# ExecStop is already out there.
boot_unit() {
    local tmux_path="$1"
    cat <<EOF
[Unit]
Description=tmux default session (detached)
Documentation=man:tmux(1)

[Service]
Type=forking
Environment=DISPLAY=:0
ExecStart=$tmux_path new-session -d
ExecStop=$tmux_path kill-server

# Agent panes share the server's cgroup, so when any child build or sim process
# gets reaped by the kernel OOM killer, the default OOMPolicy=stop would run
# ExecStop (tmux kill-server) and tear down every pane. Keep the server and all
# surviving panes alive on child OOM; only restart if tmux itself exits.
OOMPolicy=continue
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
EOF
}

# continuum's periodic save is a #() in status-right, so it only runs while a
# client is attached: tmux expands status-right on a client redraw, and
# status-interval caps how often — it does not tick without one. This machine's
# normal state is a detached server full of agents, which is exactly when the
# frame is worth the most and was being saved never.
#
# has-session is load-bearing, not politeness: with no server answering, save.sh
# still writes an empty dump and repoints "last" at it. PATH is pinned because
# save.sh shells out to a bare `tmux`, and the systemd --user PATH has no
# Homebrew on it — a bare tmux there is apt's, talking to a Homebrew server.
save_service_unit() {
    local tmux_path="$1" save_script="$PLUGIN_DIR/tmux-resurrect/scripts/save.sh"
    cat <<EOF
[Unit]
Description=Save the tmux frame with tmux-resurrect

[Service]
Type=oneshot
Environment=PATH=$(dirname "$tmux_path"):/usr/bin:/bin
ExecStart=/bin/sh -c 'if $tmux_path has-session 2>/dev/null; then exec $save_script quiet; fi'
EOF
}

save_timer_unit() {
    cat <<'EOF'
[Unit]
Description=Save the tmux frame every 5 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF
}

install_units() {
    local unit_dir="$HOME/.config/systemd/user" tmux_path changed=false
    tmux_path="$(command -v tmux)"

    write_if_changed "$unit_dir/tmux.service" "$(boot_unit "$tmux_path")" && changed=true
    write_if_changed "$unit_dir/tmux-save.service" "$(save_service_unit "$tmux_path")" &&
        changed=true
    write_if_changed "$unit_dir/tmux-save.timer" "$(save_timer_unit)" && changed=true

    if [[ "$changed" == true ]]; then
        if ! systemctl --user daemon-reload; then
            print_error "wrote tmux units but 'systemctl --user daemon-reload' failed"
            return 1
        fi
        print_updated "tmux systemd units for $tmux_path"
    else
        print_success "tmux systemd units already run $tmux_path"
    fi

    if systemctl --user is-enabled --quiet tmux-save.timer &&
        systemctl --user is-active --quiet tmux-save.timer; then
        print_success "tmux-save.timer already saves every 5 minutes"
    elif systemctl --user enable --now tmux-save.timer; then
        print_updated "tmux frame saves every 5 minutes (tmux-save.timer)"
    else
        print_error "could not enable tmux-save.timer"
        return 1
    fi
}

install_tmux || exit 1

if ! is_installed git; then
    print_error "git is required; install it first with 'installers/installer.sh apt'"
    exit 1
fi

install_user="$(id -un)"

# The user service kills tmux at logout unless lingering is enabled.
if command -v loginctl >/dev/null 2>&1; then
    if [ "$(loginctl show-user "$install_user" -p Linger --value 2>/dev/null)" = yes ]; then
        print_success "already lingering: $install_user (tmux survives logout)"
    elif run_as_root loginctl enable-linger "$install_user"; then
        print_updated "lingering for $install_user (tmux survives logout)"
    else
        print_warning "could not enable lingering; tmux boot support stays off"
    fi
fi

mkdir -p "$PLUGIN_DIR"

failures=0
plugins_changed=false
for entry in "${PLUGINS[@]}"; do
    IFS='|' read -r name url <<< "$entry"
    dest="$PLUGIN_DIR/$name"

    if [ -d "$dest/.git" ]; then
        head_before="$(git -C "$dest" rev-parse HEAD)"
        if ! git -C "$dest" pull --ff-only --quiet; then
            print_warning "could not update $name (local changes?)"
        elif [[ "$(git -C "$dest" rev-parse HEAD)" == "$head_before" ]]; then
            print_success "up to date: $name"
        else
            print_updated "$name"
            plugins_changed=true
        fi
        continue
    fi

    if [ -e "$dest" ]; then
        print_error "$dest exists but is not a git checkout; remove it and re-run"
        failures=$((failures + 1))
        continue
    fi

    echo "Cloning $name..."
    if git clone --depth 1 --quiet "$url" "$dest"; then
        print_installed "$name"
        plugins_changed=true
    else
        print_error "Failed to clone $name"
        failures=$((failures + 1))
    fi
done

if (( failures > 0 )); then
    exit 1
fi

install_units || exit 1

# A running server only picks up new plugin code on a reload.
if [[ "$plugins_changed" == true ]] && tmux info >/dev/null 2>&1; then
    if tmux source-file "$HOME/.config/tmux/tmux.conf" 2>/dev/null; then
        print_success "reloaded running tmux server"
    else
        print_warning "plugins installed; reload tmux with: tmux source-file ~/.config/tmux/tmux.conf"
    fi
fi
