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

if [[ "$EUID" -eq 0 ]]; then
    print_error "Run this installer as your normal user; it uses sudo when needed."
    exit 1
fi

# shellcheck source=/etc/os-release
source /etc/os-release
if [[ "$ID" != "ubuntu" ]]; then
    print_error "Docker Engine installation is supported only on Ubuntu (found $PRETTY_NAME)."
    exit 1
fi

install_user="$(id -un)"
ubuntu_codename="${UBUNTU_CODENAME:-$VERSION_CODENAME}"

echo "Installing Docker Engine from Docker's official Ubuntu repository..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl

installed_conflicts=()
for package in "${CONFLICTING_PACKAGES[@]}"; do
    if dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null | grep -q '^ii'; then
        installed_conflicts+=("$package")
    fi
done

if ((${#installed_conflicts[@]})); then
    echo "Removing conflicting packages: ${installed_conflicts[*]}"
    sudo apt-get remove -y "${installed_conflicts[@]}"
fi

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$KEYRING_PATH"
sudo chmod a+r "$KEYRING_PATH"

sudo tee "$SOURCE_PATH" >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $ubuntu_codename
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: $KEYRING_PATH
EOF

sudo apt-get update
sudo apt-get install -y "${DOCKER_PACKAGES[@]}"

# The package normally creates this group; --force keeps reruns idempotent.
sudo groupadd --force docker
sudo usermod --append --groups docker "$install_user"

print_success "Installed $(docker --version)"
print_success "Added $install_user to the docker group."
print_warning "The docker group grants root-level privileges."
echo "Log out and back in (or run 'newgrp docker') before using Docker without sudo."
