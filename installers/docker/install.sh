#!/bin/bash

# Docker Engine installer for Ubuntu
# https://docs.docker.com/engine/install/ubuntu/

set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

DOCKER_PACKAGES=(
    docker-ce
    docker-ce-cli
    containerd.io
    docker-buildx-plugin
    docker-compose-plugin
)
CONFLICTING_PACKAGES=(
    docker.io
    docker-compose
    docker-compose-v2
    docker-doc
    podman-docker
    containerd
    runc
)
KEYRING_PATH="/etc/apt/keyrings/docker.asc"
SOURCE_PATH="/etc/apt/sources.list.d/docker.sources"
NVIDIA_KEYRING_PATH="/etc/apt/keyrings/nvidia-container-toolkit.asc"
NVIDIA_SOURCE_PATH="/etc/apt/sources.list.d/nvidia-container-toolkit.sources"

install_docker_engine() {
    # shellcheck source=/etc/os-release
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        print_error "Docker Engine installation is supported only on Ubuntu (found $PRETTY_NAME)."
        return 1
    fi

    local ubuntu_codename="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
    local package
    local -a installed_conflicts=()

    echo "Installing Docker Engine from Docker's official Ubuntu repository..."
    run_as_root apt-get update
    run_as_root apt-get install -y ca-certificates curl

    for package in "${CONFLICTING_PACKAGES[@]}"; do
        if dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null | grep -q '^ii'; then
            installed_conflicts+=("$package")
        fi
    done

    if ((${#installed_conflicts[@]})); then
        echo "Removing conflicting packages: ${installed_conflicts[*]}"
        run_as_root apt-get remove -y "${installed_conflicts[@]}"
    fi

    run_as_root install -m 0755 -d /etc/apt/keyrings
    run_as_root curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$KEYRING_PATH"
    run_as_root chmod a+r "$KEYRING_PATH"

    run_as_root tee "$SOURCE_PATH" >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $ubuntu_codename
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: $KEYRING_PATH
EOF

    run_as_root apt-get update
    run_as_root apt-get install -y "${DOCKER_PACKAGES[@]}"
}

nvidia_runtime_configured() {
    docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'
}

install_nvidia_runtime() {
    echo "NVIDIA GPU detected; installing the NVIDIA Container Toolkit..."
    run_as_root install -m 0755 -d /etc/apt/keyrings
    run_as_root curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey -o "$NVIDIA_KEYRING_PATH"
    run_as_root chmod a+r "$NVIDIA_KEYRING_PATH"

    # Flat repository: Suites is "/" and there is no Components entry.
    run_as_root tee "$NVIDIA_SOURCE_PATH" >/dev/null <<EOF
Types: deb
URIs: https://nvidia.github.io/libnvidia-container/stable/deb/$(dpkg --print-architecture)
Suites: /
Signed-By: $NVIDIA_KEYRING_PATH
EOF

    run_as_root apt-get update
    run_as_root apt-get install -y nvidia-container-toolkit
    run_as_root nvidia-ctk runtime configure --runtime=docker
    run_as_root systemctl restart docker
    print_success "NVIDIA runtime configured (verify: docker run --rm --gpus all ubuntu nvidia-smi)."
}

if is_installed docker; then
    print_success "Already installed: $(docker --version)"
else
    install_docker_engine
    print_success "Installed $(docker --version)"
fi

# Configure the runtime from hardware detection so a newly installed driver
# does not need to be loaded before the post-install reboot.
if has_nvidia_gpu; then
    if nvidia_runtime_configured; then
        print_success "NVIDIA container runtime already configured."
    else
        install_nvidia_runtime
    fi
else
    print_warning "No NVIDIA GPU detected; leaving the container runtime CPU-only."
fi

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    install_user="$(id -un)"
    # Checking first costs nothing and keeps a re-run from spending two sudo
    # calls to re-add a user who has been in the group since the first install.
    if id -nG "$install_user" | grep -qw docker; then
        print_success "$install_user is already in the docker group."
    else
        # The package normally creates this group; --force keeps reruns idempotent.
        run_as_root groupadd --force docker
        run_as_root usermod --append --groups docker "$install_user"
        print_success "Added $install_user to the docker group."
        print_warning "The docker group grants root-level privileges."
        echo "Log out and back in (or run 'newgrp docker') before using Docker without sudo."
    fi
fi
