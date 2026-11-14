#!/bin/bash

# Install the Ubuntu-recommended desktop NVIDIA driver. ubuntu-drivers uses
# the same selection logic as Additional Drivers and supports Secure Boot.
# https://documentation.ubuntu.com/server/how-to/graphics/install-nvidia-drivers/

set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

# ubuntu-drivers flags exactly one package recommended across every GPU, read
# from the cached apt index. It spends ~2.5 s of local work answering, so its
# answer is kept until something it reads changes: the hardware (a reboot), the
# apt index (the update stamp), or the installed drivers.
RECOMMENDATION_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/linux-utils/nvidia-recommended-driver"

# Installed nvidia-driver-<series> packages; none on a fresh machine, where
# dpkg-query exits 1.
installed_drivers() {
    dpkg-query -W -f='${db:Status-Abbrev}\t${Package}\n' 'nvidia-driver-*' 2>/dev/null |
        awk '$1 ~ /^.i/ && $2 ~ /^nvidia-driver-[0-9]/ { print $2 }' || true
}

recommended_driver() {
    local key devices recommended
    key="$(< /proc/sys/kernel/random/boot_id) $(stat -c %Y "$APT_UPDATE_STAMP" 2>/dev/null || echo 0)"
    key="$key $(installed_drivers | xargs)"
    if [[ "$(head -n1 "$RECOMMENDATION_CACHE" 2>/dev/null)" == "$key" ]]; then
        sed -n 2p "$RECOMMENDATION_CACHE"
        return
    fi
    devices="$(LC_ALL=C ubuntu-drivers devices)"
    recommended="$(awk '$1 == "driver" && $3 ~ /^nvidia-driver-/ && / recommended *$/ { print $3 }' \
        <<<"$devices")"
    mkdir -p "$(dirname "$RECOMMENDATION_CACHE")"
    printf '%s\n%s\n' "$key" "$recommended" > "$RECOMMENDATION_CACHE"
    printf '%s\n' "$recommended"
}

if ! has_nvidia_gpu; then
    print_skipped "no NVIDIA GPU"
    exit 0
fi

recommended="$(recommended_driver)"
if [[ -z "$recommended" ]] || ! apt_installed "$recommended"; then
    # The cached index may be empty on a fresh image, or stale enough to name an
    # older driver; decide from a fresh one before acting on it.
    apt_index_fresh || apt_refresh
    recommended="$(recommended_driver)"
fi

if [[ -z "$recommended" ]]; then
    print_skipped "ubuntu-drivers recommends no NVIDIA driver"
    exit 0
fi

# A machine with a driver keeps it. `ubuntu-drivers install` passes over
# drivers that are already installed and takes the best one left, so it swaps
# series (595 -> 580 -> 595 ...) and needs a reboot each time; moving to a new
# recommendation is the user's call.
installed="$(installed_drivers | xargs)"
if [[ -z "$installed" ]]; then
    echo "Installing Ubuntu's recommended NVIDIA driver: $recommended"
    run_as_root ubuntu-drivers install
    if ! apt_installed "$recommended"; then
        print_error "ubuntu-drivers install did not install $recommended"
        exit 1
    fi
    print_installed "$recommended"
    installed="$recommended"
elif ! apt_installed "$recommended"; then
    print_warning "Ubuntu now recommends $recommended; $installed is installed. Run 'sudo ubuntu-drivers install' and reboot to switch."
else
    print_success "Recommended driver already installed: $recommended"
fi

if nvidia-smi >/dev/null 2>&1; then
    print_success "NVIDIA driver is active: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"
else
    print_warning "NVIDIA driver $installed installed; reboot to load it."
fi
