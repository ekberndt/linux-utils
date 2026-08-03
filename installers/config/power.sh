#!/bin/bash

# Prefer peak performance over Ubuntu's balanced/ondemand defaults.
#
# Two layers: GNOME power-profiles-daemon (when "performance" exists) and the
# cpufreq governor (when the kernel exposes it). Always-plugged desktops still
# frequency-scale under balanced — this is not a no-op there.
#
# Honors DRY_RUN=true. Usually invoked via the orchestrator
# (`installers/config/install.sh`); also runnable standalone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

dry_run="${DRY_RUN:-false}"
gov_file="/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors"
conf="/etc/default/cpufrequtils"

if [[ "$(uname -s)" != "Linux" ]]; then
    print_warning "skipping power profile (not Linux)"
    exit 0
fi

if command -v powerprofilesctl >/dev/null 2>&1; then
    profile_list="$(powerprofilesctl list 2>/dev/null || true)"
    if grep -qE '^[[:space:]]*\*?[[:space:]]*performance:' <<<"$profile_list"; then
        current="$(powerprofilesctl get 2>/dev/null || true)"
        if [[ "$current" == "performance" ]]; then
            print_success "Power profile already performance"
        elif [[ "$dry_run" == true ]]; then
            print_warning "would set power profile: ${current:-unknown} -> performance"
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
    exit 0
fi
if ! grep -qw performance "$gov_file"; then
    print_warning "performance governor unavailable ($(cat "$gov_file")); leaving governor alone"
    exit 0
fi

if [[ -f "$conf" ]] && grep -q 'ENABLE="true"' "$conf" && grep -q 'GOVERNOR="performance"' "$conf"; then
    print_success "Already configured: $conf (performance)"
elif [[ "$dry_run" == true ]]; then
    print_warning "would write $conf (GOVERNOR=performance)"
else
    # Overwrite intentional: one performance policy for every machine this repo sets up.
    if sudo tee "$conf" >/dev/null <<'EOF'
# Managed by linux-utils config sync: prefer performance over balanced.
ENABLE="true"
GOVERNOR="performance"
MAX_SPEED="0"
MIN_SPEED="0"
EOF
    then
        print_success "Wrote $conf (GOVERNOR=performance)"
    else
        print_error "Failed to write $conf"
        exit 1
    fi
fi

if [[ "$dry_run" == true ]]; then
    print_warning "would set CPU governor to performance on all CPUs"
    exit 0
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
