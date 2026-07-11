#!/bin/bash

# Streaming installer output filters (shared with tests).

# Strip ANSI only; keep ✓/✗ from child installers.
normalize_output_line() {
    local line="$1"
    # shellcheck disable=SC2001
    line="$(printf '%s' "$line" | sed $'s/\033\\[[0-9;]*[[:alpha:]]//g')"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    printf '%s' "$line"
}

# 0 = drop, 1 = detail line, 2 = ephemeral status.
classify_output_line() {
    local line="$1"
    local line_lc="${line,,}"

    # print_header rules wrap past terminal width; showing them as status leaves
    # orphan dashed rows that look like repeated "info: ---..." spam.
    if [[ "$line" =~ ^[-_=─—]{4,}$ ]] || [[ "$line" =~ ^[[:space:][:punct:]]+$ ]]; then
        return 0
    fi

    case "$line_lc" in
        ""| \
        *"all packages are up to date"*| \
        *"all packages installed."*|*"all packages installed"*| \
        *"apt installation complete."*|*"flatpak installation complete."*|*"snap installation complete."*| \
        *"lazyvim installation complete."*|*"cargo package installation complete."*| \
        *"syncing claude config"*|*"syncing codex config"*| \
        *"syncing nvim config"*|*"syncing tmux config"*|*"done."*| \
        *"warning: apt does not have a stable cli interface"*| \
        *"reading package lists..."*|*"building dependency tree..."*| \
        *"reading state information..."*| \
        *"0 upgraded, 0 newly installed"*| \
        *"use 'sudo apt autoremove'"*| \
        *"the following packages were automatically installed"*| \
        *"is already the newest version"*| \
        homepage:* )
            return 0
            ;;
    esac

    if [[ "$line_lc" =~ [0-9]+% ]] || [[ "$line_lc" =~ bytes/s ]] || [[ "$line_lc" =~ installing\ [0-9]+/ ]]; then
        return 2
    fi

    if [[ "$line_lc" == *"✓"* || "$line_lc" == *"✗"* || "$line_lc" == *"⚠"* ]] \
        || [[ "$line_lc" == installing:* || "$line_lc" == *"installing "* ]] \
        || [[ "$line_lc" == skipping* || "$line_lc" == *"already installed"* ]] \
        || [[ "$line_lc" == *"successfully installed"* || "$line_lc" == *"failed to install"* ]] \
        || [[ "$line_lc" == *"error:"* || "$line_lc" == *"failed"* ]] \
        || [[ "$line_lc" == *"e: "* || "$line_lc" == *"unable to locate"* ]]; then
        return 1
    fi

    return 2
}
