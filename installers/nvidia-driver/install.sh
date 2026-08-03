#!/bin/bash

# Install the Ubuntu-recommended desktop NVIDIA driver. ubuntu-drivers uses
# the same selection logic as Additional Drivers and supports Secure Boot.
# https://documentation.ubuntu.com/server/how-to/graphics/install-nvidia-drivers/

set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

if ! has_nvidia_gpu; then
    print_success "No NVIDIA GPU detected; skipping driver installation."
    exit 0
fi

echo "Installing Ubuntu's recommended NVIDIA driver..."
run_as_root ubuntu-drivers install

if nvidia-smi >/dev/null 2>&1; then
    print_success "NVIDIA driver is active: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"
else
    print_warning "NVIDIA driver installed; reboot to load it."
fi
