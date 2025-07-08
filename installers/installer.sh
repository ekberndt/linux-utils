#!/bin/bash

# Master installer script
# Installs packages from all supported package managers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=====================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Parse command line arguments
INSTALL_APT=false
INSTALL_FLATPAK=false
INSTALL_SNAP=false
INSTALL_ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--apt)
            INSTALL_APT=true
            shift
            ;;
        -f|--flatpak)
            INSTALL_FLATPAK=true
            shift
            ;;
        -s|--snap)
            INSTALL_SNAP=true
            shift
            ;;
        --all)
            INSTALL_ALL=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  -a, --apt         Install APT packages"
            echo "  -f, --flatpak     Install Flatpak packages"
            echo "  -s, --snap        Install Snap packages"
            echo "      --all         Install all package types"
            echo "  -h, --help        Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --all                    Install everything"
            echo "  $0 -a -f                    Install APT and Flatpak only"
            echo "  $0 --apt --snap             Install APT and Snap only"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# If no options specified, show help
if [[ "$INSTALL_ALL" == false && "$INSTALL_APT" == false && "$INSTALL_FLATPAK" == false && "$INSTALL_SNAP" == false ]]; then
    echo "No installation options specified. Use --help for usage information."
    exit 1
fi

# Set all flags if --all is specified
if [[ "$INSTALL_ALL" == true ]]; then
    INSTALL_APT=true
    INSTALL_FLATPAK=true
    INSTALL_SNAP=true
fi

print_header "Linux Package Installation Script"

# Update system first
print_header "Updating System"
if sudo apt update && sudo apt upgrade -y; then
    print_success "System updated successfully"
else
    print_error "Failed to update system"
    exit 1
fi

# Install APT packages
if [ "$INSTALL_APT" = true ]; then
    print_header "Installing APT Packages"
    if [ -f "$SCRIPT_DIR/apt/install.sh" ]; then
        bash "$SCRIPT_DIR/apt/install.sh"
    else
        print_warning "APT installer not found at $SCRIPT_DIR/apt/install.sh"
    fi
fi

# Install Flatpak packages
if [ "$INSTALL_FLATPAK" = true ]; then
    print_header "Installing Flatpak Packages"
    if [ -f "$SCRIPT_DIR/flatpak/install.sh" ]; then
        bash "$SCRIPT_DIR/flatpak/install.sh"
    else
        print_warning "Flatpak installer not found at $SCRIPT_DIR/flatpak/install.sh"
    fi
fi

# Install Snap packages
if [ "$INSTALL_SNAP" = true ]; then
    print_header "Installing Snap Packages"
    if [ -f "$SCRIPT_DIR/snap/install.sh" ]; then
        bash "$SCRIPT_DIR/snap/install.sh"
    else
        print_warning "Snap installer not found at $SCRIPT_DIR/snap/install.sh"
    fi
fi

print_header "Installation Complete"
print_success "All selected package installations completed!"
