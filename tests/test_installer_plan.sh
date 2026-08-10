#!/bin/bash
set -uo pipefail

# Profile and component resolution, driven through the real installer so the
# registry, profile files, and argument parsing are all exercised together.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

installer() { bash "$ROOT/installers/installer.sh" "$@"; }

targets="$(installer list)"
workstation="$(installer plan workstation)"
workstation_apps="$(installer plan workstation desktop-apps)"
datacenter="$(installer plan datacenter)"
datacenter_extended="$(installer plan datacenter ollama)"

assert_contains "list names the workstation profile" "$targets" "workstation"
assert_contains "list names the datacenter profile" "$targets" "datacenter"

assert_contains "workstation installs the recommended NVIDIA driver" \
    "$workstation" "Recommended NVIDIA driver"
assert_contains "workstation installs Homebrew" "$workstation" "Homebrew packages"
assert_contains "workstation installs tmux" "$workstation" "tmux session persistence"
assert_not_contains "workstation leaves personal desktop apps out" \
    "$workstation" "Personal desktop apps"
assert_contains "desktop apps join the workstation on request" \
    "$workstation_apps" "Personal desktop apps"

assert_contains "datacenter installs Docker" "$datacenter" "Docker Engine"
assert_contains "datacenter installs W&B" "$datacenter" "Weights & Biases"
assert_contains "datacenter installs tracked config" "$datacenter" "Tracked config"
assert_not_contains "datacenter leaves Homebrew out" "$datacenter" "Homebrew packages"
assert_not_contains "datacenter leaves the image NVIDIA driver alone" \
    "$datacenter" "Recommended NVIDIA driver"
assert_contains "a component composes with a profile" "$datacenter_extended" "Ollama"

# The registry is execution order, and Docker's NVIDIA runtime setup needs the
# driver's packages to already be on the box.
assert_contains "workstation installs the NVIDIA driver before Docker" \
    "$(< "$ROOT/installers/profiles/workstation.conf")" \
    $'apt\n    nvidia-driver\n    docker'

plan_is_inert="$(installer plan datacenter >/dev/null && echo inert)"
assert_eq "plan changes nothing" "$plan_is_inert" "inert"

assert_eq "an unknown target fails" \
    "$(installer definitely-not-a-component >/dev/null 2>&1; echo $?)" "1"

# The opt-in split is the point of desktop-apps: nothing may be in both sets.
manifest_entries() {
    sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' -e 's/[[:space:]]*#.*//' "$@" |
        awk '{ print $1 }' | sort -u
}
overlap="$(comm -12 \
    <(manifest_entries "$ROOT/installers/apt/apt_packages.txt" \
        "$ROOT/installers/flatpak/flatpaks.txt" "$ROOT/installers/snap/snaps.txt") \
    <(manifest_entries "$ROOT/installers/desktop-apps/apt_packages.txt" \
        "$ROOT/installers/desktop-apps/flatpaks.txt" \
        "$ROOT/installers/desktop-apps/snaps.txt"))"
assert_eq "default and opt-in manifests are disjoint" "$overlap" ""

test_result
