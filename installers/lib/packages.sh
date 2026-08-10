#!/bin/bash

# Package-list installers for apt, snap, and flatpak. Sourced by common.sh.
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

apt_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

apt_install() {
    run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
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
    local -a package_lines=() ppas=() missing=()

    require_file "$packages_file"

    if dpkg_is_interrupted; then
        print_error "dpkg has an unfinished transaction; apt cannot install anything."
        print_error "Run 'sudo dpkg --configure -a', then re-run the installer."
        return 1
    fi

    echo "Installing apt packages..."
    # Load once so later processing cannot re-read a mutated file mid-install.
    mapfile -t package_lines < "$packages_file"

    for line in "${package_lines[@]}"; do
        parse_package_line "$line" || continue
        [[ -n "$ppa" ]] && ppas+=("ppa:$ppa")
    done

    if ((${#ppas[@]})); then
        echo "Adding ${#ppas[@]} PPAs..."
        for ppa in "${ppas[@]}"; do
            echo "Adding PPA: $ppa"
            run_as_root add-apt-repository -y "$ppa"
        done
        echo "Updating package lists after adding PPAs..."
        run_as_root apt-get update
    fi

    for line in "${package_lines[@]}"; do
        parse_package_line "$line" || continue

        if [[ "$optional" == true ]] && ! install_optionals_env; then
            echo "Skipping optional package: $package"
        elif apt_installed "$package"; then
            print_success "Already installed: $package"
        else
            missing+=("$package")
        fi
    done

    if ! install_batch "apt packages" apt_install apt_installed "${missing[@]}"; then
        print_error "APT installation completed with failures."
        return 1
    fi
    echo "APT installation complete."
}

snap_installed() {
    snap list "$1" >/dev/null 2>&1
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

flatpak_installed() {
    flatpak info "$1" >/dev/null 2>&1
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
        if ! run_as_root apt-get install -y flatpak; then
            print_error "Failed to install flatpak"
            return 1
        fi
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
