#!/bin/bash
set -uo pipefail

# Upgrades: a component asks cheaply whether anything is outdated, upgrades
# only then, reports old -> new, and fails loudly when the upgrade fails. Every
# manager is a stub on PATH that answers from fixture files under $STUB and
# logs its calls; HOME is scratch.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=../installers/lib/common.sh
source "$ROOT/installers/lib/common.sh"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
STUB="$tmp/stub"
mkdir -p "$tmp/bin" "$tmp/home" "$STUB"
export STUB

# stub <name>: a PATH binary that logs "<name> <args>" and runs stdin as its body.
stub() {
    {
        cat <<'EOF'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "$STUB/calls"
EOF
        cat
    } > "$tmp/bin/$1"
    chmod +x "$tmp/bin/$1"
}

# sudo authenticates with flags and otherwise runs the command, as the real
# one does once the installer's session is open.
stub sudo <<'EOF'
case "$1" in -*) exit 0 ;; esac
exec "$@"
EOF

# drain <due-file> <manager>: what a stub's successful upgrade does to the list
# its check answers from, unless "<manager>-stuck" says the manager declined.
cat > "$tmp/drain" <<'EOF'
[[ -e "$STUB/$2-stuck" ]] || : > "$STUB/$1"
EOF
export DRAIN="$tmp/drain"

# component <name> [VAR=value]...: run installers/<name>/install.sh as a step
# would, leaving its exit in $rc, its status records in $records, its stub
# calls in $calls, and its output in $tmp/out.
component() {
    local name="$1"
    shift
    : > "$STUB/calls"
    : > "$tmp/status"
    env -i HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" STUB="$STUB" DRAIN="$DRAIN" \
        INSTALLER_STATUS_FILE="$tmp/status" "$@" \
        bash "$ROOT/installers/$name/install.sh" >"$tmp/out" 2>&1 </dev/null
    rc=$?
    records="$(< "$tmp/status")"
    calls="$(< "$STUB/calls")"
}

# ran <call>: whether a stub logged exactly this call.
ran() { grep -qFx -- "$1" <<<"$calls" && echo ran || echo "did not run"; }
updated() { printf 'updated\t%s' "$1"; }
errored() { printf 'error\t%s' "$1"; }
warned() { printf 'warn\t%s' "$1"; }

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    as_root=""
else
    as_root="sudo "
fi

# --- Version reading and comparison -----------------------------------------

newer() { version_newer "$1" "$2" && echo newer || echo "not newer"; }
assert_eq "a two-digit minor is newer than a one-digit one" "$(newer 1.10.0 1.9.0)" "newer"
assert_eq "an older release is not newer" "$(newer 1.9.0 1.10.0)" "not newer"
assert_eq "a tag's v prefix is ignored" "$(newer v0.10.0 0.10.0)" "not newer"
assert_eq "a later tag is newer" "$(newer v0.11.0 0.10.0)" "newer"
assert_eq "a two-digit patch is newer" "$(newer 0.34.10 0.34.9)" "newer"
assert_eq "a two-digit major is newer" "$(newer v10.2.0 8.5.1)" "newer"
assert_eq "a missing trailing field counts as zero" "$(newer 1.0 1.0.0)" "not newer"
assert_eq "an extra nonzero field is newer" "$(newer 1.0.1 1.0)" "newer"

assert_eq "ollama names the client version after an older server's" \
    "$(printf 'ollama version is 0.34.0\nWarning: client version is 0.34.1\n' | last_version)" \
    "0.34.1"
assert_eq "an unreachable ollama server still yields the client version" \
    "$(printf 'Warning: could not connect to a running Ollama instance\nWarning: client version is 0.34.1\n' | last_version)" \
    "0.34.1"
assert_eq "a build hash is not a version" "$(echo 'grok 1.0.34 (3736acbc8658)' | last_version)" "1.0.34"
assert_eq "a product name after the version is ignored" \
    "$(echo '2.1.325 (Claude Code)' | last_version)" "2.1.325"
assert_eq "bazelisk's own version reads without its v" \
    "$(echo 'Bazelisk version: v1.29.0' | last_version)" "1.29.0"

stub curl <<'EOF'
case "$1" in
    -fsSIL) cat "$STUB/landing" ;;
    -fsSL)
        [[ -e "$STUB/download-fails" ]] && exit 22
        if [[ "${3:-}" == -o ]]; then cp "$STUB/asset" "$4"; else cat "$STUB/script"; fi
        ;;
esac
EOF
# latest <owner/repo> <tag>: where /releases/latest lands once redirects settle.
latest() {
    printf 'https://github.com/%s/releases/tag/%s' "$1" "$2" > "$STUB/landing"
}

latest o/r v1.2.3
assert_eq "the latest release is the tag GitHub lands on" \
    "$(PATH="$tmp/bin:$PATH" latest_release o/r)" "v1.2.3"
assert_contains "the lookup follows a moved repository's redirects" "$(< "$STUB/calls")" \
    "curl -fsSIL -o /dev/null -w %{url_effective} https://github.com/o/r/releases/latest"
printf 'https://github.com/o/r/releases' > "$STUB/landing"
assert_eq "a repo without releases has no latest" \
    "$(PATH="$tmp/bin:$PATH" latest_release o/r || echo none)" "none"

# --- apt: whole-machine upgrade under the hourly index rule -----------------

stub dpkg-query <<'EOF'
printf 'ii \tgit\t\n'
EOF
stub apt-cache <<'EOF'
EOF
stub apt-get <<'EOF'
case "$*" in
    "-s upgrade") cat "$STUB/apt-upgrades" ;;
    "-s autoremove") cat "$STUB/apt-removals" ;;
    "update --error-on=any") [[ ! -e "$STUB/apt-update-fails" ]] ;;
    *" upgrade") [[ -e "$STUB/apt-fails" ]] && exit 100; bash "$DRAIN" apt-upgrades apt ;;
    *" autoremove") bash "$DRAIN" apt-removals apt ;;
esac
EOF
printf 'git # version control\n' > "$STUB/apt_packages.txt"
stamp="$tmp/update-success-stamp"
apt_component() {
    component apt INSTALLER_APT_PACKAGES_FILE="$STUB/apt_packages.txt" APT_UPDATE_STAMP="$stamp"
}

cat > "$STUB/apt-upgrades" <<'EOF'
NOTE: This is only a simulation!
Inst libssl3t64 [3.0.13-0ubuntu3.4] (3.0.13-0ubuntu3.5 Ubuntu:24.04/noble-updates [arm64])
Inst tailscale [1.104.7] (1.106.0 Tailscale:stable [arm64])
Conf libssl3t64 (3.0.13-0ubuntu3.5 Ubuntu:24.04/noble-updates [arm64])
Conf tailscale (1.106.0 Tailscale:stable [arm64])
EOF
: > "$STUB/apt-removals"
touch -d '2 hours ago' "$stamp"
apt_component
assert_eq "an apt upgrade succeeds" "$rc" "0"
assert_contains "an index over an hour old is refreshed" "$calls" "apt-get update"
assert_contains "the upgrade runs unattended" "$calls" \
    "apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade"
assert_contains "an apt upgrade names old -> new" "$records" \
    "$(updated "libssl3t64 3.0.13-0ubuntu3.4 -> 3.0.13-0ubuntu3.5")"
assert_contains "every upgraded package is named" "$records" "$(updated "tailscale 1.104.7 -> 1.106.0")"
assert_not_contains "the simulation needs no root" "$calls" "sudo apt-get -s"

printf 'NOTE: This is only a simulation!\n0 upgraded, 0 newly installed\n' > "$STUB/apt-upgrades"
apt_component
assert_eq "a current machine succeeds" "$rc" "0"
assert_eq "a current machine reports nothing, so it reads already current" "$records" ""
assert_not_contains "an index refreshed within the hour is not refreshed" "$calls" "apt-get update"
assert_not_contains "nothing to upgrade runs no upgrade" "$calls" "force-confold upgrade"
assert_not_contains "a current machine never reaches sudo" "$calls" "sudo"

printf 'Remv linux-image-6.8.0-40-generic [6.8.0-40.40]\n' > "$STUB/apt-removals"
apt_component
assert_contains "autoremove runs when apt would remove something" "$calls" \
    "force-confold autoremove"
assert_contains "an autoremoved package is named" "$records" \
    "$(updated "linux-image-6.8.0-40-generic removed")"
: > "$STUB/apt-removals"

# apt-get update exits 0 when a source fails; --error-on=any makes it say so.
touch -d '2 hours ago' "$stamp" "$STUB/apt-update-fails"
apt_component
assert_eq "a failed index refresh fails the component" "$rc" "1"
assert_contains "a failed index refresh is not mistaken for current" "$calls" \
    "apt-get update --error-on=any"
assert_not_contains "a failed index refresh checks nothing against the stale index" "$calls" \
    "apt-get -s upgrade"
assert_eq "a failed index refresh leaves the stamp stale for the next run" \
    "$(refreshed_within_hour "$stamp" && echo fresh || echo stale)" "stale"
rm "$STUB/apt-update-fails"
touch "$stamp"

printf 'Inst libssl3t64 [3.0.13-0ubuntu3.4] (3.0.13-0ubuntu3.5 Ubuntu:24.04/noble-updates [arm64])\n' \
    > "$STUB/apt-upgrades"
touch "$STUB/apt-fails"
apt_component
assert_eq "a failed apt upgrade fails the component" "$rc" "1"
assert_contains "a failed apt upgrade says so" "$records" "$(errored "apt-get upgrade failed")"
assert_not_contains "a failed apt upgrade claims no upgrade" "$records" "updated"
rm "$STUB/apt-fails"

# --- Homebrew: the same function on Linux and macOS ------------------------

stub brew <<'EOF'
case "$1" in
    --repository) echo "$STUB/brew-repo" ;;
    outdated) cat "$STUB/brew-outdated" ;;
    upgrade) [[ -e "$STUB/brew-fails" ]] && exit 1; bash "$DRAIN" brew-outdated brew ;;
esac
EOF
mkdir -p "$STUB/brew-repo/.git"
brew_upgrade() {
    : > "$STUB/calls"
    : > "$tmp/status"
    (PATH="$tmp/bin:$PATH" INSTALLER_STATUS_FILE="$tmp/status" \
        upgrade_brew_packages "$tmp/bin/brew" >/dev/null 2>&1)
    rc=$?
    records="$(< "$tmp/status")"
    calls="$(< "$STUB/calls")"
}

cat > "$STUB/brew-outdated" <<'EOF'
lazygit (0.44.1) < 0.45.0
htop (3.3.0) < 3.4.0 [pinned at 3.3.0]
scroll-reverser (1.8) != 1.9
EOF
touch -d '2 hours ago' "$STUB/brew-repo/.git/FETCH_HEAD"
brew_upgrade
assert_eq "a brew upgrade succeeds" "$rc" "0"
assert_contains "a stale Homebrew index is refreshed" "$calls" "brew update"
assert_contains "outdated formulae are upgraded" "$calls" "brew upgrade"
assert_contains "a formula upgrade names old -> new" "$records" "$(updated "lazygit 0.44.1 -> 0.45.0")"
assert_contains "a cask upgrade names old -> new" "$records" "$(updated "scroll-reverser 1.8 -> 1.9")"
assert_not_contains "a pinned formula is not reported" "$records" "htop"

touch "$STUB/brew-repo/.git/FETCH_HEAD"
printf 'htop (3.3.0) < 3.4.0 [pinned at 3.3.0]\n' > "$STUB/brew-outdated"
brew_upgrade
assert_not_contains "a Homebrew index fetched within the hour is not refreshed" "$calls" "brew update"
assert_not_contains "only a pinned formula outdated runs no upgrade" "$calls" "brew upgrade"
assert_eq "only a pinned formula outdated reads already current" "$records" ""

printf 'lazygit (0.44.1) < 0.45.0\n' > "$STUB/brew-outdated"
touch "$STUB/brew-fails"
brew_upgrade
assert_eq "a failed brew upgrade fails" "$rc" "1"
assert_contains "a failed brew upgrade says so" "$records" "$(errored "brew upgrade failed")"
rm "$STUB/brew-fails"

# --- snap: every installed snap ---------------------------------------------

stub snap <<'EOF'
case "$1 ${2:-}" in
    "list ") cat "$STUB/snap-list" ;;
    "refresh --list") cat "$STUB/snap-due" ;;
    "refresh ") [[ -e "$STUB/snap-fails" ]] && exit 1; bash "$DRAIN" snap-due snap ;;
esac
EOF
cat > "$STUB/snap-list" <<'EOF'
Name     Version   Rev   Tracking       Publisher   Notes
core22   20240111  1380  latest/stable  canonical✓  base
firefox  132.0     5000  latest/stable  mozilla✓    -
netron   7.0       100   latest/stable  lutzroeder  -
EOF
cat > "$STUB/snap-due" <<'EOF'
Name     Version   Rev   Size   Publisher   Notes
core22   20240111  1400  77MB   canonical✓  base
firefox  133.0     5100  250MB  mozilla✓    -
EOF
component snap
assert_eq "a snap refresh succeeds" "$rc" "0"
assert_eq "due snaps are refreshed" "$(ran "${as_root}snap refresh")" "ran"
assert_contains "a snap refresh names old -> new" "$records" "$(updated "firefox 132.0 -> 133.0")"
assert_contains "a new revision with the same version is still named" "$records" \
    "$(updated "core22 20240111")"

echo "All snaps up to date." > "$STUB/snap-due"
component snap
assert_eq "nothing due runs no refresh" "$(ran "snap refresh")" "did not run"
assert_eq "nothing due reads already current" "$records" ""

# A held snap, or one whose app is running, stays due after `snap refresh`.
printf 'Name Version Rev Size Publisher Notes\nfirefox 133.0 5100 250MB mozilla -\n' > "$STUB/snap-due"
touch "$STUB/snap-stuck"
component snap
assert_eq "a snap the refresh declined does not fail the step" "$rc" "0"
assert_contains "a snap still due after the refresh is a warning" "$records" \
    "$(warned "Still outdated after upgrading: firefox 132.0 -> 133.0")"
assert_not_contains "a snap still due is not reported updated" "$records" "updated"
rm "$STUB/snap-stuck"

touch "$STUB/snap-fails"
component snap
assert_eq "a failed snap refresh fails the component" "$rc" "1"
assert_contains "a failed snap refresh says so" "$records" "$(errored "snap refresh failed")"
rm "$STUB/snap-fails"

# --- Flatpak: both scopes, root only for the system one ---------------------

stub flatpak <<'EOF'
case "$*" in
    "remote-ls --updates --user --columns=application,version") cat "$STUB/flatpak-user" ;;
    "remote-ls --updates --system --columns=application,version") cat "$STUB/flatpak-system" ;;
    "update "*)
        [[ -e "$STUB/flatpak-fails" ]] && exit 1
        if [[ "$2" == --user ]]; then bash "$DRAIN" flatpak-user flatpak; else bash "$DRAIN" flatpak-system flatpak; fi
        ;;
esac
EOF
printf 'org.gimp.GIMP\t3.0.2\norg.freedesktop.Platform.GL.default\t\n' > "$STUB/flatpak-user"
: > "$STUB/flatpak-system"
component flatpak
assert_eq "a Flatpak update succeeds" "$rc" "0"
assert_contains "user Flatpaks update without root" "$calls" "flatpak update --user -y --noninteractive"
assert_not_contains "nothing system-wide asks for root" "$calls" "sudo"
assert_contains "an updated app is named with its version" "$records" "$(updated "org.gimp.GIMP 3.0.2")"
assert_contains "an updated runtime without a version is named" "$records" \
    "$(updated "org.freedesktop.Platform.GL.default")"

: > "$STUB/flatpak-user"
printf 'com.spotify.Client\t1.2.50\n' > "$STUB/flatpak-system"
component flatpak
assert_contains "system Flatpaks update as root" "$calls" \
    "${as_root}flatpak update --system -y --noninteractive"
assert_not_contains "nothing in the user scope runs no user update" "$calls" "update --user"

: > "$STUB/flatpak-system"
component flatpak
assert_eq "no Flatpak updates read already current" "$records" ""

printf 'org.gimp.GIMP\t3.0.2\n' > "$STUB/flatpak-user"
touch "$STUB/flatpak-fails"
component flatpak
assert_eq "a failed Flatpak update fails the component" "$rc" "1"
assert_contains "a failed Flatpak update says so" "$records" "$(errored "flatpak update --user failed")"
rm "$STUB/flatpak-fails"

# --- npm: global packages, through sudo only for a root-owned prefix --------

stub npm <<'EOF'
case "$*" in
    "outdated -g --parseable")
        cat "$STUB/npm-outdated"
        [[ -s "$STUB/npm-outdated" || -e "$STUB/npm-check-fails" ]] && exit 1
        exit 0
        ;;
    "root -g") cat "$STUB/npm-root" ;;
    "update -g") [[ -e "$STUB/npm-fails" ]] && exit 1; bash "$DRAIN" npm-outdated npm ;;
esac
EOF
mkdir -p "$STUB/user-modules" "$STUB/root-modules"
chmod a-w "$STUB/root-modules"
cat > "$STUB/npm-outdated" <<'EOF'
/usr/lib/node_modules/npm:npm@12.3.0:npm@12.2.2:npm@12.3.0:global
/usr/lib/node_modules/@openai/codex:@openai/codex@0.2.0:@openai/codex@0.1.0:@openai/codex@0.2.0:global
/usr/lib/node_modules/left-pad:left-pad@1.0.0:left-pad@1.0.0:left-pad@2.0.0:global
EOF
echo "$STUB/user-modules" > "$STUB/npm-root"
component npm
assert_eq "an npm upgrade succeeds" "$rc" "0"
assert_contains "a user-writable prefix updates without sudo" "$calls" "npm update -g"
assert_not_contains "a user-writable prefix never reaches sudo" "$calls" "sudo"
assert_contains "an npm upgrade names old -> new" "$records" "$(updated "npm 12.2.2 -> 12.3.0")"
assert_contains "a scoped package keeps its scope" "$records" "$(updated "@openai/codex 0.1.0 -> 0.2.0")"
assert_not_contains "a major npm update would not take is not reported" "$records" "left-pad"

if [[ -n "$as_root" ]]; then
    printf '/usr/lib/node_modules/npm:npm@12.3.0:npm@12.2.2:npm@12.3.0:global\n' > "$STUB/npm-outdated"
    echo "$STUB/root-modules" > "$STUB/npm-root"
    component npm
    assert_contains "a root-owned prefix updates through sudo" "$calls" "sudo npm update -g"
fi

printf '/usr/lib/node_modules/left-pad:left-pad@1.0.0:left-pad@1.0.0:left-pad@2.0.0:global\n' \
    > "$STUB/npm-outdated"
component npm
assert_not_contains "nothing npm would move runs no update" "$calls" "update -g"
assert_eq "nothing npm would move reads already current" "$records" ""

: > "$STUB/npm-outdated"
touch "$STUB/npm-check-fails"
component npm
assert_eq "an npm check that fails without listing anything fails" "$rc" "1"
assert_contains "a failed npm check says so" "$records" \
    "$(errored "Could not check global npm packages for upgrades")"
rm "$STUB/npm-check-fails"

printf '/usr/lib/node_modules/npm:npm@12.3.0:npm@12.2.2:npm@12.3.0:global\n' > "$STUB/npm-outdated"
echo "$STUB/user-modules" > "$STUB/npm-root"
touch "$STUB/npm-fails"
component npm
assert_eq "a failed npm update fails the component" "$rc" "1"
assert_contains "a failed npm update says so" "$records" "$(errored "npm update -g failed")"
rm "$STUB/npm-fails"

# --- pnpm: global packages ---------------------------------------------------

stub pnpm <<'EOF'
case "$*" in
    "outdated -g --format json")
        cat "$STUB/pnpm-outdated"
        [[ "$(cat "$STUB/pnpm-outdated")" == "{}" ]] || exit 1
        ;;
    "update -g") [[ -e "$STUB/pnpm-fails" ]] && exit 1; echo "{}" > "$STUB/pnpm-outdated" ;;
esac
EOF
cat > "$STUB/pnpm-outdated" <<'EOF'
{
  "typescript": {"current": "5.6.2", "latest": "5.7.0", "wanted": "5.7.0", "isDeprecated": false},
  "eslint": {"current": "8.57.0", "latest": "9.0.0", "wanted": "8.57.0", "isDeprecated": false}
}
EOF
component pnpm
assert_eq "a pnpm upgrade succeeds" "$rc" "0"
assert_contains "outdated pnpm packages are updated" "$calls" "pnpm update -g"
assert_contains "a pnpm upgrade names old -> new" "$records" "$(updated "typescript 5.6.2 -> 5.7.0")"
assert_not_contains "a major pnpm update would not take is not reported" "$records" "eslint"

echo "{}" > "$STUB/pnpm-outdated"
component pnpm
assert_not_contains "nothing outdated runs no pnpm update" "$calls" "update -g"
assert_eq "nothing outdated in pnpm reads already current" "$records" ""

echo " ERR_PNPM_META_FETCH_FAIL" > "$STUB/pnpm-outdated"
component pnpm
assert_eq "an unreadable pnpm check fails" "$rc" "1"
assert_contains "an unreadable pnpm check says so" "$records" \
    "$(errored "Could not check global pnpm packages for upgrades")"

printf '{"typescript": {"current": "5.6.2", "wanted": "5.7.0"}}\n' > "$STUB/pnpm-outdated"
touch "$STUB/pnpm-fails"
component pnpm
assert_eq "a failed pnpm update fails the component" "$rc" "1"
assert_contains "a failed pnpm update says so" "$records" "$(errored "pnpm update -g failed")"
rm "$STUB/pnpm-fails" "$tmp/bin/pnpm"

# --- pip: --user packages ----------------------------------------------------

stub python3 <<'EOF'
case "$*" in
    "-m pip --version") ;;
    "-m pip list --user --outdated --format=columns") cat "$STUB/pip-outdated" ;;
    "-m pip list --user --format=freeze") cat "$STUB/pip-installed" ;;
    "-m pip index versions pip") [[ ! -e "$STUB/pip-offline" ]] ;;
    "-m pip install --user --upgrade "*) [[ -e "$STUB/pip-fails" ]] && exit 1; bash "$DRAIN" pip-outdated pip ;;
esac
EOF
echo "requests==2.31.0" > "$STUB/pip-installed"
cat > "$STUB/pip-outdated" <<'EOF'
Package  Version Latest Type
-------- ------- ------ -----
requests 2.31.0  2.32.3 wheel
EOF
component pip
assert_eq "a pip upgrade succeeds" "$rc" "0"
assert_contains "outdated user packages are upgraded" "$calls" \
    "python3 -m pip install --user --upgrade requests"
assert_contains "a pip upgrade names old -> new" "$records" "$(updated "requests 2.31.0 -> 2.32.3")"

component pip VIRTUAL_ENV="$tmp/venv"
assert_contains "an active virtualenv skips pip, saying why" "$records" "skipped"
assert_not_contains "an active virtualenv asks pip nothing" "$calls" "pip list"

: > "$STUB/pip-outdated"
component pip
assert_not_contains "nothing outdated runs no pip install" "$calls" "pip install"
assert_eq "nothing outdated in pip reads already current" "$records" ""

# pip lists nothing outdated, exiting 0, when it cannot reach the index.
touch "$STUB/pip-offline"
component pip
assert_eq "an unreachable index fails the pip step" "$rc" "1"
assert_contains "an unreachable index is not mistaken for current" "$records" \
    "$(errored "Could not reach the package index to check pip user packages")"
rm "$STUB/pip-offline"

: > "$STUB/pip-installed"
component pip
assert_not_contains "no user packages asks the index nothing" "$calls" "--outdated"
echo "requests==2.31.0" > "$STUB/pip-installed"

printf 'Package Version Latest Type\n------- ------- ------ -----\nrequests 2.31.0 2.32.3 wheel\n' \
    > "$STUB/pip-outdated"
touch "$STUB/pip-fails"
component pip
assert_eq "a failed pip upgrade fails the component" "$rc" "1"
assert_contains "a failed pip upgrade says so" "$records" \
    "$(errored "pip install --user --upgrade failed")"
rm "$STUB/pip-fails" "$tmp/bin/python3"

# --- pipx: no outdated check, so compare versions around upgrade-all --------

stub pipx <<'EOF'
case "$*" in
    "list --short") cat "$STUB/pipx-list" ;;
    "runpip black index versions pip") [[ ! -e "$STUB/pipx-offline" ]] ;;
    upgrade-all)
        [[ -e "$STUB/pipx-fails" ]] && exit 1
        [[ -e "$STUB/pipx-next" ]] && mv "$STUB/pipx-next" "$STUB/pipx-list"
        exit 0
        ;;
esac
EOF
printf 'black 24.1.0\nruff 0.5.0\n' > "$STUB/pipx-list"
printf 'black 24.2.0\nruff 0.5.0\n' > "$STUB/pipx-next"
component pipx
assert_eq "a pipx upgrade succeeds" "$rc" "0"
assert_contains "a moved pipx app names old -> new" "$records" "$(updated "black 24.1.0 -> 24.2.0")"
assert_not_contains "an unmoved pipx app is not reported" "$records" "ruff"

component pipx
assert_eq "pipx apps that did not move read already current" "$records" ""

# pip inside each app's venv is already satisfied, exiting 0, when offline.
touch "$STUB/pipx-offline"
component pipx
assert_eq "an unreachable index fails the pipx step" "$rc" "1"
assert_contains "an unreachable index is not mistaken for current pipx apps" "$records" \
    "$(errored "Could not reach the package index to upgrade pipx apps")"
rm "$STUB/pipx-offline"

: > "$STUB/pipx-list"
component pipx
assert_not_contains "no pipx apps runs no upgrade" "$calls" "upgrade-all"

echo "black 24.2.0" > "$STUB/pipx-list"
touch "$STUB/pipx-fails"
component pipx
assert_eq "a failed pipx upgrade fails the component" "$rc" "1"
assert_contains "a failed pipx upgrade says so" "$records" "$(errored "pipx upgrade-all failed")"
rm "$STUB/pipx-fails"

# --- uv: self update for a standalone install, then every tool --------------

stub uv <<'EOF'
case "$*" in
    --version) echo "uv $(cat "$STUB/uv-version") (x86_64-unknown-linux-gnu)" ;;
    "self update")
        [[ -e "$STUB/uv-fails" ]] && exit 1
        [[ -e "$STUB/uv-next" ]] && mv "$STUB/uv-next" "$STUB/uv-version"
        exit 0
        ;;
    "tool list") cat "$STUB/uv-tools" ;;
    "tool list --outdated") cat "$STUB/uv-outdated" ;;
    "tool upgrade --all") mv "$STUB/uv-tools-next" "$STUB/uv-tools" ;;
esac
EOF
mkdir -p "$tmp/home/.config/uv"
touch "$tmp/home/.config/uv/uv-receipt.json"
echo 0.13.8 > "$STUB/uv-version"
echo 0.13.9 > "$STUB/uv-next"
printf 'wandb v0.19.0\n- wandb\n- wb\n' > "$STUB/uv-tools"
printf 'wandb v0.19.0 [latest: 0.19.1]\n- wandb\n- wb\n' > "$STUB/uv-outdated"
printf 'wandb v0.19.1\n- wandb\n- wb\n' > "$STUB/uv-tools-next"
component uv
assert_eq "a uv upgrade succeeds" "$rc" "0"
assert_contains "a standalone uv updates itself" "$records" "$(updated "uv 0.13.8 -> 0.13.9")"
assert_contains "an outdated uv tool names old -> new" "$records" "$(updated "wandb v0.19.0 -> v0.19.1")"

rm "$tmp/home/.config/uv/uv-receipt.json"
: > "$STUB/uv-outdated"
component uv
assert_not_contains "a uv another manager installed is left to it" "$calls" "self update"
assert_not_contains "current uv tools are not upgraded" "$calls" "tool upgrade"
assert_eq "a current uv reads already current" "$records" ""

touch "$tmp/home/.config/uv/uv-receipt.json" "$STUB/uv-fails"
component uv
assert_eq "a failed uv self update fails the component" "$rc" "1"
assert_contains "a failed uv self update says so" "$records" "$(errored "Failed to update uv")"
rm "$STUB/uv-fails"

# --- Agent CLIs: their own updaters ------------------------------------------

stub claude <<'EOF'
case "$1" in
    --version) echo "$(cat "$STUB/claude-version") (Claude Code)" ;;
    update)
        [[ -e "$STUB/claude-fails" ]] && exit 1
        [[ -e "$STUB/claude-next" ]] && mv "$STUB/claude-next" "$STUB/claude-version"
        exit 0
        ;;
esac
EOF
echo 2.1.325 > "$STUB/claude-version"
echo 2.1.330 > "$STUB/claude-next"
component claude
assert_eq "a Claude Code update succeeds" "$rc" "0"
assert_contains "an installed CLI runs its updater" "$calls" "claude update"
assert_not_contains "an installed CLI fetches no installer" "$calls" "curl"
assert_contains "a CLI update names old -> new" "$records" "$(updated "claude 2.1.325 -> 2.1.330")"

component claude
assert_eq "a CLI whose updater changed nothing reads already current" "$records" ""

touch "$STUB/claude-fails"
component claude
assert_eq "a failed CLI update fails the component" "$rc" "1"
assert_contains "a failed CLI update says so" "$records" "$(errored "Failed to update claude")"
rm "$STUB/claude-fails"

# OpenCode's script installs only to ~/.opencode/bin, which the run's PATH
# lacks until the component adds it.
cat > "$STUB/script" <<'EOF'
mkdir -p "$HOME/.opencode/bin"
printf '#!/bin/bash\necho 1.0.0\n' > "$HOME/.opencode/bin/opencode"
chmod +x "$HOME/.opencode/bin/opencode"
EOF
component opencode
assert_eq "a fresh OpenCode install succeeds" "$rc" "0"
assert_contains "a fresh OpenCode install names its version" "$records" \
    "$(printf 'installed\topencode (1.0.0)')"

# --- Ollama: no updater, so compare with the latest release -----------------

stub ollama <<'EOF'
[[ -e "$STUB/ollama-unreadable" ]] && { echo "ollama: cannot execute"; exit 1; }
echo "ollama version is 0.34.0"
echo "Warning: client version is $(cat "$STUB/ollama-client")"
EOF
# shellcheck disable=SC2016 # Expanded when the vendor script runs.
printf 'echo 0.35.0 > "$STUB/ollama-client"\n' > "$STUB/script"
echo 0.34.1 > "$STUB/ollama-client"
latest ollama/ollama v0.35.0
component ollama
assert_eq "an Ollama reinstall succeeds" "$rc" "0"
assert_contains "a newer release re-runs the vendor script" "$calls" \
    "curl -fsSL https://ollama.com/install.sh"
assert_contains "the reinstall names old -> new" "$records" "$(updated "ollama 0.34.1 -> 0.35.0")"

latest ollama/ollama v0.35.0
component ollama
assert_not_contains "a client at the latest release is not reinstalled, whatever the server runs" \
    "$calls" "curl -fsSL"
assert_eq "an Ollama at the latest release reads already current" "$records" ""

# shellcheck disable=SC2016 # Expanded when the vendor script runs.
printf 'echo "download failed"; exit 0\n' > "$STUB/script"
latest ollama/ollama v0.36.0
component ollama
assert_eq "a vendor script that exits 0 without upgrading fails" "$rc" "1"
assert_contains "a reinstall that did not move the version says so" "$records" \
    "$(errored "ollama is still 0.35.0 after reinstalling; the latest is 0.36.0")"

touch "$STUB/ollama-unreadable"
component ollama
assert_eq "an unreadable Ollama version fails" "$rc" "1"
assert_contains "an unreadable Ollama version says so" "$records" \
    "$(errored "Could not read the installed ollama version")"
rm "$STUB/ollama-unreadable"

printf 'https://github.com/ollama/ollama/releases' > "$STUB/landing"
component ollama
assert_eq "a failed release lookup fails" "$rc" "1"
assert_contains "a failed release lookup says so" "$records" \
    "$(errored "Could not find the latest ollama/ollama release")"

# --- bazelisk and buildtools: replace binaries older than the release -------

usrlocal="$tmp/usrlocal"
mkdir -p "$usrlocal"
ln -s bazelisk "$usrlocal/bazel"
# Its --version answers with Bazel's; only `version` with a Bazel stand-in
# names bazelisk's own.
cat > "$usrlocal/bazelisk" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == version && "${USE_BAZEL_VERSION:-}" == /* ]]; then
    echo "Bazelisk version: v1.29.0"
    exec "$USE_BAZEL_VERSION"
fi
echo "bazel 9.3.2"
EOF
chmod +x "$usrlocal/bazelisk"
cp "$usrlocal/bazelisk" "$STUB/old-bazelisk"
echo "new bazelisk" > "$STUB/asset"

latest bazelbuild/bazelisk v1.29.0
component bazelisk INSTALLER_BIN_DIR="$usrlocal"
assert_eq "a current bazelisk succeeds" "$rc" "0"
assert_not_contains "bazelisk's own version, not Bazel's, is compared" "$calls" "releases/download"
assert_eq "a current bazelisk reads already current" "$records" ""

latest bazelbuild/bazelisk v1.30.0
touch "$STUB/download-fails"
component bazelisk INSTALLER_BIN_DIR="$usrlocal"
assert_eq "a failed bazelisk download fails" "$rc" "1"
assert_eq "a failed download leaves the installed bazelisk in place" \
    "$(cmp -s "$usrlocal/bazelisk" "$STUB/old-bazelisk" && echo intact || echo damaged)" "intact"
rm "$STUB/download-fails"

component bazelisk INSTALLER_BIN_DIR="$usrlocal"
assert_contains "a newer bazelisk downloads that release" "$calls" \
    "releases/download/v1.30.0/bazelisk-linux-"
assert_eq "the new bazelisk replaces the old" "$(< "$usrlocal/bazelisk")" "new bazelisk"
assert_contains "a bazelisk upgrade names old -> new" "$records" "$(updated "bazelisk 1.29.0 -> 1.30.0")"

for tool in buildifier buildozer unused-deps; do
    printf '#!/bin/bash\necho "%s version: 8.0.0 "\necho "%s scm revision: 0cfe520f"\n' \
        "${tool/-/_}" "${tool/-/_}" > "$usrlocal/$tool"
    chmod +x "$usrlocal/$tool"
done
latest bazel-contrib/buildtools v8.0.0
component buildtools INSTALLER_BIN_DIR="$usrlocal"
assert_eq "current buildtools read already current" "$records" ""
latest bazel-contrib/buildtools v8.2.1
component buildtools INSTALLER_BIN_DIR="$usrlocal"
assert_contains "an older buildifier is replaced" "$records" "$(updated "buildifier 8.0.0 -> 8.2.1")"
assert_contains "an older unused-deps is replaced" "$records" "$(updated "unused-deps 8.0.0 -> 8.2.1")"

# --- cargo: rustup update on `rustup check`, crates through cargo install ---

stub rustup <<'EOF'
case "$*" in
    check) cat "$STUB/rustup-check"; [[ ! -e "$STUB/rustup-check-fails" ]] ;;
    update) [[ -e "$STUB/rustup-fails" ]] && exit 1; bash "$DRAIN" rustup-check rustup ;;
    "run stable rustc --version") echo "rustc 1.100.0 (0ef1bc386 2026-11-09)" ;;
    "run stable cargo install --list") cat "$STUB/crates" ;;
    "run stable cargo install "*)
        [[ -e "$STUB/cargo-fails" ]] && exit 101
        [[ -e "$STUB/crates-next" ]] && mv "$STUB/crates-next" "$STUB/crates"
        exit 0
        ;;
esac
EOF
mkdir -p "$tmp/home/.cargo/bin"
for bin in just dust just-lsp rg bat; do
    printf '#!/bin/bash\n' > "$tmp/home/.cargo/bin/$bin"
    chmod +x "$tmp/home/.cargo/bin/$bin"
done
# shellcheck disable=SC2016 # The literal line the component looks for.
printf 'export PATH="$HOME/.cargo/bin:$PATH"\n' | tee "$tmp/home/.profile" > "$tmp/home/.bashrc"
printf 'du-dust v1.2.6:\n    dust\njust v1.58.0:\n    just\njust-lsp v0.8.0:\n    just-lsp\n' \
    > "$STUB/crates"
printf 'du-dust v1.2.6:\n    dust\njust v1.59.0:\n    just\njust-lsp v0.8.0:\n    just-lsp\n' \
    > "$STUB/crates-next"

# installs <key>...: cargo's install records. A key is "name version (source)",
# optionally followed by "|<JSON options>" for a crate installed with options.
installs() {
    local key options records=""
    for key in "$@"; do
        options='{"version_req": null, "features": [], "all_features": false, "no_default_features": false, "profile": "release"}'
        [[ "$key" == *"|"* ]] && options="${key#*|}" key="${key%%|*}"
        records="$records${records:+, }\"$key\": $options"
    done
    printf '{"installs": {%s}}\n' "$records" > "$tmp/home/.cargo/.crates2.json"
}
crates_io="(registry+https://github.com/rust-lang/crates.io-index)"
installs "du-dust 1.2.6 $crates_io" "just 1.58.0 $crates_io" "just-lsp 0.8.0 $crates_io" \
    "ripgrep 14.1.0 $crates_io|{\"version_req\": null, \"features\": [\"pcre2\"], \"profile\": \"release\"}" \
    "bat 0.24.0 (sparse+https://index.crates.io/)|{\"version_req\": \"^0.24\", \"features\": []}" \
    "mytool 0.1.0 (git+https://github.com/me/mytool#abc123)"

cat > "$STUB/rustup-check" <<'EOF'
stable-x86_64-unknown-linux-gnu - Update available : 1.99.0 (07dca489a 2026-10-01) -> 1.100.0 (0ef1bc386 2026-11-09)
rustup - Update available : 1.29.2 -> 1.29.3
EOF
component cargo
assert_eq "a Rust upgrade succeeds" "$rc" "0"
assert_contains "an available toolchain update runs rustup update" "$calls" "rustup update"
assert_contains "a toolchain update names old -> new" "$records" \
    "$(updated "stable-x86_64-unknown-linux-gnu 1.99.0 -> 1.100.0")"
assert_contains "a rustup self-update names old -> new" "$records" "$(updated "rustup 1.29.2 -> 1.29.3")"
# Given several crates, cargo refreshes the sparse index for the first only.
for crate in just du-dust just-lsp; do
    assert_eq "$crate gets a cargo install of its own" \
        "$(ran "rustup run stable cargo install $crate")" "ran"
done
assert_contains "an upgraded crate names old -> new" "$records" "$(updated "just v1.58.0 -> v1.59.0")"
assert_eq "a crate outside the list is upgraded with the features it was installed with" \
    "$(ran "rustup run stable cargo install ripgrep --features pcre2")" "ran"
assert_eq "a pinned crate stays within its version requirement" \
    "$(ran "rustup run stable cargo install bat --version ^0.24")" "ran"
assert_not_contains "a git install is not reinstalled from crates.io" "$calls" "cargo install mytool"

echo "stable-x86_64-unknown-linux-gnu - update available: 1.100.0 (0ef1bc386 2026-11-09) -> 1.101.0 (1a2b3c4d5 2026-11-20)" \
    > "$STUB/rustup-check"
component cargo
assert_contains "rustup 1.29's lowercase check still triggers the update" "$records" \
    "$(updated "stable-x86_64-unknown-linux-gnu 1.100.0 -> 1.101.0")"

echo "stable-x86_64-unknown-linux-gnu - up to date: 1.100.0 (0ef1bc386 2026-11-09)" \
    > "$STUB/rustup-check"
component cargo
assert_not_contains "a current toolchain runs no rustup update" "$calls" "rustup update"
assert_eq "current Rust and crates read already current" "$records" ""

: > "$STUB/rustup-check"
touch "$STUB/rustup-check-fails"
component cargo
assert_eq "a failed rustup check fails the component" "$rc" "1"
assert_contains "a failed rustup check says so" "$records" \
    "$(errored "Could not check Rust toolchains for updates")"
rm "$STUB/rustup-check-fails"

touch "$STUB/cargo-fails"
component cargo
assert_eq "a failed cargo install fails the component" "$rc" "1"
assert_contains "a failed cargo install says so" "$records" "$(errored "Failed to upgrade: du-dust")"
rm "$STUB/cargo-fails"

# A missing crate from the list installs as it stands.
installs "du-dust 1.2.6 $crates_io" "just 1.59.0 $crates_io"
rm "$tmp/home/.cargo/bin/just-lsp"
component cargo
assert_eq "a missing crate from the list is installed" \
    "$(ran "rustup run stable cargo install just-lsp")" "ran"
printf '#!/bin/bash\n' > "$tmp/home/.cargo/bin/just-lsp"
chmod +x "$tmp/home/.cargo/bin/just-lsp"

# A just from another manager is left to it.
installs "du-dust 1.2.6 $crates_io" "just-lsp 0.8.0 $crates_io"
printf '#!/bin/bash\n' > "$tmp/bin/just"
chmod +x "$tmp/bin/just"
rm "$tmp/home/.cargo/bin/just"
printf 'du-dust v1.2.6:\n    dust\njust-lsp v0.8.0:\n    just-lsp\n' > "$STUB/crates"
component cargo
assert_eq "a binary another manager installed is not handed to cargo" \
    "$(ran "rustup run stable cargo install just")" "did not run"
assert_eq "the crates cargo owns still go through cargo" \
    "$(ran "rustup run stable cargo install du-dust")" "ran"
rm "$tmp/bin/just"

# --- gh: installed extensions ------------------------------------------------

stub gh <<'EOF'
case "$*" in
    --version) echo "gh version 2.45.0 (2026-03-17)" ;;
    "extension list")
        [[ -e "$STUB/gh-logged-out" ]] && { echo "To get started with GitHub CLI, please run: gh auth login" >&2; exit 4; }
        cat "$STUB/gh-extensions"
        ;;
    "extension upgrade --all")
        [[ -e "$STUB/gh-fails" ]] && exit 1
        [[ -e "$STUB/gh-next" ]] && mv "$STUB/gh-next" "$STUB/gh-extensions"
        exit 0
        ;;
    "extension install "*) printf 'gh stack\tgithub/gh-stack\tv0.4.0\n' >> "$STUB/gh-extensions" ;;
esac
EOF
printf 'gh stack\tgithub/gh-stack\tv0.3.0\n' > "$STUB/gh-extensions"
printf 'gh stack\tgithub/gh-stack\tv0.4.0\n' > "$STUB/gh-next"
component gh
assert_eq "a gh extension upgrade succeeds" "$rc" "0"
assert_contains "an extension upgrade names old -> new" "$records" \
    "$(updated "github/gh-stack v0.3.0 -> v0.4.0")"
assert_not_contains "an installed extension is not reinstalled" "$calls" "extension install"

component gh
assert_eq "current extensions read already current" "$records" ""

touch "$STUB/gh-fails"
component gh
assert_eq "a failed extension upgrade fails the component" "$rc" "1"
assert_contains "a failed extension upgrade says so" "$records" \
    "$(errored "Failed to upgrade GitHub CLI extensions")"
rm "$STUB/gh-fails"

: > "$STUB/gh-extensions"
component gh
assert_not_contains "no extensions runs no upgrade" "$calls" "extension upgrade"
assert_contains "a missing gh stack is installed" "$calls" "extension install github/gh-stack"

touch "$STUB/gh-logged-out"
component gh
assert_eq "a logged-out gh does not fail the step" "$rc" "0"
assert_contains "a logged-out gh says how to log in" "$records" \
    "$(warned "Could not list GitHub CLI extensions; run 'gh auth login', then re-run")"
assert_not_contains "a logged-out gh does not try to reinstall an extension" "$calls" "extension install"
rm "$STUB/gh-logged-out"

# --- End to end: the status line --------------------------------------------

cat > "$tmp/bin/uname" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == -s ]]; then
    echo Linux
    exit 0
fi
exec /usr/bin/uname "$@"
EOF
chmod +x "$tmp/bin/uname"
installer() {
    env -i HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" STUB="$STUB" DRAIN="$DRAIN" \
        XDG_STATE_HOME="$tmp/state" APT_UPDATE_STAMP="$stamp" \
        INSTALLER_APT_PACKAGES_FILE="$STUB/apt_packages.txt" \
        bash "$ROOT/installers/installer.sh" "$@" </dev/null
}
printf 'Inst libssl3t64 [3.0.13-0ubuntu3.4] (3.0.13-0ubuntu3.5 Ubuntu:24.04/noble-updates [arm64])\n' \
    > "$STUB/apt-upgrades"
line="$(installer apt | grep -F "APT packages")"
assert_contains "an upgrade reads as updated" "$line" "updated"
assert_contains "the status line names old -> new" "$line" "libssl3t64 3.0.13-0ubuntu3.4 -> 3.0.13-0ubuntu3.5"

: > "$STUB/apt-upgrades"
line="$(installer apt | grep -F "APT packages")"
assert_contains "a run with nothing to upgrade reads already current" "$line" "already current"

test_result
