#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../installers/lib/common.sh
source "$REPO_ROOT/installers/lib/common.sh"
# shellcheck source=../installers/lib/steps.sh
source "$REPO_ROOT/installers/lib/steps.sh"
# shellcheck source=../installers/components.sh
source "$REPO_ROOT/installers/components.sh"

PACKAGES_FILE="$SCRIPT_DIR/brew.txt"

usage() {
    cat <<USAGE
Usage:
  $0 [workstation] [<component>...]
  $0 config [<component>...]
  $0 <component>...
  $0 plan [workstation|config|<component>...]
  $0 list

On macOS this installs Homebrew packages from brew.txt and upgrades everything
Homebrew holds, upgrades every cross-platform component already installed
(installing one when named), and syncs tracked config (AeroSpace, Warp OSC 52,
agent skills, editor, tmux, screenshots). Linux-only profiles do not run here.
USAGE
}

list_targets() {
    local entry name label command
    echo "macOS"
    printf '  %-14s %s\n' "install" "Homebrew, upgrades of installed components, AeroSpace, Warp OSC 52, screenshots, and tracked agent config"
    printf '  %-14s %s\n' "config" "AeroSpace, Warp OSC 52, screenshots, and tracked agent/editor config"
    echo
    echo "Components"
    for entry in "${COMPONENTS[@]}"; do
        IFS='|' read -r name label _ command <<< "$entry"
        [[ "$command" == - ]] || printf '  %-14s %s\n' "$name" "$label"
    done
}

# macos_component <name>: the registry entry of a component that runs here.
macos_component() {
    local entry command
    entry="$(find_component "$1")" || return 1
    IFS='|' read -r _ _ _ command <<< "$entry"
    [[ "$command" != - ]] && printf '%s\n' "$entry"
}

install_packages() {
    local brew_path had_failure=false
    if ! brew_path="$(command -v brew)"; then
        print_error "Homebrew is required: https://brew.sh"
        return 1
    fi
    install_brew_package_list "$brew_path" "$PACKAGES_FILE" || had_failure=true
    upgrade_brew_packages "$brew_path" || had_failure=true
    [[ "$had_failure" == false ]]
}

# On PATH, or where a vendor installer puts it: a non-login shell's PATH can
# lack those directories, and the components add them.
component_installed() {
    local dir
    command -v "$1" >/dev/null 2>&1 && return 0
    for dir in "$HOME/.local/bin" "$HOME/.grok/bin" "$HOME/.opencode/bin" "$HOME/.cargo/bin"; do
        [[ -x "$dir/$1" ]] && return 0
    done
    return 1
}

select_component() {
    local name label
    IFS='|' read -r name label _ <<< "$1"
    if (( ${#SELECTED_COMPONENTS[@]} == 0 )) ||
       ! contains_item "$name" "${SELECTED_COMPONENTS[@]}"; then
        SELECTED_COMPONENTS+=("$name")
        SELECTED_LABELS+=("$label")
    fi
}

print_plan() {
    local label
    print_header "macOS installer"
    [[ "$DO_PACKAGES" == true ]] && echo "  · Homebrew packages"
    if (( ${#SELECTED_LABELS[@]} > 0 )); then
        for label in "${SELECTED_LABELS[@]}"; do
            echo "  · $label"
        done
    fi
    if [[ "$DO_CONFIG" == true ]]; then
        echo "  · Agent config (includes Warp OSC 52)"
        echo "  · Screenshots saved to ~/Pictures/screenshots"
    fi
}

if [[ "$(uname -s)" != Darwin ]]; then
    print_error "The macOS installer must run on macOS."
    exit 1
fi

PLAN_ONLY=false
case "${1:-}" in
    -h | --help | help)
        usage
        exit 0
        ;;
    list | --list)
        list_targets
        exit 0
        ;;
    plan | --plan)
        PLAN_ONLY=true
        shift
        ;;
esac

seen_config=false
seen_workstation=false
SELECTED_COMPONENTS=()
SELECTED_LABELS=()

if (( $# == 0 )); then
    seen_workstation=true
fi

for arg in "$@"; do
    case "$arg" in
        "" | workstation | install)
            seen_workstation=true
            ;;
        config)
            seen_config=true
            ;;
        -h | --help | help)
            usage
            exit 0
            ;;
        list | --list)
            list_targets
            exit 0
            ;;
        *)
            if comp_entry="$(macos_component "$arg")"; then
                select_component "$comp_entry"
            else
                print_error "Target '$arg' is not supported on macOS."
                echo "Run '$0 list' for macOS targets."
                exit 1
            fi
            ;;
    esac
done

DO_PACKAGES=false
DO_CONFIG=false
if [[ "$seen_workstation" == true ]]; then
    DO_PACKAGES=true
    DO_CONFIG=true
    # Upgrade what is installed; naming a component is what installs it.
    for entry in "${COMPONENTS[@]}"; do
        IFS='|' read -r _ _ _ command <<< "$entry"
        [[ "$command" != - ]] && component_installed "$command" && select_component "$entry"
    done
elif [[ "$seen_config" == true ]]; then
    DO_CONFIG=true
fi

if [[ "$PLAN_ONLY" == true ]]; then
    print_plan
    exit 0
fi

step_total=${#SELECTED_COMPONENTS[@]}
[[ "$DO_PACKAGES" == true ]] && step_total=$((step_total + 1))
[[ "$DO_CONFIG" == true ]] && step_total=$((step_total + 1))
start_steps "macOS installer" "$(plural "$step_total" step)" "$step_total" || exit 1

if [[ "$DO_PACKAGES" == true ]]; then
    run_step packages "Homebrew packages" install_packages
fi

if (( ${#SELECTED_COMPONENTS[@]} > 0 )); then
    for idx in "${!SELECTED_COMPONENTS[@]}"; do
        run_step "${SELECTED_COMPONENTS[$idx]}" "${SELECTED_LABELS[$idx]}" \
            bash "$REPO_ROOT/installers/${SELECTED_COMPONENTS[$idx]}/install.sh"
    done
fi

if [[ "$DO_CONFIG" == true ]]; then
    run_step config "Tracked config" bash "$REPO_ROOT/installers/config/install.sh"
fi

finish_steps
