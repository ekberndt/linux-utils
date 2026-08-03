#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

gsettings() {
    case "$1" in
        list-schemas)
            echo org.gnome.shell
            ;;
        get)
            echo "['yelp.desktop', 'org.gnome.Terminal.desktop', 'snap-store_snap-store.desktop', 'firefox_firefox.desktop', 'org.gnome.Software.desktop', 'snap-store_ubuntu-software.desktop']"
            ;;
        set)
            printf 'set:%s\n' "$4"
            ;;
    esac
}
export -f gsettings

output="$(bash "$ROOT/installers/config/gnome.sh")"
expected="set:['org.gnome.Terminal.desktop', 'firefox_firefox.desktop']"

if [[ "$output" != *"$expected"* ]]; then
    echo "FAIL GNOME favorites: $output" >&2
    exit 1
fi

dry_run_output="$(DRY_RUN=true bash "$ROOT/installers/config/gnome.sh")"
if [[ "$dry_run_output" == *"set:"* ]] || \
    [[ "$dry_run_output" != *"would hide Help and App Center"* ]]; then
    echo "FAIL GNOME favorites dry run: $dry_run_output" >&2
    exit 1
fi
