#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/steps.sh
source "$SCRIPT_DIR/lib/steps.sh"

# One entry point. Darwin never sees Linux profiles; macos/install.sh owns
# packages + config there. just install / just config both come through here.
if [[ "$(uname -s)" == Darwin ]]; then
    exec bash "$SCRIPT_DIR/../macos/install.sh" "$@"
fi

# Registry order is execution order. Profiles only choose from these names.
COMPONENTS=(
    "apt|APT packages|apt/install.sh|yes"
    "nvidia-driver|Recommended NVIDIA driver|nvidia-driver/install.sh|yes"
    "docker|Docker Engine|docker/install.sh|yes"
    "flatpak|Flatpak apps|flatpak/install.sh|yes"
    "snap|Snap packages|snap/install.sh|yes"
    "desktop-apps|Personal desktop apps|desktop-apps/install.sh|yes"
    "homebrew|Homebrew packages|homebrew/install.sh|yes"
    "uv|uv Python toolchain|uv/install.sh|no"
    "wandb|Weights & Biases|wandb/install.sh|no"
    "netron|Netron model viewer|netron/install.sh|no"
    "npm|npm global packages|npm/install.sh|yes"
    "pnpm|pnpm global packages|pnpm/install.sh|no"
    "pip|pip user packages|pip/install.sh|no"
    "pipx|pipx apps|pipx/install.sh|no"
    "tailscale|Tailscale|tailscale/install.sh|yes"
    "bazelisk|Bazelisk|bazelisk/install.sh|yes"
    "buildtools|Bazel build tools|buildtools/install.sh|yes"
    "gh|GitHub CLI|gh/install.sh|yes"
    "opencode|OpenCode|opencode/install.sh|no"
    "claude|Claude Code|claude/install.sh|no"
    "codex|Codex CLI|codex/install.sh|yes"
    "grok|Grok Build|grok/install.sh|no"
    "agy|Antigravity CLI|agy/install.sh|no"
    "ollama|Ollama|ollama/install.sh|yes"
    "cargo|Rust and Cargo packages|cargo/install.sh|yes"
    "zoxide|zoxide|zoxide/install.sh|no"
    "openrgb|OpenRGB|openrgb/install.sh|yes"
    "lazyvim|Neovim and LazyVim|lazyvim/install.sh|yes"
    "tmux|tmux session persistence|tmux/install.sh|yes"
    "robotics|Intel RealSense|robotics/install.sh|yes"
    "config|Tracked config|config/install.sh|yes"
)

usage() {
    cat <<EOF
Usage:
  $0 <profile-or-component>... [--optionals]
  $0 plan <profile-or-component>...
  $0 list

Examples:
  $0 datacenter              Bootstrap a root-owned GPU host
  $0 workstation             Install the workstation profile
  $0 workstation desktop-apps  Include personal desktop applications
  $0 datacenter ollama       Add a component to a profile
  $0 uv cargo config         Install selected components
  $0 plan datacenter         Print the resolved plan without changing anything

Run '$0 list' to see profiles and components.
EOF
}

component_exists() {
    local target="$1" entry name
    for entry in "${COMPONENTS[@]}"; do
        IFS='|' read -r name _ _ _ <<< "$entry"
        [[ "$name" == "$target" ]] && return 0
    done
    return 1
}

add_requested_component() {
    local component="$1"
    # bash 3.2 + set -u treats "${arr[@]}" as unbound when arr is empty.
    if ((${#REQUESTED_COMPONENTS[@]} > 0)) &&
        contains_item "$component" "${REQUESTED_COMPONENTS[@]}"; then
        return
    fi
    REQUESTED_COMPONENTS+=("$component")
}

load_profile() {
    local name="$1" profile_file="$SCRIPT_DIR/profiles/$1.conf" component

    if [[ -n "$SELECTED_PROFILE" ]]; then
        print_error "Choose one profile; got '$SELECTED_PROFILE' and '$name'"
        return 1
    fi

    PROFILE_COMPONENTS=()
    PROFILE_APT_PACKAGES_FILE=""
    # shellcheck disable=SC1090
    source "$profile_file"
    SELECTED_PROFILE="$name"
    for component in "${PROFILE_COMPONENTS[@]}"; do
        if ! component_exists "$component"; then
            print_error "Profile '$name' names unknown component '$component'"
            return 1
        fi
        add_requested_component "$component"
    done
}

list_targets() {
    local profile_file entry name label

    echo "Profiles"
    for profile_file in "$SCRIPT_DIR"/profiles/*.conf; do
        PROFILE_DESCRIPTION=""
        # shellcheck disable=SC1090
        source "$profile_file"
        printf '  %-14s %s\n' "$(basename "$profile_file" .conf)" "$PROFILE_DESCRIPTION"
    done

    echo
    echo "Components"
    for entry in "${COMPONENTS[@]}"; do
        IFS='|' read -r name label _ _ <<< "$entry"
        printf '  %-14s %s\n' "$name" "$label"
    done
}

PLAN_ONLY=false
INSTALL_OPTIONALS=false
SELECTED_PROFILE=""
PROFILE_APT_PACKAGES_FILE=""
REQUESTED_COMPONENTS=()

if (( $# == 0 )); then
    usage
    exit 1
fi

case "$1" in
    -h|--help|help)
        usage
        exit 0
        ;;
    list)
        list_targets
        exit 0
        ;;
    plan)
        PLAN_ONLY=true
        shift
        ;;
esac

if (( $# == 0 )); then
    print_error "No profile or component selected"
    usage
    exit 1
fi

for target in "$@"; do
    case "$target" in
        --optionals)
            INSTALL_OPTIONALS=true
            ;;
        -* )
            print_error "Unknown option: $target"
            exit 1
            ;;
        *)
            if [[ -f "$SCRIPT_DIR/profiles/$target.conf" ]]; then
                load_profile "$target" || exit 1
            elif component_exists "$target"; then
                add_requested_component "$target"
            else
                print_error "Unknown profile or component: $target"
                echo "Run '$0 list' to see valid targets."
                exit 1
            fi
            ;;
    esac
done

if (( ${#REQUESTED_COMPONENTS[@]} == 0 )); then
    print_error "No profile or component selected"
    exit 1
fi

SELECTED_COMPONENTS=()
SELECTED_LABELS=()
SELECTED_SCRIPTS=()
needs_sudo=false
for entry in "${COMPONENTS[@]}"; do
    IFS='|' read -r name label script uses_sudo <<< "$entry"
    if contains_item "$name" "${REQUESTED_COMPONENTS[@]}"; then
        SELECTED_COMPONENTS+=("$name")
        SELECTED_LABELS+=("$label")
        SELECTED_SCRIPTS+=("$script")
        [[ "$uses_sudo" == yes ]] && needs_sudo=true
    fi
done

step_total=${#SELECTED_COMPONENTS[@]}
subtitle="$(plural "$step_total" step)"
[[ -n "$SELECTED_PROFILE" ]] && subtitle="$SELECTED_PROFILE · $subtitle"

if [[ "$PLAN_ONLY" == true ]]; then
    print_header "Linux Utils Installer"
    printf '%s  %s%s\n' "$BOLD" "$subtitle" "$NC"
    for label in "${SELECTED_LABELS[@]}"; do
        echo "  · $label"
    done
    exit 0
fi

export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none
export NEEDRESTART_MODE=a
[[ "$INSTALL_OPTIONALS" == true ]] && export INSTALLER_INSTALL_OPTIONALS=1
[[ -n "$PROFILE_APT_PACKAGES_FILE" ]] && \
    export INSTALLER_APT_PACKAGES_FILE="$PROFILE_APT_PACKAGES_FILE"

start_steps "Linux Utils Installer" "$subtitle" "$step_total" || exit 1

if [[ "$needs_sudo" == true ]]; then
    start_sudo_session || exit 1
    trap stop_sudo_session EXIT
fi

for index in "${!SELECTED_COMPONENTS[@]}"; do
    run_step "${SELECTED_COMPONENTS[$index]}" "${SELECTED_LABELS[$index]}" \
        bash "$SCRIPT_DIR/${SELECTED_SCRIPTS[$index]}"
done

finish_steps
