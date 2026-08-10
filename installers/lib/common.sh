#!/bin/bash

# Shared helpers for every installer. Sourcing this also loads packages.sh.

_term_style() {
    if command -v tput >/dev/null 2>&1; then
        tput "$@" 2>/dev/null || true
    fi
}

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    RED="$(_term_style bold)""$(_term_style setaf 1)"
    GREEN="$(_term_style bold)""$(_term_style setaf 2)"
    YELLOW="$(_term_style bold)""$(_term_style setaf 3)"
    BLUE="$(_term_style bold)""$(_term_style setaf 6)"
    BOLD="$(_term_style bold)"
    NC="$(_term_style sgr0)"
else
    RED="" GREEN="" YELLOW="" BLUE="" BOLD="" NC=""
fi

# An accent bar reads as a heading at any width, so nothing has to be measured,
# centred, or re-wrapped when the terminal resizes.
print_header() {
    printf '\n%s▌%s %s%s%s\n' "$BLUE" "$NC" "$BOLD" "$1" "$NC"
}
print_success() { echo "${GREEN}✓ $1${NC}"; }
print_warning() { echo "${YELLOW}⚠ $1${NC}"; }
print_error() { echo "${RED}✗ $1${NC}"; }

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
    local installer_pid=$$
    (
        while sleep 60; do
            kill -0 "$installer_pid" 2>/dev/null || exit
            sudo -n -v >/dev/null 2>&1 || true
        done
    ) &
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

has_nvidia_gpu() {
    local device

    for device in /sys/bus/pci/devices/*; do
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
        aarch64) echo "arm64" ;;
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
            print_success "Successfully installed: $package"
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
            print_success "Successfully installed: $package"
        done
        return 0
    fi

    print_warning "Batch $label install failed; retrying individually..."
    install_each "$label" "$install_fn" "$verify_fn" "$@"
}

# Echo " (1.2.3)" for a command that reports a version, and nothing otherwise;
# not every CLI here answers --version.
version_suffix() {
    local version
    version="$("$1" --version 2>/dev/null | head -n1)" || true
    printf '%s' "${version:+ ($version)}"
}

# install_from_web_script <name> <url> [interpreter]
# The vendor-hosted "curl | sh" install used by uv, tailscale, ollama, and the
# agent CLIs. Returns early when the command is already on PATH.
install_from_web_script() {
    local name="$1" url="$2" interpreter="${3:-sh}"

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
    print_success "Successfully installed: $name$(version_suffix "$name")"
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
