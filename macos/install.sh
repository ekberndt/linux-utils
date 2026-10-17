#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../installers/lib/common.sh
source "$REPO_ROOT/installers/lib/common.sh"

PACKAGES_FILE="$SCRIPT_DIR/brew.txt"

MACOS_COMPONENTS=(
    "uv|uv Python toolchain|uv/install.sh"
    "wandb|Weights & Biases|wandb/install.sh"
    "opencode|OpenCode|opencode/install.sh"
    "claude|Claude Code|claude/install.sh"
    "codex|Codex CLI|codex/install.sh"
    "grok|Grok Build|grok/install.sh"
    "agy|Antigravity CLI|agy/install.sh"
    "zoxide|zoxide|zoxide/install.sh"
)

usage() {
    cat <<USAGE
Usage:
  $0 [workstation] [<component>...]
  $0 config [<component>...]
  $0 <component>...
  $0 plan [workstation|config|<component>...]
  $0 list

On macOS this installs Homebrew packages from brew.txt, runs cross-platform
component installers, and syncs tracked config (AeroSpace, Warp OSC 52, agent
skills, editor, tmux, screenshots). Linux-only profiles do not run here.
USAGE
}

list_targets() {
    local entry name label
    echo "macOS"
    printf '  %-14s %s\n' "install" "Homebrew packages, AeroSpace, Warp OSC 52, screenshots, and tracked agent config"
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

brew_formula_installed() { brew list --formula "$1" >/dev/null 2>&1; }
brew_formula_install() { brew install "$@"; }
brew_cask_installed() { brew list --cask "$1" >/dev/null 2>&1; }
brew_cask_install() { brew install --cask "$@"; }

install_packages() {
    local line entry package had_failure=false
    local -a formulae=() casks=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        entry="$(printf '%s' "${line%%#*}" | xargs)"
        [[ -z "$entry" ]] && continue

        if [[ "$entry" == *" --cask" ]]; then
            package="${entry% --cask}"
            if brew_cask_installed "$package"; then
                print_success "Already installed: $package"
            else
                casks+=("$package")
            fi
        else
            if brew_formula_installed "$entry"; then
                print_success "Already installed: $entry"
            else
                formulae+=("$entry")
            fi
        fi
    done < "$PACKAGES_FILE"

    if (( ${#formulae[@]} > 0 )); then
        install_batch "brew formulae" brew_formula_install brew_formula_installed "${formulae[@]}" || had_failure=true
    fi
    if (( ${#casks[@]} > 0 )); then
        install_batch "brew casks" brew_cask_install brew_cask_installed "${casks[@]}" || had_failure=true
    fi

    [[ "$had_failure" == false ]]
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
                IFS='|' read -r comp_name comp_label comp_script <<< "$comp_entry"
                if (( ${#SELECTED_COMPONENTS[@]} == 0 )) ||
                   ! contains_item "$comp_name" "${SELECTED_COMPONENTS[@]}"; then
                    SELECTED_COMPONENTS+=("$comp_name")
                    SELECTED_LABELS+=("$comp_label")
                    SELECTED_SCRIPTS+=("$comp_script")
                fi
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
elif [[ "$seen_config" == true ]]; then
    DO_CONFIG=true
fi

if [[ "$PLAN_ONLY" == true ]]; then
    print_plan
    exit 0
fi

print_plan

had_failure=false

if [[ "$DO_PACKAGES" == true ]]; then
    if ! command -v brew >/dev/null 2>&1; then
        print_error "Homebrew is required: https://brew.sh"
        had_failure=true
    elif ! install_packages; then
        print_error "Package installation completed with failures."
        had_failure=true
    fi
fi

if (( ${#SELECTED_SCRIPTS[@]} > 0 )); then
    for idx in "${!SELECTED_SCRIPTS[@]}"; do
        comp_name="${SELECTED_COMPONENTS[$idx]}"
        comp_script="$REPO_ROOT/installers/${SELECTED_SCRIPTS[$idx]}"
        if ! bash "$comp_script"; then
            print_error "$comp_name failed"
            had_failure=true
        fi
    done
fi

if [[ "$DO_CONFIG" == true ]]; then
    if ! bash "$REPO_ROOT/installers/config/install.sh"; then
        print_error "Config sync failed"
        had_failure=true
    fi
fi

[[ "$had_failure" == false ]]
