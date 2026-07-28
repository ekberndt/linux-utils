#!/bin/bash

# Robotics installer
# Installs robotics tooling starting with the Intel RealSense SDK 2.0 from
# RealSense's official Debian apt repository (DKMS + utils + dev headers).
# https://github.com/realsenseai/librealsense/blob/master/doc/distribution_linux.md

set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

KEYRING_PATH="/etc/apt/keyrings/librealsenseai.gpg"
SOURCE_PATH="/etc/apt/sources.list.d/librealsense.list"
KEY_URL="https://librealsense.realsenseai.com/Debian/librealsenseai.asc"
REPO_URL="https://librealsense.realsenseai.com/Debian/apt-repo"

# Runtime + tools + headers for building against librealsense.
# librealsense2-dbg is omitted (large debug symbols; install manually if needed).
REALSENSE_PACKAGES=(
    librealsense2-dkms
    librealsense2-utils
    librealsense2-dev
)

if [[ "$EUID" -eq 0 ]]; then
    print_error "Run this installer as your normal user; it uses sudo when needed."
    exit 1
fi

# shellcheck source=/etc/os-release
source /etc/os-release
if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
    print_error "RealSense packages are supported only on Ubuntu/Debian (found ${PRETTY_NAME:-$ID})."
    exit 1
fi

if ! is_installed "lsb_release"; then
    print_error "lsb_release is required (package: lsb-release)."
    exit 1
fi

distro_codename="$(lsb_release -cs)"
case "$distro_codename" in
    focal|jammy|noble|bookworm)
        ;;
    *)
        print_warning "Codename '$distro_codename' is not a documented RealSense LTS target (Ubuntu 20/22/24)."
        print_warning "Continuing; the apt repo may not have packages for this release."
        ;;
esac

package_installed() {
    dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | grep -q '^ii'
}

all_packages_installed() {
    local pkg
    for pkg in "${REALSENSE_PACKAGES[@]}"; do
        package_installed "$pkg" || return 1
    done
    return 0
}

if all_packages_installed && is_installed "realsense-viewer"; then
    print_success "Already installed: Intel RealSense SDK (realsense-viewer)"
    exit 0
fi

echo "Installing Intel RealSense SDK from RealSense's official Debian repository..."

sudo apt-get install -y ca-certificates curl gnupg apt-transport-https lsb-release

sudo mkdir -p /etc/apt/keyrings
# Keyring includes the new RealSense public key and the legacy Intel key.
curl -sSf "$KEY_URL" | gpg --dearmor | sudo tee "$KEYRING_PATH" >/dev/null
sudo chmod a+r "$KEYRING_PATH"

echo "deb [signed-by=${KEYRING_PATH}] ${REPO_URL} ${distro_codename} main" \
    | sudo tee "$SOURCE_PATH" >/dev/null

sudo apt-get update

if ! sudo apt-get install -y "${REALSENSE_PACKAGES[@]}"; then
    print_error "Failed to install RealSense packages: ${REALSENSE_PACKAGES[*]}"
    exit 1
fi

if ! is_installed "realsense-viewer"; then
    print_error "realsense-viewer not on PATH after install"
    exit 1
fi

print_success "Installed Intel RealSense SDK (librealsense2-dkms, utils, dev)"
echo "Reconnect the RealSense camera, then run: realsense-viewer"
echo "Kernel module check: modinfo uvcvideo | grep version:  # should mention realsense"
