#!/bin/bash
set -uo pipefail

# `ubuntu-drivers install` skips installed drivers and installs the best one
# left, so running it over the recommended driver swapped in another series on
# every run. The component calls it only while the recommended driver is
# missing, and decides that from a fresh apt index before installing.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/pci/0000:01:00.0"
echo 0x10de > "$tmp/pci/0000:01:00.0/vendor"
echo 0x030000 > "$tmp/pci/0000:01:00.0/class"

# ubuntu-drivers only knows the drivers in the apt index: none when it is
# empty, 580 when it is stale, 595 once refreshed.
cat > "$tmp/bin/ubuntu-drivers" <<'EOF'
#!/bin/bash
index="$(< "$APT_INDEX")"
case "$1" in
    devices)
        echo "== /sys/devices/pci0000:00/0000:01:00.0 =="
        echo "vendor   : NVIDIA Corporation"
        case "$index" in
            stale) echo "driver   : nvidia-driver-580-open - distro non-free recommended" ;;
            fresh)
                echo "driver   : nvidia-driver-580-open - distro non-free"
                echo "driver   : nvidia-driver-595-open - distro non-free recommended"
                ;;
        esac
        echo "driver   : xserver-xorg-video-nouveau - distro free builtin"
        ;;
    install)
        echo "ubuntu-drivers install" >> "$CALLS"
        # The real bug: the best driver not yet installed wins.
        if grep -q nvidia-driver-595-open "$DPKG_STATE"; then
            printf 'ii \tnvidia-driver-580-open\t\n' > "$DPKG_STATE"
        elif [[ -z "${INSTALL_BROKEN:-}" ]]; then
            printf 'ii \tnvidia-driver-595-open\t\n' > "$DPKG_STATE"
        fi
        ;;
esac
EOF
cat > "$tmp/bin/apt-get" <<'EOF'
#!/bin/bash
[[ "$1" == update ]] && echo fresh > "$APT_INDEX"
EOF
cat > "$tmp/bin/dpkg-query" <<'EOF'
#!/bin/bash
cat "$DPKG_STATE"
EOF
cat > "$tmp/bin/apt-cache" <<'EOF'
#!/bin/bash
EOF
cat > "$tmp/bin/sudo" <<'EOF'
#!/bin/bash
echo "sudo $*" >> "$CALLS"
exec "$@"
EOF
cat > "$tmp/bin/nvidia-smi" <<'EOF'
#!/bin/bash
[[ -z "${DRIVER_NOT_LOADED:-}" ]] && echo 595.99.02
EOF
chmod +x "$tmp/bin/"*

export DPKG_STATE="$tmp/dpkg" CALLS="$tmp/calls" PCI_DEVICES_DIR="$tmp/pci"
export APT_INDEX="$tmp/index" INSTALLER_STATUS_FILE="$tmp/status"
export APT_UPDATE_STAMP="$tmp/update-success-stamp"

# Each run starts with an index last refreshed long ago.
run_component() {
    : > "$CALLS"
    : > "$INSTALLER_STATUS_FILE"
    rm -f "$APT_UPDATE_STAMP"
    PATH="$tmp/bin:$PATH" bash "$ROOT/installers/nvidia-driver/install.sh" >/dev/null 2>&1
}

echo fresh > "$APT_INDEX"
printf 'ii \tnvidia-driver-595-open\t\n' > "$DPKG_STATE"
run_component
assert_eq "the recommended driver installed is current" "$?" "0"
assert_eq "a current driver needs no apt, sudo, or ubuntu-drivers install" "$(< "$CALLS")" ""
assert_eq "a current driver reports no change" "$(< "$INSTALLER_STATUS_FILE")" ""
run_component
assert_eq "a re-run leaves the driver alone" "$(< "$DPKG_STATE")" \
    "$(printf 'ii \tnvidia-driver-595-open\t')"

printf 'ii \tnvidia-driver-580-open\t\n' > "$DPKG_STATE"
run_component
assert_contains "a missing recommended driver is installed" "$(< "$CALLS")" \
    "ubuntu-drivers install"
assert_contains "the index is refreshed before installing a driver" "$(< "$CALLS")" \
    "sudo apt-get update"
assert_contains "the new driver is reported" "$(< "$INSTALLER_STATUS_FILE")" \
    "$(printf 'installed\tnvidia-driver-595-open')"

: > "$APT_INDEX"
: > "$DPKG_STATE"
run_component
assert_eq "an empty index still installs the driver" "$?" "0"
assert_contains "an empty index installs what a fresh one recommends" \
    "$(< "$INSTALLER_STATUS_FILE")" "$(printf 'installed\tnvidia-driver-595-open')"

echo stale > "$APT_INDEX"
: > "$DPKG_STATE"
run_component
assert_eq "a stale index does not fail the install it triggers" "$?" "0"
assert_contains "a stale index installs what a fresh one recommends" \
    "$(< "$INSTALLER_STATUS_FILE")" "$(printf 'installed\tnvidia-driver-595-open')"

echo stale > "$APT_INDEX"
printf 'ii \tnvidia-driver-595-open\t\n' > "$DPKG_STATE"
run_component
assert_eq "a stale index naming an older driver leaves the current one" \
    "$(grep -c 'ubuntu-drivers install' "$CALLS")" "0"

echo fresh > "$APT_INDEX"
printf 'ii \tnvidia-driver-580-open\t\n' > "$DPKG_STATE"
: > "$CALLS"
touch "$APT_UPDATE_STAMP"
PATH="$tmp/bin:$PATH" bash "$ROOT/installers/nvidia-driver/install.sh" >/dev/null 2>&1
assert_not_contains "an index refreshed within the hour is not refreshed again" \
    "$(< "$CALLS")" "apt-get update"
assert_contains "it still installs the missing driver" "$(< "$CALLS")" "ubuntu-drivers install"

echo fresh > "$APT_INDEX"
printf 'ii \tnvidia-driver-580-open\t\n' > "$DPKG_STATE"
INSTALL_BROKEN=1 run_component
assert_eq "an install that leaves the recommended driver missing fails" "$?" "1"
assert_contains "that failure is reported" "$(< "$INSTALLER_STATUS_FILE")" "error"

printf 'ii \tnvidia-driver-595-open\t\n' > "$DPKG_STATE"
DRIVER_NOT_LOADED=1 run_component
assert_contains "an installed but unloaded driver asks for a reboot" \
    "$(< "$INSTALLER_STATUS_FILE")" "reboot to load it"

PCI_DEVICES_DIR="$tmp/no-pci" run_component
assert_contains "no NVIDIA GPU is a skip" "$(< "$INSTALLER_STATUS_FILE")" \
    "$(printf 'skipped\tno NVIDIA GPU')"

test_result
