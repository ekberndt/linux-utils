#!/bin/bash
set -uo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

uname() {
    if [[ "${1:-}" == "-s" ]]; then
        echo Linux
    else
        command uname "$@"
    fi
}

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
export -f uname gsettings

output="$(bash "$ROOT/installers/config/gnome.sh")"
assert_contains "GNOME favorites strips Help and App Center" \
    "$output" "set:['org.gnome.Terminal.desktop', 'firefox_firefox.desktop']"

dry_run_output="$(DRY_RUN=true bash "$ROOT/installers/config/gnome.sh")"
assert_not_contains "GNOME dry run does not mutate gsettings" "$dry_run_output" "set:"
assert_contains "GNOME dry run reports planned change" \
    "$dry_run_output" "would hide Help and App Center"

test_result
