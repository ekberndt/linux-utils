#!/bin/bash
set -uo pipefail

# font_family_installed used to pipe fc-list into `grep -q`. Under pipefail a
# match closed the pipe, fc-list got SIGPIPE, and the installer reported the
# Nerd Font missing. Drive the real function with a producer that keeps writing
# after the match.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=../installers/lazyvim/install.sh
source "$ROOT/installers/lazyvim/install.sh"

fc-list() {
    local i
    for i in $(seq 1 2000); do
        echo "Other Family $i"
    done
    echo "JetBrainsMono Nerd Font Mono,JetBrainsMono NFM"
    for i in $(seq 1 2000); do
        echo "Later Family $i"
    done
}

assert_eq "installed family is found" \
    "$(font_family_installed "JetBrainsMono Nerd Font Mono" && echo yes || echo no)" "yes"
assert_eq "comma-split alias is found" \
    "$(font_family_installed "JetBrainsMono NFM" && echo yes || echo no)" "yes"
assert_eq "missing family is not found" \
    "$(font_family_installed "Missing Font" && echo yes || echo no)" "no"

# A visible font is current: no brew lookup and no forced cache rebuild, which
# cost seconds on every run.
calls="$(mktemp)"
trap 'rm -f -- "$calls"' EXIT
# shellcheck disable=SC2329
fc-cache() { echo "fc-cache $*" >> "$calls"; }
# shellcheck disable=SC2329
find_brew() { echo "find_brew" >> "$calls"; return 1; }
install_nerd_font >/dev/null
assert_eq "an available font skips brew and fc-cache" "$(< "$calls")" ""

# shellcheck disable=SC2329
fc-list() { echo "Other Family"; }
# shellcheck disable=SC2329
find_brew() { echo "$calls.brew"; }
# shellcheck disable=SC2016  # $1 belongs to the stub.
printf '#!/bin/bash\n[[ "$1" == list ]] && echo %s\n' "$NERD_FONT_CASK" > "$calls.brew"
chmod +x "$calls.brew"
assert_eq "an installed cask fontconfig cannot see fails after a rebuild" \
    "$(install_nerd_font >/dev/null; echo $?)" "1"
assert_contains "that rebuild ran" "$(< "$calls")" "fc-cache -f"
rm -f -- "$calls.brew"

test_result
