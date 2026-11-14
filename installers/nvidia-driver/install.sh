#!/bin/bash

# Install the Ubuntu-recommended desktop NVIDIA driver. ubuntu-drivers uses
# the same selection logic as Additional Drivers and supports Secure Boot.
# https://documentation.ubuntu.com/server/how-to/graphics/install-nvidia-drivers/

set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

# ubuntu-drivers flags exactly one package recommended across every GPU, read
# from the cached apt index.
recommended_driver() {
    local devices
    devices="$(LC_ALL=C ubuntu-drivers devices)"
    awk '$1 == "driver" && $3 ~ /^nvidia-driver-/ && / recommended *$/ { print $3 }' \
        <<<"$devices"
}

if ! has_nvidia_gpu; then
    print_skipped "no NVIDIA GPU"
    exit 0
fi

# `ubuntu-drivers install` passes over drivers that are already installed and
# takes the best one left, so run against the recommended driver it swaps in
# another series (595 -> 580 -> 595 ...), churning a minute of packages and
# needing a reboot each time. Call it only while the recommended one is missing.
recommended="$(recommended_driver)"
if [[ -z "$recommended" ]] || ! apt_installed "$recommended"; then
    # The cached index may be empty on a fresh image, or stale enough to name an
    # older driver; decide from a fresh one before installing anything.
    apt_index_fresh || apt_refresh
    recommended="$(recommended_driver)"
fi

if [[ -z "$recommended" ]]; then
    print_skipped "ubuntu-drivers recommends no NVIDIA driver"
    exit 0
fi

if apt_installed "$recommended"; then
    print_success "Recommended driver already installed: $recommended"
else
    echo "Installing Ubuntu's recommended NVIDIA driver: $recommended"
    run_as_root ubuntu-drivers install
    if ! apt_installed "$recommended"; then
        print_error "ubuntu-drivers install did not install $recommended"
        exit 1
    fi
    print_installed "$recommended"
fi

if nvidia-smi >/dev/null 2>&1; then
    print_success "NVIDIA driver is active: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"
else
    print_warning "NVIDIA driver $recommended installed; reboot to load it."
fi
