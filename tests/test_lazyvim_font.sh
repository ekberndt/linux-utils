#!/bin/bash
set -euo pipefail

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

# The old pipeline failed most of the time, not every time.
i=0
while ((i < 20)); do
    if ! font_family_installed "JetBrainsMono Nerd Font Mono"; then
        echo "FAIL installed family vanished on iteration $i" >&2
        failures=$((failures + 1))
        break
    fi
    i=$((i + 1))
done
assert_eq "installed family survives repeated checks" "$i" "20"

test_result
