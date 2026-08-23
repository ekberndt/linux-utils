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
            print_success "Installed tmux ($(tmux -V))"
            return 0
        fi
        print_error "Failed to install tmux"
        return 1
    fi

    if ! brew_path="$(find_brew)"; then
        print_error "Homebrew is required to install tmux. Run 'installers/installer.sh homebrew' first."
        return 1
    fi

    if "$brew_path" list --formula tmux >/dev/null 2>&1; then
        print_success "tmux already installed via Homebrew"
    elif ! "$brew_path" install tmux; then
        print_error "Failed to install tmux"
        return 1
    fi

    eval "$("$brew_path" shellenv)"
    hash -r
    print_success "Installed stable tmux ($(tmux -V))"
}

# continuum writes this unit once and never revisits it, so a tmux that moved
# from apt to Homebrew leaves ExecStart pointing at a binary that is gone. Worse,
# its template ends with ExecStop=<resurrect>/save.sh, and systemd runs ExecStop
# after the main process has already died on its own: save.sh finds no server,
# dumps nothing, and repoints "last" at the empty file it just wrote. That is how
# this machine lost its frame on 2026-08-11 and again on 2026-08-22, both times
# to an OOM kill. tmux-save.timer is the saver now, so this unit only starts and
# stops the server. Written every run rather than patched, because the content is
# a pure function of the tmux path and the bad ExecStop is already out there.
write_boot_unit() {
    local unit="$HOME/.config/systemd/user/tmux.service"
    local tmux_path
    tmux_path="$(command -v tmux)"

    mkdir -p "$(dirname "$unit")"
    cat > "$unit" <<EOF
[Unit]
Description=tmux default session (detached)
Documentation=man:tmux(1)

[Service]
Type=forking
Environment=DISPLAY=:0
ExecStart=$tmux_path new-session -d
ExecStop=$tmux_path kill-server

# Agent panes share the server's cgroup, so systemd-oomd accounts their memory
# here and reaps this unit first. Come back and let continuum restore, instead of
# sitting failed until someone notices — which is where 2026-08-22 left it.
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
EOF

    if systemctl --user daemon-reload; then
        print_success "tmux boot service runs $tmux_path"
        return 0
    fi
    print_error "wrote $unit but 'systemctl --user daemon-reload' failed"
    return 1
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
install_save_timer() {
    local unit_dir="$HOME/.config/systemd/user"
    local tmux_path save_script
    tmux_path="$(command -v tmux)"
    save_script="$PLUGIN_DIR/tmux-resurrect/scripts/save.sh"

    mkdir -p "$unit_dir"
    cat > "$unit_dir/tmux-save.service" <<EOF
[Unit]
Description=Save the tmux frame with tmux-resurrect

[Service]
Type=oneshot
Environment=PATH=$(dirname "$tmux_path"):/usr/bin:/bin
ExecStart=/bin/sh -c 'if $tmux_path has-session 2>/dev/null; then exec $save_script quiet; fi'
EOF

    cat > "$unit_dir/tmux-save.timer" <<'EOF'
[Unit]
Description=Save the tmux frame every 5 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF

    if systemctl --user daemon-reload &&
        systemctl --user enable --now tmux-save.timer; then
        print_success "tmux frame saves every 5 minutes (tmux-save.timer)"
        return 0
    fi
    print_error "could not enable tmux-save.timer"
    return 1
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
        print_success "enabled lingering: $install_user (tmux survives logout)"
    else
        print_warning "could not enable lingering; tmux boot support stays off"
    fi
fi

mkdir -p "$PLUGIN_DIR"

failures=0
for entry in "${PLUGINS[@]}"; do
    IFS='|' read -r name url <<< "$entry"
    dest="$PLUGIN_DIR/$name"

    if [ -d "$dest/.git" ]; then
        if git -C "$dest" pull --ff-only --quiet; then
            print_success "up to date: $name"
        else
            print_warning "could not update $name (local changes?)"
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
        print_success "Successfully installed: $name"
    else
        print_error "Failed to clone $name"
        failures=$((failures + 1))
    fi
done

if (( failures > 0 )); then
    exit 1
fi

write_boot_unit || exit 1
install_save_timer || exit 1

if tmux info >/dev/null 2>&1; then
    if tmux source-file "$HOME/.config/tmux/tmux.conf" 2>/dev/null; then
        print_success "reloaded running tmux server"
    else
        print_warning "plugins installed; reload tmux with: tmux source-file ~/.config/tmux/tmux.conf"
    fi
fi
