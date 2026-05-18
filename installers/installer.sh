#!/bin/bash

# Master installer script
# Installs packages from all supported package managers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# --- Installer Registry ---
# Format: "directory_name|short_flag|long_flag|display_name"
# To add a new installer: create <dir>/install.sh and add one line here.
INSTALLERS=(
    "apt|a|apt|APT Packages"
    "flatpak|f|flatpak|Flatpak Packages"
    "snap|s|snap|Snap Packages"
    "uv|u|uv|uv (Python package manager)"
    "tailscale|t|tailscale|Tailscale (VPN/mesh networking)"
    "bazelisk|b|bazelisk|bazelisk (Bazel version manager)"
    "buildtools|B|buildtools|buildtools (buildifier, buildozer, unused-deps)"
    "gh|g|gh|GitHub CLI (from official repo)"
)

# --- Help ---
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    for entry in "${INSTALLERS[@]}"; do
        IFS='|' read -r _ short long display <<< "$entry"
        printf "  -%s, --%-12s Install %s\n" "$short" "$long" "$display"
    done
    echo "      --all         Install all package types"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --all                    Install everything"
    echo "  $0 -a -f                    Install APT and Flatpak only"
    echo "  $0 --apt --snap             Install APT and Snap only"
}

# --- Parse CLI flags dynamically ---
declare -A INSTALL_FLAGS
INSTALL_ALL=false

for entry in "${INSTALLERS[@]}"; do
    IFS='|' read -r name _ _ _ <<< "$entry"
    INSTALL_FLAGS["$name"]=false
done

while [[ $# -gt 0 ]]; do
    matched=false
    for entry in "${INSTALLERS[@]}"; do
        IFS='|' read -r name short long _ <<< "$entry"
        if [[ "$1" == "-$short" || "$1" == "--$long" ]]; then
            INSTALL_FLAGS["$name"]=true
            matched=true
            break
        fi
    done
    if [[ "$matched" == false ]]; then
        case "$1" in
            --all) INSTALL_ALL=true ;;
            -h|--help) show_help; exit 0 ;;
            *) echo "Unknown option: $1"; echo "Use --help for usage information"; exit 1 ;;
        esac
    fi
    shift
done

# Check if anything was selected
any_selected=false
if [[ "$INSTALL_ALL" == true ]]; then
    any_selected=true
else
    for name in "${!INSTALL_FLAGS[@]}"; do
        if [[ "${INSTALL_FLAGS[$name]}" == true ]]; then
            any_selected=true
            break
        fi
    done
fi

if [[ "$any_selected" == false ]]; then
    echo "No installation options specified. Use --help for usage information."
    exit 1
fi

# --- Run selected installers ---
print_header "Linux Package Installation Script"

print_header "Updating System"
if sudo apt update && sudo apt upgrade -y; then
    print_success "System updated successfully"
else
    print_error "Failed to update system"
    exit 1
fi

for entry in "${INSTALLERS[@]}"; do
    IFS='|' read -r name _ _ display <<< "$entry"
    if [[ "${INSTALL_FLAGS[$name]}" == true || "$INSTALL_ALL" == true ]]; then
        print_header "Installing $display"
        script="$SCRIPT_DIR/$name/install.sh"
        if [ -f "$script" ]; then
            bash "$script"
        else
            print_warning "$display installer not found at $script"
        fi
    fi
done

print_header "Installation Complete"
print_success "All selected package installations completed!"
