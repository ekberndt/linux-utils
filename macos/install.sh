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
config (AeroSpace, agent skills, editor, tmux). Linux profiles do not run here.
EOF
}

list_targets() {
    echo "macOS"
    printf '  %-14s %s\n' "install" "Homebrew packages, AeroSpace, and tracked agent config"
    printf '  %-14s %s\n' "config" "AeroSpace and tracked agent/editor config"
}

install_formula() {
    local package="$1"

    if brew list --formula "$package" >/dev/null 2>&1; then
        print_success "Already installed: $package"
    elif brew install "$package"; then
        print_success "Successfully installed: $package"
    else
        print_error "Failed to install: $package"
        return 1
    fi
}

install_cask() {
    local package="$1"

    if brew list --cask "$package" >/dev/null 2>&1; then
        print_success "Already installed: $package"
    elif brew install --cask "$package"; then
        print_success "Successfully installed: $package"
    else
        print_error "Failed to install: $package"
        return 1
    fi
}

install_packages() {
    local line entry package had_failure=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        entry="$(printf '%s' "${line%%#*}" | xargs)"
        [[ -z "$entry" ]] && continue

        if [[ "$entry" == *" --cask" ]]; then
            package="${entry% --cask}"
            install_cask "$package" || had_failure=true
        else
            install_formula "$entry" || had_failure=true
        fi
    done < "$PACKAGES_FILE"

    [[ "$had_failure" == false ]]
}

print_plan() {
    print_header "macOS installer"
    [[ "$DO_PACKAGES" == true ]] && echo "  · Homebrew packages"
    echo "  · Agent config"
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
    list)
        list_targets
        exit 0
        ;;
    plan)
        PLAN_ONLY=true
        shift
        ;;
esac

DO_PACKAGES=true
seen_config=false
seen_workstation=false
for target in "$@"; do
    case "$target" in
        workstation) seen_workstation=true ;;
        config) seen_config=true ;;
        --optionals)
            print_warning "--optionals is Linux APT; ignoring on macOS"
            ;;
        -*)
            print_error "Unknown option: $target"
            exit 1
            ;;
        *)
            print_error "Linux-only target: $target"
            echo "On macOS, run: just install" >&2
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

# Agent config does not depend on Homebrew. just install still links skills
# when a formula is missing or brew is not installed yet.
if ! bash "$REPO_ROOT/installers/config/install.sh"; then
    print_error "Config sync failed"
    had_failure=true
fi

[[ "$had_failure" == false ]]
