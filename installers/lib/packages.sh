#!/bin/bash

# Package-list installers and whole-manager upgrades for apt, snap, flatpak,
# and Homebrew. Sourced by common.sh; the Homebrew ones also run under macOS's
# bash 3.2.
#
# Each manifest is a text file of `package # description` lines. Blank lines
# and comments are ignored; per-manager extras are noted on their parser.

# Parse one apt manifest line. Optional entries start with "? "; a PPA is given
# as "package | ppa:user/repo". Sets the globals package, optional, and ppa.
# Returns 1 for blank and comment lines.
#
# shellcheck disable=SC2034  # package/optional/ppa are outputs for callers
parse_package_line() {
    local line="$1"
    optional=false
    package=""
    ppa=""

    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && return 1

    if [[ "$line" =~ ^\?[[:space:]]+(.*) ]]; then
        optional=true
        line="${BASH_REMATCH[1]}"
    fi

    if [[ "$line" =~ ^([^|#]+)\|[[:space:]]*ppa:([^#]+) ]]; then
        package=$(echo "${BASH_REMATCH[1]}" | xargs)
        ppa=$(echo "${BASH_REMATCH[2]}" | xargs)
    else
        package=$(echo "$line" | awk '{print $1}')
    fi

    [[ -n "$package" ]]
}

# Strip a trailing comment and surrounding whitespace from a manifest line.
package_entry() {
    echo "$1" | cut -d'#' -f1 | xargs
}

install_optionals_env() {
    case "${INSTALLER_INSTALL_OPTIONALS:-}" in
        1|true|True|TRUE|yes|Yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

# Print each named package dpkg does not have installed. The second status
# letter is the installed state, so held ("hi") packages count.
missing_apt_packages() {
    local status real provided package
    status="$(dpkg-query -W -f='${db:Status-Abbrev}\t${Package}\t${Provides}\n' 2>/dev/null)"
    real=$'\n'"$(awk -F'\t' '$1 ~ /^.i/ { print $2 }' <<<"$status")"$'\n'
    provided=$'\n'"$(awk -F'\t' '$1 ~ /^.i/ {
        n = split($3, names, /, */)
        for (i = 1; i <= n; i++) { sub(/ .*/, "", names[i]); print names[i] }
    }' <<<"$status")"$'\n'

    for package in "$@"; do
        [[ "$real" == *$'\n'"$package"$'\n'* ]] && continue
        # An installed provider satisfies a purely virtual name, and apt has
        # nothing to install for it: 24.04 renamed libfuse2 to libfuse2t64,
        # which provides it, and asking dpkg for the old name alone sent it back
        # to apt on every run. A real package of that name still installs.
        [[ "$provided" == *$'\n'"$package"$'\n'* &&
            "$(LC_ALL=C apt-cache policy "$package" 2>/dev/null)" == *"Candidate: (none)"* ]] &&
            continue
        echo "$package"
    done
}

apt_installed() {
    [[ -z "$(missing_apt_packages "$1")" ]]
}

# Ubuntu's update-notifier hook touches this after every successful
# `apt-get update`. apt_refresh touches it too, for images without that
# package.
APT_UPDATE_STAMP="${APT_UPDATE_STAMP:-/var/lib/apt/periodic/update-success-stamp}"

# apt-get update exits 0 when a source fails to fetch, and the stamp would then
# vouch for a stale index for an hour. --error-on needs apt 2.1.16 (22.04+).
apt_refresh() {
    run_as_root apt-get update --error-on=any && run_as_root touch "$APT_UPDATE_STAMP"
}

# Nothing keeps the index fresh on its own: apt-daily refreshes only when
# unattended-upgrades sets APT::Periodic::Update-Package-Lists, and hosts
# without it (DGX OS among them) can sit on a weeks-old index. So an install or
# upgrade check refreshes it under the hourly rule, about once per run.
apt_index_fresh() {
    refreshed_within_hour "$APT_UPDATE_STAMP"
}

# Steps run with stdin closed. sudo drops the installer's environment, so pass
# the unattended settings through it: debconf takes its defaults, needrestart
# restarts services instead of asking, and dpkg keeps a locally edited conffile
# instead of prompting for it.
apt_get() {
    run_as_root env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -y \
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"
}

apt_install() {
    apt_index_fresh || apt_refresh || return 1
    apt_get install "$@"
}

# apt refuses every transaction while a previous dpkg run is unfinished, so one
# interrupted install (a Ctrl-C during an initramfs rebuild will do it) becomes
# a cascade of unrelated component failures. Name the one-line fix instead.
#
# Collect before matching: `grep -q` exits on the first hit, and under pipefail
# the SIGPIPE it deals dpkg-query would read back as "no match".
dpkg_is_interrupted() {
    local statuses
    statuses="$(dpkg-query -W -f='${Status}\n' 2>/dev/null)" || return 1
    grep -qE 'half-configured|half-installed|unpacked' <<<"$statuses"
}

install_apt_package_list() {
    local packages_file="$1"
    local line package optional ppa
    local -a package_lines=() wanted=() missing=() ppas=()

    require_file "$packages_file"

    if dpkg_is_interrupted; then
        print_error "dpkg has an unfinished transaction; apt cannot install anything."
        print_error "Run 'sudo dpkg --configure -a', then re-run the installer."
        return 1
    fi

    # Load once so later processing cannot re-read a mutated file mid-install.
    mapfile -t package_lines < "$packages_file"

    for line in "${package_lines[@]}"; do
        parse_package_line "$line" || continue
        if [[ "$optional" == true ]] && ! install_optionals_env; then
            echo "Skipping optional package: $package"
        else
            wanted+=("$package")
        fi
    done

    mapfile -t missing < <(missing_apt_packages "${wanted[@]}")
    echo "Already installed: $(( ${#wanted[@]} - ${#missing[@]} )) of ${#wanted[@]} apt packages"
    ((${#missing[@]})) || return 0

    # A PPA only matters for a package still to install, and adding one costs
    # a network round trip.
    for line in "${package_lines[@]}"; do
        parse_package_line "$line" || continue
        [[ -n "$ppa" ]] && contains_item "$package" "${missing[@]}" && ppas+=("ppa:$ppa")
    done
    if ((${#ppas[@]})); then
        for ppa in "${ppas[@]}"; do
            echo "Adding PPA: $ppa"
            run_as_root add-apt-repository -y "$ppa"
        done
        apt_refresh
    fi

    if ! install_batch "apt packages" apt_install apt_installed "${missing[@]}"; then
        print_error "APT installation completed with failures."
        return 1
    fi
    echo "APT installation complete."
}

# "name installed -> candidate" per package `apt-get upgrade` would upgrade,
# from "Inst name [installed] (candidate suite [arch])"; any other Inst line
# still names one. Simulating needs no root.
apt_upgrades_due() {
    apt-get -s upgrade | sed -nE -e 's/^Inst ([^ ]+) \[([^]]+)\] \(([^ ]+) .*/\1 \2 -> \3/p' \
        -e t -e 's/^Inst ([^ ]+).*/\1/p'
}

apt_removals_due() {
    apt-get -s autoremove | sed -nE 's/^Remv ([^ ]+).*/\1 removed/p'
}

# `apt-get upgrade` over every installed package, then autoremove, so a current
# machine never reaches sudo. Like `apt-get upgrade` itself, this leaves
# held-back packages, the ones whose upgrade needs a new package or a removal,
# to a full-upgrade by hand.
upgrade_apt_packages() {
    local due
    apt_index_fresh || apt_refresh || return 1

    if ! due="$(apt_upgrades_due)"; then
        print_error "Could not check APT packages for upgrades"
        return 1
    fi
    if [[ -n "$due" ]]; then
        if ! apt_get upgrade; then
            print_error "apt-get upgrade failed"
            return 1
        fi
        report_upgraded "$due" apt_upgrades_due
    fi

    if ! due="$(apt_removals_due)"; then
        print_error "Could not check for APT packages to autoremove"
        return 1
    fi
    [[ -n "$due" ]] || return 0
    if ! apt_get autoremove; then
        print_error "apt-get autoremove failed"
        return 1
    fi
    report_upgraded "$due" apt_removals_due
}

snap_installed() {
    snap list "$1" >/dev/null 2>&1
}

# Store queries filter by host architecture, so a snap published only for
# amd64 either returns no record on arm64 or reports `latest/stable: --`.
snap_available() {
    local info
    info="$(snap info "$1" 2>/dev/null)" || return 1
    grep -qE '^[[:space:]]*latest/stable:[[:space:]]+[^-[:space:]]' <<<"$info"
}

snap_install() {
    run_as_root snap install "$@"
}

snap_install_classic() {
    run_as_root snap install --classic "$@"
}

# Manifest extra: "--classic" requests a classically confined snap.
install_snap_packages() {
    local packages_file="$1"
    local line entry package
    local -a installed=() regular=() classic=()
    local had_failure=false

    require_file "$packages_file"

    echo "Installing snap packages..."
    mapfile -t installed < <(snap list 2>/dev/null | awk 'NR > 1 { print $1 }')

    while IFS= read -r line; do
        entry="$(package_entry "$line")"
        [[ -z "$entry" ]] && continue

        package="${entry/--classic/}"
        package="$(echo "$package" | xargs)"

        if contains_item "$package" "${installed[@]}"; then
            print_success "Already installed: $package"
        elif ! snap_available "$package"; then
            print_skipped "$package (no stable snap for $(uname -m))"
        elif [[ "$entry" == *"--classic"* ]]; then
            classic+=("$package")
        else
            regular+=("$package")
        fi
    done < <(read_package_list "$packages_file")

    install_batch "snaps" snap_install snap_installed "${regular[@]}" || had_failure=true
    # Classic confinement cannot share an install transaction with other snaps.
    install_each "classic snaps" snap_install_classic snap_installed "${classic[@]}" ||
        had_failure=true

    if [[ "$had_failure" == true ]]; then
        print_error "Snap installation completed with failures."
        return 1
    fi
    echo "Snap installation complete."
}

# "name installed -> new" per snap due a refresh. A new revision can keep its
# version, which leaves "name version". Asking the store needs no root.
snaps_due() {
    local due
    due="$(snap refresh --list)" || return 1
    awk 'FILENAME == ARGV[1] { if (FNR > 1) old[$1] = $2; next }
        FNR > 1 { print $1, ($1 in old && old[$1] != $2 ? old[$1] " -> " $2 : $2) }' \
        <(snap list) - <<<"$due"
}

# Every installed snap, as `snap refresh` would.
upgrade_snaps() {
    local due
    if ! due="$(snaps_due)"; then
        print_error "Could not check snaps for refreshes"
        return 1
    fi
    [[ -n "$due" ]] || return 0
    if ! run_as_root snap refresh; then
        print_error "snap refresh failed"
        return 1
    fi
    report_upgraded "$due" snaps_due
}

flatpak_installed() {
    flatpak info "$1" >/dev/null 2>&1
}

flatpak_available() {
    flatpak remote-info --user flathub "$1" >/dev/null 2>&1
}

flatpak_install() {
    flatpak install --user -y flathub "$@"
}

install_flatpak_packages() {
    local packages_file="$1"
    local line app_id
    local -a installed=() missing=()

    require_file "$packages_file"

    if ! is_installed "flatpak"; then
        echo "Flatpak not found. Installing flatpak..."
        if ! apt_install flatpak; then
            print_error "Failed to install flatpak"
            return 1
        fi
        print_installed flatpak
    fi

    # User-scope installs avoid polkit. System installs still count as present.
    flatpak remote-add --user --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo

    echo "Installing flatpak packages (user scope)..."
    mapfile -t installed < <(flatpak list --app --columns=application 2>/dev/null)

    while IFS= read -r line; do
        app_id="$(package_entry "$line")"
        [[ -z "$app_id" ]] && continue

        if contains_item "$app_id" "${installed[@]}"; then
            print_success "Already installed: $app_id"
        elif ! flatpak_available "$app_id"; then
            print_skipped "$app_id (no flathub build for $(uname -m))"
        else
            missing+=("$app_id")
        fi
    done < <(read_package_list "$packages_file")

    if ! install_batch "flatpaks" flatpak_install flatpak_installed "${missing[@]}"; then
        print_error "Flatpak installation completed with failures."
        return 1
    fi
    echo "Flatpak installation complete."
}

# "app version" per Flatpak due an update in one scope; many apps publish no
# version.
flatpaks_due() {
    flatpak remote-ls --updates "--$1" --columns=application,version |
        awk '{ print $1 (NF > 1 ? " " $2 : "") }'
}

# Every installed Flatpak, in both scopes. This installer installs into the
# user scope, which needs no root; updating the system scope does.
upgrade_flatpaks() {
    local scope due had_failure=false
    for scope in user system; do
        if ! due="$(flatpaks_due "$scope")"; then
            print_error "Could not check $scope Flatpaks for updates"
            had_failure=true
            continue
        fi
        [[ -n "$due" ]] || continue
        if [[ "$scope" == system ]]; then
            run_as_root flatpak update --system -y --noninteractive
        else
            flatpak update --user -y --noninteractive
        fi || {
            print_error "flatpak update --$scope failed"
            had_failure=true
            continue
        }
        report_upgraded "$due" flatpaks_due "$scope"
    done
    [[ "$had_failure" == false ]]
}

brew_install_formula() { "$BREW" install "$@"; }
brew_install_cask() { "$BREW" install --cask "$@"; }
brew_formula_installed() { "$BREW" list --formula "$1" >/dev/null 2>&1; }
brew_cask_installed() { "$BREW" list --cask "$1" >/dev/null 2>&1; }

# install_brew_package_list <brew> <manifest>
# Manifest extra: "--cask" installs a cask rather than a formula. What is
# installed is listed once up front: `brew list --formula <name>` leaves brew's
# bash fast path for Ruby and costs ~1.5s a package.
install_brew_package_list() {
    local BREW="$1" packages_file="$2"
    local line entry package installed_formulae installed_casks had_failure=false
    local -a formulae=() casks=()

    require_file "$packages_file"
    installed_formulae=$'\n'"$("$BREW" list --formula -1 2>/dev/null)"$'\n'
    installed_casks=$'\n'"$("$BREW" list --cask -1 2>/dev/null)"$'\n'

    while IFS= read -r line; do
        entry="$(package_entry "$line")"
        [[ -z "$entry" ]] && continue
        package="$(echo "${entry/--cask/}" | xargs)"

        if [[ "$entry" == *"--cask"* ]]; then
            if [[ "$installed_casks" == *$'\n'"$package"$'\n'* ]]; then
                print_success "Already installed: $package"
            else
                casks+=("$package")
            fi
        elif [[ "$installed_formulae" == *$'\n'"$package"$'\n'* ]]; then
            print_success "Already installed: $package"
        else
            formulae+=("$package")
        fi
    done < <(read_package_list "$packages_file")

    # bash 3.2 + set -u treats "${arr[@]}" as unbound when arr is empty.
    if ((${#formulae[@]})); then
        install_batch "formulae" brew_install_formula brew_formula_installed \
            "${formulae[@]}" || had_failure=true
    fi
    if ((${#casks[@]})); then
        install_batch "casks" brew_install_cask brew_cask_installed \
            "${casks[@]}" || had_failure=true
    fi

    if [[ "$had_failure" == true ]]; then
        print_error "Homebrew package installation completed with failures."
        return 1
    fi
}

# "name installed -> latest" per formula or cask `brew upgrade` would upgrade,
# from "name (installed) < latest", or != for a cask. A pinned formula is
# listed, but brew upgrade skips it. A nonzero exit that still lists packages
# is brew reporting them.
brew_due() {
    local outdated
    outdated="$("$BREW" outdated --verbose)" || [[ -n "$outdated" ]] || return 1
    sed -E -e '/\[pinned at/d' -e 's/^([^ ]+) \((.*)\) (<|!=) (.*)$/\1 \2 -> \4/' <<<"$outdated"
}

# Every outdated formula and cask, as `brew upgrade` would. `brew update` is
# the index refresh, under the hourly rule; Homebrew stamps its own fetches in
# the repository's FETCH_HEAD and reads it the same way for auto-update.
upgrade_brew_packages() {
    local BREW="$1" due
    if ! refreshed_within_hour "$("$BREW" --repository)/.git/FETCH_HEAD" &&
        ! "$BREW" update; then
        print_error "brew update failed"
        return 1
    fi

    if ! due="$(brew_due)"; then
        print_error "Could not check Homebrew packages for upgrades"
        return 1
    fi
    [[ -n "$due" ]] || return 0
    if ! HOMEBREW_NO_AUTO_UPDATE=1 "$BREW" upgrade; then
        print_error "brew upgrade failed"
        return 1
    fi
    report_upgraded "$due" brew_due
    "$BREW" cleanup || print_warning "brew cleanup failed"
}
