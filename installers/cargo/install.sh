#!/bin/bash
set -uo pipefail

# Rustup, stable Rust, and the crates in cargo_packages.txt.

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/cargo_packages.txt"
RUSTUP_INSTALL_URL="https://sh.rustup.rs"
CARGO_BIN_DIR="$HOME/.cargo/bin"
CARGO_PATH_LINE="export PATH=\"\$HOME/.cargo/bin:\$PATH\""
RUSTUP_BIN="$CARGO_BIN_DIR/rustup"
BUILD_DEPS=(build-essential curl)
RUSTUP_PATH=""

require_file "$PACKAGES_FILE"

find_rustup() {
    local path

    if path="$(command -v rustup 2>/dev/null)" && [[ -x "$path" ]]; then
        echo "$path"
        return 0
    fi

    if [[ -x "$RUSTUP_BIN" ]]; then
        echo "$RUSTUP_BIN"
        return 0
    fi

    return 1
}

configure_cargo_path() {
    configure_shell_rcs ".cargo/bin" "# Cargo" "$CARGO_PATH_LINE"

    case ":$PATH:" in
        *":$CARGO_BIN_DIR:"*) ;;
        *) export PATH="$CARGO_BIN_DIR:$PATH" ;;
    esac
}

install_build_deps() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "Installing Rust build dependencies..."
        if ! apt_install "${BUILD_DEPS[@]}"; then
            print_error "Failed to install Rust build dependencies"
            return 1
        fi
    elif ! command -v curl >/dev/null 2>&1; then
        print_error "curl is required to install Rustup"
        return 1
    fi
}

install_rustup() {
    install_build_deps || return 1

    echo "Installing Rustup..."
    if ! curl --proto '=https' --tlsv1.2 -sSf "$RUSTUP_INSTALL_URL" | sh -s -- -y --profile minimal --no-modify-path; then
        print_error "Failed to install Rustup"
        return 1
    fi
}

stable_rustc_version() {
    "$RUSTUP_PATH" run stable rustc --version 2>/dev/null | last_version
}

# "name old -> new" per toolchain, and rustup itself, that `rustup check` finds
# an update for without downloading it. Its lines read
# "<name> - Update available : <old> (<hash> <date>) -> <new> (...)"; rustup
# 1.29 lowercased the phrase. A failure lists nothing and exits nonzero.
rust_due() {
    local check rc=0
    check="$("$RUSTUP_PATH" check)" || rc=$?
    check="$(grep -i 'update available' <<<"$check" |
        sed -E 's/ - [Uu]pdate available ?: / /; s/ \([^)]*\)//g')"
    [[ -n "$check" ]] || return "$rc"
    printf '%s\n' "$check"
}

# `rustup update` updates every toolchain and rustup itself.
update_rust() {
    local due
    if ! due="$(rust_due)"; then
        print_error "Could not check Rust toolchains for updates"
        return 1
    fi
    [[ -n "$due" ]] || return 0
    if ! "$RUSTUP_PATH" update; then
        print_error "rustup update failed"
        return 1
    fi
    report_upgraded "$due" rust_due
}

ensure_rust_toolchain() {
    if ! RUSTUP_PATH="$(find_rustup)"; then
        install_rustup || return 1
        RUSTUP_PATH="$RUSTUP_BIN"
        print_installed "rustup"
    fi
    configure_cargo_path

    if [[ -n "$(stable_rustc_version)" ]]; then
        update_rust
        return
    fi
    if ! "$RUSTUP_PATH" toolchain install stable --profile minimal; then
        print_error "Failed to install Rust stable toolchain"
        return 1
    fi
    print_installed "rustc $(stable_rustc_version)"
}

# Parse "crate" or "crate:bin" from a package-list entry (comment already stripped).
# Sets globals: crate, bin.
parse_cargo_entry() {
    local entry="$1"
    crate=""
    bin=""

    if [[ "$entry" == *:* ]]; then
        crate="${entry%%:*}"
        bin="${entry#*:}"
    else
        crate="$entry"
        bin="$entry"
    fi

    [[ -n "$crate" && -n "$bin" ]]
}

cargo_binary_installed() {
    local bin="$1"

    is_installed "$bin" || [[ -x "$CARGO_BIN_DIR/$bin" ]]
}

# "crate version" for each crate cargo installed. `cargo install --list` reads
# "du-dust v1.2.6:" with the binaries indented below.
cargo_crate_versions() {
    "$RUSTUP_PATH" run stable cargo install --list | awk '/^[^ ]/ { sub(/:$/, ""); print $1, $2 }'
}

# The `cargo install` arguments, tab-separated, that reproduce each crate
# cargo installed from crates.io: run with other features or a dropped
# --version, it would reinstall the crate that way. git and path installs are
# left out, since reinstalling from crates.io would change their source.
registry_crate_installs() {
    python3 -I - "$HOME/.cargo/.crates2.json" <<'PY'
import json, sys
try:
    installs = json.load(open(sys.argv[1]))["installs"]
except FileNotFoundError:
    sys.exit()
for key, spec in installs.items():
    name, _, source = key.split(" ", 2)
    if "crates.io-index" not in source and "index.crates.io" not in source:
        continue
    args = [name]
    if spec.get("version_req"):
        args += ["--version", spec["version_req"]]
    if spec.get("features"):
        args += ["--features", ",".join(spec["features"])]
    if spec.get("all_features"):
        args.append("--all-features")
    if spec.get("no_default_features"):
        args.append("--no-default-features")
    if spec.get("profile", "release") != "release":
        args += ["--profile", spec["profile"]]
    print("\t".join(args))
PY
}

ensure_rust_toolchain || exit 1

if ! installed_crates="$(cargo_crate_versions)" || ! upgrades="$(registry_crate_installs)"; then
    print_error "Could not list the crates cargo installed"
    exit 1
fi

# A missing crate from the list installs. One whose binary is present is either
# cargo's, and upgraded below, or another manager's, and left to it.
had_failure=false
while IFS= read -r line; do
    entry="$(package_entry "$line")"
    [[ -z "$entry" ]] && continue
    parse_cargo_entry "$entry" || continue
    cargo_binary_installed "$bin" && continue

    if ! "$RUSTUP_PATH" run stable cargo install "$crate"; then
        print_error "Failed to install: $crate"
        had_failure=true
    elif ! cargo_binary_installed "$bin"; then
        print_error "cargo install $crate finished but binary '$bin' not found"
        had_failure=true
    fi
done < <(read_package_list "$PACKAGES_FILE")

# Every crate cargo installed from crates.io, the list's and the user's own.
# `cargo install` rebuilds only one with a newer release. One crate per call:
# given several, cargo refreshes the index only for the first, and the sparse
# crates.io index is per crate, so the rest were judged against a stale cache
# and a newer release surfaced one crate per run.
while IFS=$'\t' read -ra install; do
    (( ${#install[@]} )) || continue
    if ! "$RUSTUP_PATH" run stable cargo install "${install[@]}"; then
        print_error "Failed to upgrade: ${install[0]}"
        had_failure=true
    fi
done <<<"$upgrades"
report_version_changes "$installed_crates" "$(cargo_crate_versions)"

[[ "$had_failure" == false ]]
