#!/bin/bash

# Shared utilities for all installer scripts

# Color codes
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

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }

# Check if a command is available
# Usage: is_installed "uv" && exit 0
is_installed() {
    command -v "$1" &>/dev/null
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
