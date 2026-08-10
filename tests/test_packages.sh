#!/bin/bash
set -uo pipefail

# Manifest parsing and the shared install helpers in installers/lib.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=../installers/lib/common.sh
source "$ROOT/installers/lib/common.sh"

assert_parse() {
    local name="$1" line="$2" want_pkg="$3" want_opt="$4" want_ppa="$5"
    package=""; optional=false; ppa=""
    if ! parse_package_line "$line"; then
        assert_eq "$name" "skipped" "parsed"
        return
    fi
    assert_eq "$name package" "$package" "$want_pkg"
    assert_eq "$name optional" "$optional" "$want_opt"
    assert_eq "$name ppa" "$ppa" "$want_ppa"
}

assert_skipped() {
    local name="$1" line="$2"
    if parse_package_line "$line"; then
        assert_eq "$name" "parsed" "skipped"
    else
        assert_eq "$name" "skipped" "skipped"
    fi
}

assert_parse "plain entry" "git # version control" "git" "false" ""
assert_parse "optional entry" "? sway # tiling" "sway" "true" ""
assert_parse "ppa entry" "foo | ppa:user/repo # desc" "foo" "false" "user/repo"
assert_skipped "comment line" "# comment only"
assert_skipped "blank line" ""

assert_eq "entry strips its comment" "$(package_entry "code --classic # editor")" \
    "code --classic"

unset INSTALLER_INSTALL_OPTIONALS
assert_eq "optionals are off by default" "$(install_optionals_env && echo on || echo off)" "off"
# shellcheck disable=SC2034  # read out of the environment by install_optionals_env.
INSTALLER_INSTALL_OPTIONALS=1
assert_eq "optionals honour the flag" "$(install_optionals_env && echo on || echo off)" "on"
unset INSTALLER_INSTALL_OPTIONALS

# install_batch: one transaction, falling back to one-at-a-time so a single bad
# package cannot take the rest of the list down with it.
never_installed() { return 1; }
fails_on_bad() { [[ "$*" != *bad* ]]; }

assert_eq "an empty batch is a no-op" \
    "$(install_batch pkgs fails_on_bad never_installed >/dev/null; echo $?)" "0"
assert_eq "a clean batch succeeds" \
    "$(install_batch pkgs fails_on_bad never_installed a b >/dev/null; echo $?)" "0"
assert_eq "a batch with a bad package fails" \
    "$(install_batch pkgs fails_on_bad never_installed a bad >/dev/null 2>&1; echo $?)" "1"

batch_output="$(install_batch pkgs fails_on_bad never_installed a bad c 2>&1)"
assert_contains "a failed batch retries individually" "$batch_output" "retrying individually"
assert_contains "the good packages still install" "$batch_output" "Successfully installed: c"
assert_contains "the bad package is reported" "$batch_output" "Failed to install: bad"

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    sudo() { return 1; }
    assert_eq "root runs commands directly" "$(run_as_root printf direct)" "direct"
else
    sudo() { printf 'elevated:%s' "$*"; }
    assert_eq "a normal user goes through sudo" "$(run_as_root printf direct)" \
        "elevated:printf direct"
fi
unset -f sudo

if command -v unshare >/dev/null 2>&1 && unshare -Ur true 2>/dev/null; then
    # shellcheck disable=SC2016 # COMMON_LIB is expanded by the nested shell.
    result="$(COMMON_LIB="$ROOT/installers/lib/common.sh" unshare -Ur env \
        COMMON_LIB="$ROOT/installers/lib/common.sh" bash -c \
        'source "$COMMON_LIB"; sudo() { return 1; }; run_as_root printf direct')"
    assert_eq "UID 0 bypasses sudo" "$result" "direct"
else
    echo "skip UID 0 privilege helper (user namespaces unavailable)"
fi

test_result
