#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Registry order is execution order. Profiles only choose from these names.
COMPONENTS=(
    "apt|APT packages|apt/install.sh|yes"
    "nvidia-driver|Recommended NVIDIA driver|nvidia-driver/install.sh|yes"
    "docker|Docker Engine|docker/install.sh|yes"
    "flatpak|Flatpak packages|flatpak/install.sh|yes"
    "snap|Snap packages|snap/install.sh|yes"
    "desktop-apps|Personal desktop apps|desktop-apps/install.sh|yes"
    "homebrew|Homebrew packages|homebrew/install.sh|yes"
    "uv|uv Python toolchain|uv/install.sh|yes"
    "wandb|Weights & Biases|wandb/install.sh|no"
    "tailscale|Tailscale|tailscale/install.sh|yes"
    "bazelisk|Bazelisk|bazelisk/install.sh|yes"
    "buildtools|Bazel build tools|buildtools/install.sh|yes"
    "gh|GitHub CLI|gh/install.sh|yes"
    "claude|Claude Code|claude/install.sh|yes"
    "codex|Codex CLI|codex/install.sh|yes"
    "grok|Grok Build|grok/install.sh|no"
    "ollama|Ollama|ollama/install.sh|no"
    "cargo|Rust and Cargo packages|cargo/install.sh|no"
    "zoxide|zoxide|zoxide/install.sh|no"
    "openrgb|OpenRGB|openrgb/install.sh|no"
    "lazyvim|Neovim and LazyVim|lazyvim/install.sh|yes"
    "tmux|tmux session persistence|tmux/install.sh|no"
    "robotics|Intel RealSense|robotics/install.sh|yes"
    "config|Tracked config|config/install.sh|no"
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
    if ! contains_item "$component" "${REQUESTED_COMPONENTS[@]}"; then
        REQUESTED_COMPONENTS+=("$component")
    fi
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
needs_apt_update=false
for entry in "${COMPONENTS[@]}"; do
    IFS='|' read -r name label script refresh_apt <<< "$entry"
    if contains_item "$name" "${REQUESTED_COMPONENTS[@]}"; then
        SELECTED_COMPONENTS+=("$name")
        SELECTED_LABELS+=("$label")
        SELECTED_SCRIPTS+=("$script")
        [[ "$refresh_apt" == yes ]] && needs_apt_update=true
    fi
done

step_total=${#SELECTED_COMPONENTS[@]}
[[ "$needs_apt_update" == true ]] && step_total=$((step_total + 1))

print_header "Linux Utils Installer"
if [[ -n "$SELECTED_PROFILE" ]]; then
    printf 'Profile: %s\n' "$SELECTED_PROFILE"
fi
printf '%d steps queued\n' "$step_total"
[[ "$needs_apt_update" == true ]] && echo "  · APT package index"
for label in "${SELECTED_LABELS[@]}"; do
    echo "  · $label"
done

if [[ "$PLAN_ONLY" == true ]]; then
    exit 0
fi

# GitHub CLI now comes from Ubuntu. Remove the retired upstream source before
# refreshing APT because a missing or rotated key would block every component.
if contains_item "gh" "${SELECTED_COMPONENTS[@]}"; then
    run_as_root rm -f \
        /etc/apt/sources.list.d/github-cli.list \
        /etc/apt/keyrings/githubcli-archive-keyring.gpg
fi

[[ "$INSTALL_OPTIONALS" == true ]] && export INSTALLER_INSTALL_OPTIONALS=1
[[ -n "$PROFILE_APT_PACKAGES_FILE" ]] && \
    export INSTALLER_APT_PACKAGES_FILE="$PROFILE_APT_PACKAGES_FILE"
export INSTALLER_QUIET_CONFIG=1

step=0
if [[ "$needs_apt_update" == true ]]; then
    step=$((step + 1))
    printf '\n[%d/%d] APT package index\n' "$step" "$step_total"
    if ! run_as_root apt-get update; then
        print_error "Failed to update APT package index"
        exit 1
    fi
fi

had_failure=false
for index in "${!SELECTED_COMPONENTS[@]}"; do
    name="${SELECTED_COMPONENTS[$index]}"
    label="${SELECTED_LABELS[$index]}"
    script="$SCRIPT_DIR/${SELECTED_SCRIPTS[$index]}"
    step=$((step + 1))
    printf '\n[%d/%d] %s\n' "$step" "$step_total" "$label"

    if [[ ! -f "$script" ]]; then
        print_error "Missing installer: $script"
        had_failure=true
    elif ! bash "$script"; then
        print_error "$name failed"
        had_failure=true
    fi
done

if [[ "$had_failure" == true ]]; then
    print_error "Some components failed"
    exit 1
fi

print_success "Installation complete"
