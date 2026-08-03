#!/bin/bash

# APT package installer
# Reads apt_packages.txt and installs specified apt packages

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
# shellcheck source=../lib/package_list.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/package_list.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/apt_packages.txt"

require_file "$PACKAGES_FILE"

apt_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

install_apt_packages() {
    local -a pkgs=("$@")
    # One transaction: avoids N× "Reading package lists" / dep solves.
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -y "${pkgs[@]}"
}

# Prefer peak performance over Ubuntu's balanced/ondemand defaults.
# Two layers: GNOME power-profiles-daemon (when "performance" exists) and the
# cpufreq governor (always, when the kernel exposes it). Always-plugged
# desktops still frequency-scale under balanced — this is not a no-op there.
configure_performance_power() {
    local gov_file="/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors"
    local conf="/etc/default/cpufrequtils"
    local profile_list current cpu epp_avail

    if command -v powerprofilesctl >/dev/null 2>&1; then
        profile_list="$(powerprofilesctl list 2>/dev/null || true)"
        if grep -qE '^[[:space:]]*\*?[[:space:]]*performance:' <<<"$profile_list"; then
            current="$(powerprofilesctl get 2>/dev/null || true)"
            if [[ "$current" == "performance" ]]; then
                print_success "Power profile already performance"
            elif sudo powerprofilesctl set performance 2>/dev/null || \
                sudo busctl set-property net.hadess.PowerProfiles \
                    /net/hadess/PowerProfiles net.hadess.PowerProfiles \
                    ActiveProfile s performance 2>/dev/null; then
                print_success "Power profile: ${current:-unknown} -> performance"
            else
                print_warning "Could not set power-profiles-daemon to performance"
            fi
        else
            print_warning "power-profiles-daemon has no performance profile (driver limited); using CPU governor only"
        fi
    fi

    if [[ ! -f "$gov_file" ]]; then
        print_warning "No cpufreq sysfs; skipping CPU governor"
        return 0
    fi
    if ! grep -qw performance "$gov_file"; then
        print_warning "performance governor unavailable ($(cat "$gov_file")); leaving governor alone"
        return 0
    fi

    if [[ -f "$conf" ]] && grep -q 'ENABLE="true"' "$conf" && grep -q 'GOVERNOR="performance"' "$conf"; then
        print_success "Already configured: $conf (performance)"
    else
        # Overwrite intentional: one performance policy for every machine this repo sets up.
        if sudo tee "$conf" >/dev/null <<'EOF'
# Managed by linux-utils apt installer: prefer performance over balanced.
ENABLE="true"
GOVERNOR="performance"
MAX_SPEED="0"
MIN_SPEED="0"
EOF
        then
            print_success "Wrote $conf (GOVERNOR=performance)"
        else
            print_error "Failed to write $conf"
            return 1
        fi
    fi

    # Apply now; cpufrequtils only runs its defaults at service start.
    for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
        [[ -f "$cpu/cpufreq/scaling_governor" ]] || continue
        echo performance | sudo tee "$cpu/cpufreq/scaling_governor" >/dev/null
    done

    if systemctl cat cpufrequtils.service >/dev/null 2>&1; then
        sudo systemctl enable cpufrequtils.service >/dev/null 2>&1 || true
        sudo systemctl restart cpufrequtils.service >/dev/null 2>&1 || \
            sudo service cpufrequtils restart >/dev/null 2>&1 || true
    fi

    current="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || true)"
    if [[ "$current" == "performance" ]]; then
        print_success "CPU governor: performance (all CPUs)"
    else
        print_warning "CPU governor still ${current:-unknown} after apply (check BIOS/driver limits)"
    fi

    # intel_pstate / amd_pstate energy-performance preference when exposed
    if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference ]]; then
        epp_avail="$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_available_preferences 2>/dev/null || true)"
        if grep -qw performance <<<"$epp_avail"; then
            for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
                [[ -f "$cpu/cpufreq/energy_performance_preference" ]] || continue
                echo performance | sudo tee "$cpu/cpufreq/energy_performance_preference" >/dev/null
            done
            print_success "Energy performance preference: performance"
        fi
    fi
}

# Auto-accept optionals when INSTALLER_INSTALL_OPTIONALS is 1/true/yes.
install_optionals_env() {
    case "${INSTALLER_INSTALL_OPTIONALS,,}" in
        1|true|yes) return 0 ;;
        *) return 1 ;;
    esac
}

echo "Installing apt packages..."

# Load once so interactive optional prompts never steal package lines from stdin.
mapfile -t package_lines < "$PACKAGES_FILE"

# Collect PPAs first
ppas=()
for line in "${package_lines[@]}"; do
    parse_package_line "$line" || continue
    if [[ -n "$ppa" ]]; then
        ppas+=("ppa:$ppa")
    fi
done

# Add PPAs if any exist
if [[ ${#ppas[@]} -gt 0 ]]; then
    echo "Adding ${#ppas[@]} PPAs..."
    for ppa in "${ppas[@]}"; do
        echo "Adding PPA: $ppa"
        sudo add-apt-repository -y "$ppa"
    done
    echo "Updating package lists after adding PPAs..."
    sudo apt-get update
fi

# Prompt only when stdout is a real terminal. Under the dashboard (and any
# piped run), stdout is a pipe: the prompt is invisible and read </dev/tty
# hangs forever after the last non-optional package (e.g. after "tree").
can_prompt_optional() {
    [[ -t 1 && -r /dev/tty && -w /dev/tty ]]
}

missing=()
for line in "${package_lines[@]}"; do
    parse_package_line "$line" || continue

    if $optional; then
        if install_optionals_env; then
            : # auto-accept
        elif can_prompt_optional; then
            # Prompt on the controlling terminal so package-list stdin cannot be stolen.
            read -r -p "Install optional package '$package'? [y/N] " response </dev/tty || response=n
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                echo "Skipping: $package"
                continue
            fi
        else
            echo "Skipping optional package (non-interactive): $package"
            continue
        fi
    fi

    if apt_installed "$package"; then
        print_success "Already installed: $package"
    else
        missing+=("$package")
    fi
done

had_failure=false
if ((${#missing[@]} == 0)); then
    echo "All listed APT packages already installed."
else
    echo "Installing ${#missing[@]} packages: ${missing[*]}"
    if install_apt_packages "${missing[@]}"; then
        for package in "${missing[@]}"; do
            if apt_installed "$package"; then
                print_success "Successfully installed: $package"
            else
                # Virtual package names (e.g. libfuse2 → libfuse2t64) may not show under the requested name.
                print_success "Installed: $package"
            fi
        done
    else
        print_warning "Batch install failed; retrying packages individually..."
        for package in "${missing[@]}"; do
            if apt_installed "$package"; then
                print_success "Already installed: $package"
                continue
            fi
            echo "Installing: $package"
            if install_apt_packages "$package"; then
                print_success "Successfully installed: $package"
            else
                print_error "Failed to install: $package"
                had_failure=true
            fi
        done
    fi
fi

# Research boxes want peak clocks, not Ubuntu's balanced/ondemand defaults.
# Runs even when packages were already present so re-runs converge the host.
configure_performance_power

if $had_failure; then
    print_error "APT installation completed with failures."
    exit 1
fi

echo "APT installation complete."
