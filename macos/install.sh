#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../installers/lib/common.sh
source "$REPO_ROOT/installers/lib/common.sh"

PACKAGES_FILE="$SCRIPT_DIR/brew.txt"

usage() {
    cat <<EOF
Usage:
  $0 [workstation]
  $0 config
  $0 plan [workstation|config]
  $0 list

On macOS this installs Homebrew packages from brew.txt and syncs tracked
config (AeroSpace, Warp OSC 52, agent skills, editor, tmux, screenshots). Linux profiles
do not run here.
EOF
}

list_targets() {
    echo "macOS"
    printf '  %-14s %s\n' "install" "Homebrew packages, AeroSpace, Warp OSC 52, screenshots, and tracked agent config"
    printf '  %-14s %s\n' "config" "AeroSpace, Warp OSC 52, screenshots, and tracked agent/editor config"
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
    print_header "macOS installer"
    [[ "$DO_PACKAGES" == true ]] && echo "  · Homebrew packages"
    echo "  · Agent config (includes Warp OSC 52)"
    echo "  · Screenshots saved to ~/Pictures/screenshots"
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

DO_PACKAGES=true
seen_config=false
seen_workstation=false
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
            print_error "Target '$arg' is not supported on macOS."
            echo "Run '$0 list' for macOS targets."
            exit 1
            ;;
    esac
done

if [[ "$seen_config" == true && "$seen_workstation" == false ]]; then
    DO_PACKAGES=false
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

# Agent and macOS config does not depend on Homebrew.
if ! bash "$REPO_ROOT/installers/config/install.sh"; then
    print_error "Config sync failed"
    had_failure=true
fi

[[ "$had_failure" == false ]]
