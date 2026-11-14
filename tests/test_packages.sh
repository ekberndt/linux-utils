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

uname() { echo "x86_64"; }
assert_eq "detect_arch maps x86_64 to amd64" "$(detect_arch)" "amd64"
uname() { echo "aarch64"; }
assert_eq "detect_arch maps aarch64 to arm64" "$(detect_arch)" "arm64"
uname() { echo "arm64"; }
assert_eq "detect_arch maps arm64 to arm64" "$(detect_arch)" "arm64"
unset -f uname

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/snaps.txt" <<'EOF'
htop # available
netron # missing on arch
edgeonly # no stable channel
EOF

# shellcheck disable=SC2329  # invoked indirectly by install_snap_packages
snap() {
    case "$1:${2:-}" in
        list:) printf 'Name Version\n' ;;
        info:htop) printf 'channels:\n  latest/stable: 3.5.3 2026-10-17 (6667) 4MB -\n' ;;
        info:edgeonly) printf 'channels:\n  latest/stable: --\n  latest/edge: 1.0\n' ;;
        info:*) return 1 ;;
        install:*) return 0 ;;
    esac
}
# shellcheck disable=SC2329
run_as_root() { "$@"; }

snap_output="$(install_snap_packages "$tmp/snaps.txt" 2>&1)"
assert_contains "snap installs available package" "$snap_output" "Successfully installed: htop"
assert_contains "snap skips package missing on arch" "$snap_output" "Skipped: netron"
assert_contains "snap skips package without stable channel" "$snap_output" "Skipped: edgeonly"

unset -f snap run_as_root
source "$ROOT/installers/lib/common.sh"

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

# missing_apt_packages: what apt would still install. A held package is
# installed; a half-installed one is not; a purely virtual name is satisfied by
# its installed provider, but a real package of a provided name still installs.
# shellcheck disable=SC2329
dpkg-query() {
    printf 'ii \tgit\t\n'
    printf 'hi \tpinned\t\n'
    printf 'iU \thalfdone\t\n'
    printf 'rc \tremoved\t\n'
    printf 'ii \tlibfuse2t64\tlibfuse2 (= 2.9.9-8.1build1)\n'
    printf 'ii \tmawk\tawk, realpkg\n'
}
# apt-cache translates its output; only the C locale says "Candidate".
# shellcheck disable=SC2329
apt-cache() {
    [[ "${LC_ALL:-}" == C ]] || { printf '  Installationskandidat: (keine)\n'; return; }
    case "$2" in
        libfuse2) printf 'libfuse2:\n  Installed: (none)\n  Candidate: (none)\n' ;;
        realpkg) printf 'realpkg:\n  Installed: (none)\n  Candidate: 1.0-1\n' ;;
    esac
}
assert_eq "only packages apt would install are missing" \
    "$(missing_apt_packages git pinned halfdone removed libfuse2 realpkg absent | xargs)" \
    "halfdone removed realpkg absent"
assert_eq "a provided virtual name counts as installed" \
    "$(apt_installed libfuse2 && echo yes || echo no)" "yes"
assert_eq "a translated apt-cache does not hide a virtual name" \
    "$(LANG=de_DE.UTF-8 apt_installed libfuse2 && echo yes || echo no)" "yes"
unset -f dpkg-query apt-cache

# apt_install refreshes the index first when the last `apt-get update` is over
# an hour old, and marks its own refresh so the next install skips it.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/apt-get" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$APT_LOG"
EOF
chmod +x "$tmp/bin/apt-get"
# shellcheck disable=SC2329
run_as_root() { "$@"; }
export APT_LOG="$tmp/apt.log"
APT_UPDATE_STAMP="$tmp/update-success-stamp"

# Steps run with stdin closed, so dpkg must not stop to ask about a conffile.
unattended="-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

touch "$APT_UPDATE_STAMP"
: > "$APT_LOG"
(PATH="$tmp/bin:$PATH" apt_install git)
assert_eq "an index refreshed within the hour installs without a refresh" \
    "$(xargs < "$APT_LOG")" "$unattended install git"

touch -d '2 hours ago' "$APT_UPDATE_STAMP"
: > "$APT_LOG"
(PATH="$tmp/bin:$PATH" apt_install git)
assert_eq "an index over an hour old is refreshed before installing" \
    "$(xargs < "$APT_LOG")" "update --error-on=any $unattended install git"

rm -f "$APT_UPDATE_STAMP"
: > "$APT_LOG"
(PATH="$tmp/bin:$PATH" apt_install git)
(PATH="$tmp/bin:$PATH" apt_install curl)
assert_eq "a missing stamp refreshes once, and the refresh marks the index fresh" \
    "$(xargs < "$APT_LOG")" "update --error-on=any $unattended install git $unattended install curl"
unset -f run_as_root

test_result
