#!/bin/bash

# The component registry, sourced by installer.sh (Linux) and macos/install.sh.
# Kept bash 3.2 compatible for macOS.
#
# Registry order is execution order. Profiles only choose from these names, and
# each component is installers/<name>/install.sh.
#
# name|label|uses-sudo|macos-command
#   uses-sudo      Read only on Linux: one "yes" among the selected components
#                  opens a sudo session for the run.
#   macos-command  What a plain macOS run looks for to decide the component is
#                  installed, and so upgrades it; naming the component installs
#                  it. "-" keeps it Linux-only. macOS runs config as its own step.
COMPONENTS=(
    "apt|APT packages|yes|-"
    "nvidia-driver|Recommended NVIDIA driver|yes|-"
    "docker|Docker Engine|yes|-"
    "flatpak|Flatpak apps|yes|-"
    "snap|Snap packages|yes|-"
    "desktop-apps|Personal desktop apps|yes|-"
    "homebrew|Homebrew packages|yes|-"
    "uv|uv Python toolchain|no|uv"
    "wandb|Weights & Biases|no|wandb"
    "netron|Netron model viewer|no|-"
    "npm|npm global packages|yes|npm"
    "pnpm|pnpm global packages|no|pnpm"
    "pip|pip user packages|no|python3"
    "pipx|pipx apps|no|pipx"
    "tailscale|Tailscale|yes|-"
    "bazelisk|Bazelisk|yes|-"
    "buildtools|Bazel build tools|yes|-"
    "gh|GitHub CLI|yes|-"
    "opencode|OpenCode|no|opencode"
    "claude|Claude Code|no|claude"
    "codex|Codex CLI|yes|codex"
    "grok|Grok Build|no|grok"
    "agy|Antigravity CLI|no|agy"
    "herdr-core|herdr-core (hc)|no|herdr-core"
    "herdr|Herdr app|no|herdr-app"
    "ollama|Ollama|yes|-"
    "cargo|Rust and Cargo packages|yes|rustup"
    "zoxide|zoxide|no|zoxide"
    "openrgb|OpenRGB|yes|-"
    "lazyvim|Neovim and LazyVim|yes|-"
    "tmux|tmux session persistence|yes|-"
    "robotics|Intel RealSense|yes|-"
    "config|Tracked config|yes|-"
)

# find_component <name>: print the component's registry entry.
find_component() {
    local entry name
    for entry in "${COMPONENTS[@]}"; do
        IFS='|' read -r name _ <<< "$entry"
        if [[ "$name" == "$1" ]]; then
            printf '%s\n' "$entry"
            return 0
        fi
    done
    return 1
}
