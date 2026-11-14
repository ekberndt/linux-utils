#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../installers/lib/common.sh
source "$REPO_ROOT/installers/lib/common.sh"
# shellcheck source=../installers/lib/steps.sh
source "$REPO_ROOT/installers/lib/steps.sh"

PACKAGES_FILE="$SCRIPT_DIR/brew.txt"

# name|label|script|command. A plain run upgrades every component whose
# command is installed, and naming one installs it. npm through pipx install
# nothing; they upgrade what their manager already holds.
MACOS_COMPONENTS=(
    "uv|uv Python toolchain|uv/install.sh|uv"
    "wandb|Weights & Biases|wandb/install.sh|wandb"
    "opencode|OpenCode|opencode/install.sh|opencode"
    "claude|Claude Code|claude/install.sh|claude"
    "codex|Codex CLI|codex/install.sh|codex"
    "grok|Grok Build|grok/install.sh|grok"
    "agy|Antigravity CLI|agy/install.sh|agy"
    "herdr-core|herdr-core (hc)|herdr-core/install.sh|herdr-core"
    "herdr|Herdr app|herdr/install.sh|herdr-app"
    "zoxide|zoxide|zoxide/install.sh|zoxide"
    "cargo|Rust and Cargo packages|cargo/install.sh|rustup"
    "npm|npm global packages|npm/install.sh|npm"
    "pnpm|pnpm global packages|pnpm/install.sh|pnpm"
    "pip|pip user packages|pip/install.sh|python3"
    "pipx|pipx apps|pipx/install.sh|pipx"
)

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
    local entry name label
    echo "macOS"
    printf '  %-14s %s\n' "install" "Homebrew, upgrades of installed components, AeroSpace, Warp OSC 52, screenshots, and tracked agent config"
    printf '  %-14s %s\n' "config" "AeroSpace, Warp OSC 52, screenshots, and tracked agent/editor config"
    echo
    echo "Components"
    for entry in "${MACOS_COMPONENTS[@]}"; do
        IFS='|' read -r name label _ <<< "$entry"
        printf '  %-14s %s\n' "$name" "$label"
    done
}

find_macos_component() {
    local target="$1" entry name
    for entry in "${MACOS_COMPONENTS[@]}"; do
        IFS='|' read -r name _ _ <<< "$entry"
        if [[ "$name" == "$target" ]]; then
            printf '%s\n' "$entry"
            return 0
        fi
    done
    return 1
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
    local name label script
    IFS='|' read -r name label script _ <<< "$1"
    if (( ${#SELECTED_COMPONENTS[@]} == 0 )) ||
       ! contains_item "$name" "${SELECTED_COMPONENTS[@]}"; then
        SELECTED_COMPONENTS+=("$name")
        SELECTED_LABELS+=("$label")
        SELECTED_SCRIPTS+=("$script")
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
SELECTED_SCRIPTS=()

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
            if comp_entry="$(find_macos_component "$arg")"; then
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
    for entry in "${MACOS_COMPONENTS[@]}"; do
        IFS='|' read -r _ _ _ command <<< "$entry"
        component_installed "$command" && select_component "$entry"
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

if (( ${#SELECTED_SCRIPTS[@]} > 0 )); then
    for idx in "${!SELECTED_SCRIPTS[@]}"; do
        run_step "${SELECTED_COMPONENTS[$idx]}" "${SELECTED_LABELS[$idx]}" \
            bash "$REPO_ROOT/installers/${SELECTED_SCRIPTS[$idx]}"
    done
fi

if [[ "$DO_CONFIG" == true ]]; then
    run_step config "Tracked config" bash "$REPO_ROOT/installers/config/install.sh"
fi

finish_steps
