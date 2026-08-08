#!/bin/bash

# Shared utilities for all installer scripts

_term_style() {
    if command -v tput >/dev/null 2>&1; then
        tput "$@" 2>/dev/null || true
    fi
}

if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
    RED="$(_term_style bold)""$(_term_style setaf 1)"
    GREEN="$(_term_style bold)""$(_term_style setaf 2)"
    YELLOW="$(_term_style bold)""$(_term_style setaf 3)"
    BLUE="$(_term_style bold)""$(_term_style setaf 6)"
    WHITE="$(_term_style bold)""$(_term_style setaf 7)"
    BOLD="$(_term_style bold)"
    NC="$(_term_style sgr0)"
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    WHITE=""
    BOLD=""
    NC=""
fi

print_header() {
    local title="$1"
    local width
    width="$(tput cols 2>/dev/null || echo 80)"

    local rule=""
    printf -v rule "%*s" "$width" ""
    printf "%s%s%s\n" "${BLUE}${BOLD}" "${rule// /-}" "${NC}"

    local visible_title="$title"
    if (( ${#visible_title} > width )); then
        visible_title="${visible_title:0:width}"
    fi

    local left_padding=$(( (width - ${#visible_title}) / 2 ))
    local right_padding=$(( width - ${#visible_title} - left_padding ))
    printf "%s%*s%s%*s%s\n" \
        "${WHITE}${BOLD}" \
        "$left_padding" "" \
        "$visible_title" \
        "$right_padding" "" \
        "${NC}"

    printf "%s%s%s\n" "${BLUE}${BOLD}" "${rule// /-}" "${NC}"
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

    # Long source builds can outlive sudo's timestamp. Refresh it without
    # prompting so later components reuse the credential established above.
    (
        while sleep 60; do
            sudo -n -v >/dev/null 2>&1 || exit
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

# Check if a command is available
# Usage: is_installed "uv" && exit 0
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

# Exit with error if file does not exist
# Usage: require_file "$PACKAGES_FILE"
require_file() {
    if [ ! -f "$1" ]; then
        print_error "File not found: $1"
        exit 1
    fi
}

# Output non-empty, non-comment lines from a package list file
# Usage: read_package_list "$FILE" | while IFS= read -r line; do ...; done
read_package_list() {
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        echo "$line"
    done < "$1"
}

# Detect architecture and output amd64/arm64
# Usage: ARCH_SUFFIX="$(detect_arch)"
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
