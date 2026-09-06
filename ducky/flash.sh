#!/usr/bin/env bash
# Encode a DuckyScript payload and write inject.bin onto a mounted Rubber Ducky.
# Identity (user, password, ssh key) is read from the environment or the TTY,
# injected in memory, and written only to the stick — never to the repo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD="${1:-${SCRIPT_DIR}/payloads/ubuntu-install.txt}"
MOUNT="${DUCKY_MOUNT:-}"
TMP=""

# Clack / Claude Code setup chrome. Wizard I/O is /dev/tty; stdout stays quiet.
UI_TTY=0
if [[ -t 0 && -r /dev/tty ]]; then
    UI_TTY=1
fi

if [[ "${UI_TTY}" -eq 1 ]] && command -v tput >/dev/null 2>&1; then
    ORANGE="$(tput setaf 208 2>/dev/null || tput setaf 3 2>/dev/null || true)"
    GREEN="$(tput setaf 2 2>/dev/null || true)"
    RED="$(tput setaf 1 2>/dev/null || true)"
    DIM="$(tput dim 2>/dev/null || true)"
    BOLD="$(tput bold 2>/dev/null || true)"
    NC="$(tput sgr0 2>/dev/null || true)"
else
    ORANGE="" GREEN="" RED="" DIM="" BOLD="" NC=""
fi

show_cursor() {
    { printf '\033[?25h' >/dev/tty; } 2>/dev/null || true
}

hide_cursor() {
    { printf '\033[?25l' >/dev/tty; } 2>/dev/null || true
}

die() {
    show_cursor
    if [[ "${UI_TTY}" -eq 1 ]]; then
        printf '%s▲%s  %s%s%s\n%s└%s\n' \
            "$RED" "$NC" "$RED" "$*" "$NC" "$DIM" "$NC" >/dev/tty
    fi
    echo "error: $*" >&2
    exit 1
}

cleanup() {
    show_cursor
    if [[ -n "${TMP}" && -d "${TMP}" ]]; then
        find "${TMP}" -type f -exec shred -u {} + 2>/dev/null || true
        rm -rf "${TMP}"
    fi
}
trap cleanup EXIT

ui_intro() {
    [[ "${UI_TTY}" -eq 1 ]] || return 0
    printf '\n%s┌%s  %s%s%s\n%s│%s\n' \
        "$ORANGE" "$NC" "$BOLD" "$1" "$NC" "$DIM" "$NC" >/dev/tty
}

ui_outro() {
    [[ "${UI_TTY}" -eq 1 ]] || return 0
    printf '%s└%s  %s%s%s\n\n' "$GREEN" "$NC" "$GREEN" "$1" "$NC" >/dev/tty
}

ui_done() {
    [[ "${UI_TTY}" -eq 1 ]] || return 0
    printf '%s◇%s  %s\n%s│%s  %s%s%s\n%s│%s\n' \
        "$DIM" "$NC" "$1" \
        "$DIM" "$NC" "$DIM" "$2" "$NC" \
        "$DIM" "$NC" >/dev/tty
}

ui_spin() {
    [[ "${UI_TTY}" -eq 1 ]] || return 0
    printf '%s◆%s  %s\n%s│%s\n' "$ORANGE" "$NC" "$1" "$DIM" "$NC" >/dev/tty
}

ui_clear_lines() {
    local n="$1" i
    [[ "${UI_TTY}" -eq 1 ]] || return 0
    for ((i = 0; i < n; i++)); do
        printf '\033[1A\033[2K' >/dev/tty
    done
}

# After read's trailing newline, erase the live ◆ block (question + input).
ui_finish_input() {
    ui_clear_lines 3
    ui_done "$1" "$2"
}

display_path() {
    case "$1" in
        "${HOME}"/*) printf '%s/%s' '~' "${1#"${HOME}"/}" ;;
        *) printf '%s' "$1" ;;
    esac
}

find_mount() {
    local candidate
    for candidate in \
        "${DUCKY_MOUNT:-}" \
        /Volumes/DUCKY \
        /media/"${USER}"/DUCKY \
        /run/media/"${USER}"/DUCKY \
        /mnt/DUCKY; do
        [[ -n "${candidate}" && -d "${candidate}" ]] || continue
        if [[ -w "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 1
}

prompt_text() {
    local dest="$1" question="$2"
    if [[ -n "${!dest:-}" ]]; then
        ui_done "$question" "${!dest}"
        return 0
    fi
    [[ "${UI_TTY}" -eq 1 ]] || die "${dest} is unset; set it or run from a terminal"
    while true; do
        printf '%s◆%s  %s\n%s│%s  ' "$ORANGE" "$NC" "$question" "$DIM" "$NC" >/dev/tty
        IFS= read -r "${dest?}" </dev/tty
        if [[ -n "${!dest}" ]]; then
            ui_finish_input "$question" "${!dest}"
            return 0
        fi
        ui_clear_lines 2
    done
}

prompt_password() {
    local confirm=""
    if [[ -n "${DUCKY_PASSWORD:-}" ]]; then
        ui_done "Password" "••••••••"
        return 0
    fi
    [[ "${UI_TTY}" -eq 1 ]] || die "DUCKY_PASSWORD is unset; set it or run from a terminal"
    while true; do
        printf '%s◆%s  %s\n%s│%s  ' "$ORANGE" "$NC" "Password" "$DIM" "$NC" >/dev/tty
        IFS= read -rs DUCKY_PASSWORD </dev/tty
        printf '\n' >/dev/tty
        if [[ -z "${DUCKY_PASSWORD}" ]]; then
            ui_clear_lines 3
            continue
        fi
        ui_clear_lines 3
        printf '%s◆%s  %s\n%s│%s  ' "$ORANGE" "$NC" "Confirm password" "$DIM" "$NC" >/dev/tty
        IFS= read -rs confirm </dev/tty
        printf '\n' >/dev/tty
        if [[ "${DUCKY_PASSWORD}" == "${confirm}" ]]; then
            ui_clear_lines 3
            ui_done "Password" "••••••••"
            return 0
        fi
        ui_clear_lines 3
        printf '%s▲%s  %sPasswords do not match%s\n%s│%s\n' \
            "$RED" "$NC" "$RED" "$NC" "$DIM" "$NC" >/dev/tty
        sleep 1
        ui_clear_lines 2
    done
}

discover_pubkeys() {
    local f old
    old="$(shopt -p nullglob)"
    shopt -s nullglob
    for f in "${HOME}/.ssh/"*.pub; do
        [[ -f "$f" ]] && printf '%s\n' "$f"
    done
    eval "$old"
}

expand_pubkey_path() {
    local path="$1"
    path="${path#\"}"
    path="${path%\"}"
    path="${path#\'}"
    path="${path%\'}"
    # Quote every tilde: unquoted ~ in case/# patterns expands to $HOME.
    # shellcheck disable=SC2088
    case "$path" in
        '~/'*) path="${HOME}/${path#"~/"}" ;;
    esac
    printf '%s\n' "$path"
}

draw_key_menu() {
    local question="$1" hint="$2" idx="$3"
    shift 3
    local i=0 item
    printf '%s◆%s  %s\n%s│%s  %s%s%s\n' \
        "$ORANGE" "$NC" "$question" "$DIM" "$NC" "$DIM" "$hint" "$NC" >/dev/tty
    for item in "$@"; do
        if ((i == idx)); then
            printf '%s│%s  %s●%s  %s%s%s\n' \
                "$DIM" "$NC" "$ORANGE" "$NC" "$BOLD" "$item" "$NC" >/dev/tty
        else
            printf '%s│%s  %s○%s  %s%s%s\n' \
                "$DIM" "$NC" "$DIM" "$NC" "$DIM" "$item" "$NC" >/dev/tty
        fi
        i=$((i + 1))
    done
    printf '%s│%s\n' "$DIM" "$NC" >/dev/tty
}

# Arrow through discovered ~/.ssh/*.pub files, or type/paste a path.
# Sets DUCKY_PUBKEY_FILE. UI on /dev/tty.
pick_pubkey_path() {
    local -a items=() labels=()
    local line idx=0 key rest i n
    local paste_label="Paste a path…"
    local question="SSH public key"
    local hint="↑↓ to select  ·  type or paste a path  ·  enter"

    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            items+=("$line")
            labels+=("$(display_path "$line")")
        fi
    done <<EOF
$(discover_pubkeys)
EOF
    items+=("$paste_label")
    labels+=("$paste_label")
    n=${#items[@]}

    hide_cursor

    while true; do
        draw_key_menu "$question" "$hint" "$idx" "${labels[@]}"
        IFS= read -rsn1 key </dev/tty
        ui_clear_lines $((3 + n))

        if [[ "$key" == $'\x1b' ]]; then
            IFS= read -rsn1 rest </dev/tty
            IFS= read -rsn1 rest </dev/tty
            case "$rest" in
                A) if ((idx > 0)); then idx=$((idx - 1)); fi ;;
                B) if ((idx < n - 1)); then idx=$((idx + 1)); fi ;;
            esac
        elif [[ -z "$key" ]]; then
            show_cursor
            if [[ "${items[$idx]}" == "$paste_label" ]]; then
                printf '%s◆%s  %s\n%s│%s  ' \
                    "$ORANGE" "$NC" "$question" "$DIM" "$NC" >/dev/tty
                IFS= read -r line </dev/tty
                [[ -n "$line" ]] || return 1
                DUCKY_PUBKEY_FILE="$(expand_pubkey_path "$line")"
                ui_finish_input "$question" "$(display_path "${DUCKY_PUBKEY_FILE}")"
            else
                DUCKY_PUBKEY_FILE="${items[$idx]}"
                ui_done "$question" "$(display_path "${DUCKY_PUBKEY_FILE}")"
            fi
            return 0
        else
            show_cursor
            printf '%s◆%s  %s\n%s│%s  %s' \
                "$ORANGE" "$NC" "$question" "$DIM" "$NC" "$key" >/dev/tty
            IFS= read -r rest </dev/tty
            line="${key}${rest}"
            [[ -n "$line" ]] || return 1
            DUCKY_PUBKEY_FILE="$(expand_pubkey_path "$line")"
            ui_finish_input "$question" "$(display_path "${DUCKY_PUBKEY_FILE}")"
            return 0
        fi
    done
}

prompt_pubkey_file() {
    if [[ -n "${DUCKY_PUBKEY_FILE:-}" ]]; then
        DUCKY_PUBKEY_FILE="$(expand_pubkey_path "${DUCKY_PUBKEY_FILE}")"
        ui_done "SSH public key" "$(display_path "${DUCKY_PUBKEY_FILE}")"
        return 0
    fi
    [[ "${UI_TTY}" -eq 1 ]] || die "DUCKY_PUBKEY_FILE is unset; set it or run from a terminal"
    pick_pubkey_path || die "DUCKY_PUBKEY_FILE is empty"
    [[ -n "${DUCKY_PUBKEY_FILE}" ]] || die "DUCKY_PUBKEY_FILE is empty"
}

load_pubkey() {
    local line
    [[ -n "${DUCKY_PUBKEY_FILE:-}" ]] || die "DUCKY_PUBKEY_FILE is empty"
    [[ -f "${DUCKY_PUBKEY_FILE}" ]] || die "public key file not found: ${DUCKY_PUBKEY_FILE}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "${line}" && "${line}" != \#* ]] || continue
        DUCKY_SSH_PUBKEY="${line}"
        return 0
    done <"${DUCKY_PUBKEY_FILE}"
    die "no ssh public key found in ${DUCKY_PUBKEY_FILE}"
}

collect_identity() {
    ui_intro "linux-utils · USB Rubber Ducky"
    prompt_text DUCKY_USERNAME "Username"
    prompt_text DUCKY_FULLNAME "Full name"
    prompt_password
    prompt_pubkey_file
    load_pubkey
    export DUCKY_USERNAME DUCKY_FULLNAME DUCKY_PASSWORD DUCKY_SSH_PUBKEY
}

needs_identity() {
    grep -qx 'REM FLASH_INJECT_SECRETS' "${PAYLOAD}"
}

command -v python3 >/dev/null || die "python3 is required"
[[ -f "${PAYLOAD}" ]] || die "payload not found: ${PAYLOAD}"

if [[ -z "${MOUNT}" ]]; then
    MOUNT="$(find_mount)" || die "no mounted Ducky found (set DUCKY_MOUNT or plug in arming mode)"
fi
[[ -d "${MOUNT}" && -w "${MOUNT}" ]] || die "mount not writable: ${MOUNT}"

ENCODE_ARGS=()
if needs_identity; then
    collect_identity
    ENCODE_ARGS+=(--inject-identity)
else
    ui_intro "linux-utils · USB Rubber Ducky"
fi

ui_spin "Writing inject.bin"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ducky-flash.XXXXXX")"
chmod 700 "${TMP}"
if ((${#ENCODE_ARGS[@]})); then
    python3 "${SCRIPT_DIR}/encode.py" -i "${PAYLOAD}" -o "${TMP}/inject.bin" "${ENCODE_ARGS[@]}" >/dev/null
else
    python3 "${SCRIPT_DIR}/encode.py" -i "${PAYLOAD}" -o "${TMP}/inject.bin" >/dev/null
fi

# Only the compiled payload goes on the stick. A source copy would hold the
# password in plaintext on a FAT volume.
cp "${TMP}/inject.bin" "${MOUNT}/inject.bin"
if [[ -f "${MOUNT}/payload.txt" ]]; then
    rm -f "${MOUNT}/payload.txt"
fi
if command -v sync >/dev/null; then
    sync
fi

ui_clear_lines 2
ui_done "Payload" "$(display_path "${MOUNT}/inject.bin")"
ui_outro "Flashed"
