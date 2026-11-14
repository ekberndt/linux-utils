#!/bin/bash

# Shared helpers for every installer. Sourcing this also loads packages.sh.

_term_style() {
    if command -v tput >/dev/null 2>&1; then
        tput "$@" 2>/dev/null || true
    fi
}

# shellcheck disable=SC2034  # DIM is for steps.sh.
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    RED="$(_term_style bold)""$(_term_style setaf 1)"
    GREEN="$(_term_style bold)""$(_term_style setaf 2)"
    YELLOW="$(_term_style bold)""$(_term_style setaf 3)"
    BLUE="$(_term_style bold)""$(_term_style setaf 6)"
    BOLD="$(_term_style bold)"
    DIM="$(_term_style dim)"
    NC="$(_term_style sgr0)"
else
    RED="" GREEN="" YELLOW="" BLUE="" BOLD="" DIM="" NC=""
fi

# A box sized to its title rather than the terminal, so nothing re-wraps on
# resize and a short heading does not get a full-width rule.
print_header() {
    local title="$1" rule
    printf -v rule '%*s' $(( ${#title} + 2 )) ''
    rule="${rule// /─}"

    printf '\n%s╭%s╮%s\n' "$BLUE" "$rule" "$NC"
    printf '%s│%s %s%s%s %s│%s\n' "$BLUE" "$NC" "$BOLD" "$title" "$NC" "$BLUE" "$NC"
    printf '%s╰%s╯%s\n' "$BLUE" "$rule" "$NC"
}
print_success() { echo "${GREEN}✓ $1${NC}"; }
print_warning() { echo "${YELLOW}⚠ $1${NC}"; record_status warn "$1"; }
print_error() { echo "${RED}✗ $1${NC}"; record_status error "$1"; }

# What a step changed, for the step runner (steps.sh) to summarise. A step that
# records nothing is already current. Run standalone, a component only prints.
record_status() {
    [[ -n "${INSTALLER_STATUS_FILE:-}" ]] || return 0
    printf '%s\t%s\n' "$1" "$2" >> "$INSTALLER_STATUS_FILE"
}
print_installed() { print_success "Successfully installed: $1"; record_status installed "$1"; }
print_updated() { print_success "Updated: $1"; record_status updated "$1"; }
print_skipped() { echo "Skipped: $1"; record_status skipped "$1"; }

# Run a system-level command directly for root and through sudo otherwise.
run_as_root() {
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

SUDO_KEEPALIVE_PID=""

start_sudo_session() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] && return 0

    echo "Authenticating sudo once for this installation..."
    sudo -v || return 1

    # Long source builds can outlive sudo's timestamp. The loop lives as long as
    # the installer, not until the first refresh that fails: a single failure
    # (apt replacing sudo mid-run, a cleared /run/sudo/ts) would otherwise leave
    # the remaining hour unauthenticated and prompt again mid-component.
    #
    # Detached from the installer's output: a `sleep` outlives the kill in
    # stop_sudo_session, and holding stdout would stall anything reading it.
    local installer_pid=$$
    (
        while sleep 60; do
            kill -0 "$installer_pid" 2>/dev/null || exit
            sudo -n -v >/dev/null 2>&1 || true
        done
    ) </dev/null >/dev/null 2>&1 &
    SUDO_KEEPALIVE_PID=$!
}

stop_sudo_session() {
    [[ -n "$SUDO_KEEPALIVE_PID" ]] || return 0
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    SUDO_KEEPALIVE_PID=""
}

is_installed() {
    command -v "$1" &>/dev/null
}

contains_item() {
    local needle="$1"
    shift
    local item

    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

# Honors PCI_DEVICES_DIR so tests can stand in for /sys.
has_nvidia_gpu() {
    local device

    for device in "${PCI_DEVICES_DIR:-/sys/bus/pci/devices}"/*; do
        [[ -f "$device/vendor" && -f "$device/class" ]] || continue
        [[ "$(< "$device/vendor")" == 0x10de ]] || continue
        case "$(< "$device/class")" in
            0x030000|0x030200) return 0 ;;
        esac
    done
    return 1
}

require_file() {
    if [[ ! -f "$1" ]]; then
        print_error "File not found: $1"
        exit 1
    fi
}

# Output non-empty, non-comment lines from a package list file.
read_package_list() {
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        echo "$line"
    done < "$1"
}

detect_arch() {
    case "$(uname -m)" in
        x86_64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *)
            print_error "Unsupported architecture: $(uname -m)"
            return 1
            ;;
    esac
}

# install_each <label> <install-fn> <verify-fn> <package>...
# Install one package at a time, reporting each. Fails if any package failed.
install_each() {
    local label="$1" install_fn="$2" verify_fn="$3"
    shift 3
    local package had_failure=false

    for package in "$@"; do
        if "$verify_fn" "$package"; then
            print_success "Already installed: $package"
            continue
        fi
        echo "Installing: $package ($label)"
        if "$install_fn" "$package"; then
            print_installed "$package"
        else
            print_error "Failed to install: $package"
            had_failure=true
        fi
    done

    [[ "$had_failure" == false ]]
}

# install_batch <label> <install-fn> <verify-fn> <package>...
# One transaction so dependencies solve together, falling back to one-at-a-time
# so a single broken package cannot take the whole list down with it.
install_batch() {
    local label="$1" install_fn="$2" verify_fn="$3"
    shift 3
    local package

    (($#)) || return 0

    echo "Installing $# $label: $*"
    if "$install_fn" "$@"; then
        for package in "$@"; do
            print_installed "$package"
        done
        return 0
    fi

    print_warning "Batch $label install failed; retrying individually..."
    install_each "$label" "$install_fn" "$verify_fn" "$@"
}

# The last dotted version number on stdin. Last, because `ollama --version`
# names the running server's version before the client's when they differ.
last_version() {
    grep -oE '[0-9]+(\.[0-9]+)+' | tail -n1
}

cli_version() {
    "$1" --version 2>/dev/null | last_version
}

# Echo " (1.2.3)" for a command that reports a version, and nothing otherwise;
# not every CLI here answers --version.
version_suffix() {
    local version
    version="$(cli_version "$1")"
    printf '%s' "${version:+ ($version)}"
}

# version_newer <candidate> <installed>: whether candidate is the later
# version, compared field by field on their dotted numbers, so a tag's "v"
# drops out. Plain bash rather than `sort -V`, which older macOS lacks.
version_newer() {
    local -a candidate installed
    local i
    IFS=. read -ra candidate <<<"$(last_version <<<"$1")"
    IFS=. read -ra installed <<<"$(last_version <<<"$2")"
    for (( i = 0; i < ${#candidate[@]} || i < ${#installed[@]}; i++ )); do
        (( 10#${candidate[i]:-0} != 10#${installed[i]:-0} )) || continue
        (( 10#${candidate[i]:-0} > 10#${installed[i]:-0} ))
        return
    done
    return 1
}

# latest_release <owner/repo>: the tag GitHub's /releases/latest lands on, not
# the REST API and its unauthenticated rate limit. Follow every redirect: a
# moved repository (buildtools left bazelbuild for bazel-contrib) redirects to
# its new name first.
latest_release() {
    local url
    url="$(curl -fsSIL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest")" ||
        return 1
    [[ "$url" == */releases/tag/* ]] || return 1
    printf '%s\n' "${url##*/releases/tag/}"
}

# install_release_binary <owner/repo> <tag> <asset> <dest>
# Download whole before installing, so a failed download never truncates the
# binary already in place.
install_release_binary() {
    local tmp rc=0
    tmp="$(mktemp)" || return 1
    curl -fsSL "https://github.com/$1/releases/download/$2/$3" -o "$tmp" &&
        run_as_root install -m 0755 "$tmp" "$4" || rc=$?
    rm -f "$tmp"
    return "$rc"
}

# The hourly rule for package indexes: refreshed within the hour, by this run
# or anything else, is fresh enough to decide what is outdated.
refreshed_within_hour() {
    [[ -n "$(find "$1" -mmin -60 2>/dev/null)" ]]
}

# report_upgraded <due> <due-command>...
# <due> is what a manager listed as outdated before upgrading, one item per
# line, its name first. Ask again: what left the list was upgraded, and what
# is still listed is a warning, since the manager declined it (a hold, a pin,
# a running app) while exiting 0.
report_upgraded() {
    local due="$1" still line
    shift
    if ! still="$("$@")"; then
        print_warning "Could not recheck after upgrading: $*"
        still=""
    fi
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if awk -v name="${line%% *}" '$1 == name { found = 1 } END { exit !found }' <<<"$still"; then
            print_warning "Still outdated after upgrading: $line"
        else
            print_updated "$line"
        fi
    done <<<"$due"
}

# pip reads an unreachable index as nothing newer: `pip list --outdated` lists
# nothing and `pip install --upgrade` is already satisfied, both exiting 0.
# Asking the index for pip's own versions fails outright instead.
# pip_index_reachable <pip-command>...
pip_index_reachable() {
    "$@" index versions pip >/dev/null 2>&1
}

# report_version_changes <before> <after>: two "name version" listings taken
# around an upgrade. A new name was installed; a moved version was updated.
report_version_changes() {
    local name version old
    while read -r name version _; do
        [[ -n "$name" ]] || continue
        if ! old="$(awk -v name="$name" \
            '$1 == name { print $2; found = 1; exit } END { exit !found }' <<<"$1")"; then
            print_installed "$name $version"
        elif [[ "$old" != "$version" ]]; then
            print_updated "$name $old -> $version"
        fi
    done <<<"$2"
}

# Vendor install scripts drop binaries into ~/.local/bin, which is often absent
# from PATH during non-login installer runs.
use_local_bin() {
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) export PATH="$HOME/.local/bin:$PATH" ;;
    esac
}

# update_cli <name> <command>...
# Run an updater and report the version it moved <name> to. The updater
# decides whether anything is newer.
update_cli() {
    local name="$1" before after
    shift
    before="$(cli_version "$name")"
    if ! "$@"; then
        print_error "Failed to update $name"
        return 1
    fi
    after="$(cli_version "$name")"
    [[ "$after" == "$before" ]] || print_updated "$name $before -> $after"
}

# install_or_update <name> <url> <interpreter> <update-command>...
# The vendor script installs a missing CLI; an installed one updates itself.
install_or_update() {
    local name="$1" url="$2" interpreter="$3"
    shift 3
    use_local_bin
    if is_installed "$name"; then
        update_cli "$name" "$@"
    else
        install_from_web_script "$name" "$url" "$interpreter"
    fi
}

# reinstall_if_outdated <name> <owner/repo> <url> <interpreter>
# The updater for a CLI without one: re-run the vendor script when the latest
# GitHub release is newer than the installed version.
reinstall_if_outdated() {
    local name="$1" repo="$2" url="$3" interpreter="$4" installed latest
    installed="$(cli_version "$name")"
    if [[ -z "$installed" ]]; then
        print_error "Could not read the installed $name version"
        return 1
    fi
    if ! latest="$(latest_release "$repo")"; then
        print_error "Could not find the latest $repo release"
        return 1
    fi
    version_newer "$latest" "$installed" || return 0
    echo "Updating $name $installed -> ${latest#v}..."
    curl -fsSL "$url" | "$interpreter" || return 1
    # A vendor script can lose its download and still exit 0.
    installed="$(cli_version "$name")"
    if version_newer "$latest" "$installed"; then
        print_error "$name is still ${installed:-unreadable} after reinstalling; the latest is ${latest#v}"
        return 1
    fi
}

# install_from_web_script <name> <url> [interpreter]
# The vendor-hosted "curl | sh" install behind install_or_update, and
# tailscale's. Returns early when the command is already on PATH.
install_from_web_script() {
    local name="$1" url="$2" interpreter="${3:-sh}"

    use_local_bin

    if is_installed "$name"; then
        print_success "Already installed: $name$(version_suffix "$name")"
        return 0
    fi

    echo "Installing $name..."
    if ! curl -fsSL "$url" | "$interpreter"; then
        print_error "Failed to install $name"
        return 1
    fi

    if ! is_installed "$name"; then
        print_error "Install script finished but $name is not on PATH"
        return 1
    fi
    print_installed "$name$(version_suffix "$name")"
}

BREW_CANDIDATES=(
    "/home/linuxbrew/.linuxbrew/bin/brew"
    "$HOME/.linuxbrew/bin/brew"
    "/opt/homebrew/bin/brew"
    "/usr/local/bin/brew"
)

# Echo a runnable brew binary. Homebrew is not on a non-login installer's PATH,
# so fall back to the standard prefixes before giving up.
find_brew() {
    local candidate path

    if path="$(command -v brew 2>/dev/null)" && [[ -x "$path" ]] &&
        "$path" --version >/dev/null 2>&1; then
        echo "$path"
        return 0
    fi

    for candidate in "${BREW_CANDIDATES[@]}"; do
        if [[ -x "$candidate" ]] && "$candidate" --version >/dev/null 2>&1; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

# append_shell_rc_line <file> <marker> <comment> <line>
# Append <line> to a shell rc file unless <marker> is already in it.
append_shell_rc_line() {
    local rc="$1" marker="$2" comment="$3" line="$4"

    if ! touch "$rc"; then
        print_warning "Could not update $rc"
        return 1
    fi

    grep -Fq "$marker" "$rc" && return 0

    if ! printf '\n%s\n%s\n' "$comment" "$line" >> "$rc"; then
        print_warning "Could not update $rc"
        return 1
    fi
    print_updated "$rc ($comment)"
}

# configure_shell_rcs <marker> <comment> <line>
# Apply append_shell_rc_line to every login shell file this repo manages.
configure_shell_rcs() {
    append_shell_rc_line "$HOME/.profile" "$@"
    append_shell_rc_line "$HOME/.bashrc" "$@"

    if [[ "${SHELL:-}" == */zsh ]]; then
        append_shell_rc_line "$HOME/.zprofile" "$@"
    fi
}

# shellcheck source=packages.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/packages.sh"
