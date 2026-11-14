#!/bin/bash
set -uo pipefail

# `ubuntu-drivers install` skips installed drivers and installs the best one
# left, so running it over an installed driver swaps in another series. The
# component installs only on a machine with no driver, deciding from a fresh
# apt index, and otherwise warns when Ubuntu recommends a different one.

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
        echo "ubuntu-drivers devices" >> "$DEVICES_CALLS"
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
export XDG_CACHE_HOME="$tmp/cache" DEVICES_CALLS="$tmp/devices-calls"

# Each run starts with an index last refreshed long ago and nothing cached.
run_component() {
    : > "$CALLS"
    : > "$INSTALLER_STATUS_FILE"
    : > "$DEVICES_CALLS"
    rm -rf "$APT_UPDATE_STAMP" "$XDG_CACHE_HOME"
    PATH="$tmp/bin:$PATH" bash "$ROOT/installers/nvidia-driver/install.sh" >/dev/null 2>&1
}
# A re-run that keeps the cache and the stamp.
rerun_component() {
    : > "$CALLS"
    : > "$INSTALLER_STATUS_FILE"
    : > "$DEVICES_CALLS"
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

rerun_component
assert_eq "a re-run with nothing changed asks ubuntu-drivers nothing" "$(< "$DEVICES_CALLS")" ""
assert_eq "a re-run answered from the cache still reports nothing" "$(< "$INSTALLER_STATUS_FILE")" ""
touch "$APT_UPDATE_STAMP"
rerun_component
assert_eq "a refreshed apt index asks ubuntu-drivers again" "$(< "$DEVICES_CALLS")" \
    "ubuntu-drivers devices"

printf 'ii \tnvidia-driver-580-open\t\n' > "$DPKG_STATE"
run_component
assert_eq "a driver other than the recommendation does not fail the step" "$?" "0"
assert_not_contains "an installed driver is never swapped for the recommendation" "$(< "$CALLS")" \
    "ubuntu-drivers install"
assert_contains "the recommendation is checked against a fresh index" "$(< "$CALLS")" \
    "sudo apt-get update"
assert_contains "a different recommendation is a warning" "$(< "$INSTALLER_STATUS_FILE")" \
    "$(printf 'warn\tUbuntu now recommends nvidia-driver-595-open; nvidia-driver-580-open is installed')"
rerun_component
assert_contains "the warning repeats until the driver is switched" "$(< "$INSTALLER_STATUS_FILE")" \
    "Ubuntu now recommends nvidia-driver-595-open"
assert_eq "the repeated warning comes from the cache" "$(< "$DEVICES_CALLS")" ""
printf 'ii \tnvidia-driver-595-open\t\n' > "$DPKG_STATE"
rerun_component
assert_eq "switching the driver asks ubuntu-drivers again" "$(< "$DEVICES_CALLS")" \
    "ubuntu-drivers devices"
assert_not_contains "switching to the recommendation clears the warning" \
    "$(< "$INSTALLER_STATUS_FILE")" "recommends"

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
assert_not_contains "a stale index naming an older driver raises no warning" \
    "$(< "$INSTALLER_STATUS_FILE")" "recommends"

echo fresh > "$APT_INDEX"
: > "$DPKG_STATE"
rm -rf "$XDG_CACHE_HOME"
touch "$APT_UPDATE_STAMP"
rerun_component
assert_not_contains "an index refreshed within the hour is not refreshed again" \
    "$(< "$CALLS")" "apt-get update"
assert_contains "it still installs the missing driver" "$(< "$CALLS")" "ubuntu-drivers install"

echo fresh > "$APT_INDEX"
: > "$DPKG_STATE"
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
