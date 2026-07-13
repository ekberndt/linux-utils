#!/bin/bash

# Master installer script
# Installs packages from all supported package managers

# Needs bash 4+ (associative arrays, ${var,,}); macOS ships 3.2, so re-exec under a newer bash.
if [[ -z "${BASH_VERSINFO:-}" || "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash bash; do
        candidate_path="$(command -v "$candidate" 2>/dev/null)" || continue
        # Escape $ so the candidate bash expands BASH_VERSINFO, not this shell.
        candidate_major="$("$candidate_path" -c "echo \${BASH_VERSINFO[0]}" 2>/dev/null)"
        if [[ "$candidate_major" =~ ^[0-9]+$ && "$candidate_major" -ge 4 ]]; then
            exec "$candidate_path" "$0" "$@"
        fi
    done
    echo "Error: this installer requires bash 4 or newer (found ${BASH_VERSION:-unknown})." >&2
    echo "On macOS, install a modern bash with: brew install bash" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/stream_filter.sh
source "$SCRIPT_DIR/lib/stream_filter.sh"

# --- Installer Registry ---
# Format: "directory_name|short_flag|long_flag|display_name"
# To add a new installer: create <dir>/install.sh and add one line here.
INSTALLERS=(
    "apt|a|apt|APT Packages"
    "docker|d|docker|Docker Engine (official Ubuntu repository)"
    "flatpak|f|flatpak|Flatpak Packages"
    "snap|s|snap|Snap Packages"
    "homebrew|H|homebrew|Homebrew (Linuxbrew package manager)"
    "uv|u|uv|uv (Python package manager)"
    "tailscale|t|tailscale|Tailscale (VPN/mesh networking)"
    "bazelisk|b|bazelisk|bazelisk (Bazel version manager)"
    "buildtools|B|buildtools|buildtools (buildifier, buildozer, unused-deps)"
    "gh|g|gh|GitHub CLI (from official repo)"
    "claude|c|claude|Claude Code CLI (Anthropic)"
    "codex|x|codex|Codex CLI (OpenAI, via npm)"
    "grok|k|grok|Grok Build CLI (xAI)"
    "ollama|o|ollama|Ollama (local LLM runtime)"
    "cargo|r|cargo|Cargo packages (via Rustup)"
    "zoxide|z|zoxide|zoxide (smarter cd, Bash init)"
    "openrgb|R|openrgb|OpenRGB (AppImage in ~/Applications + /usr/local/bin wrapper)"
    "lazyvim|l|lazyvim|LazyVim (Neovim + LazyVim starter)"
    "config|C|config|Config sync (Bash aliases, Claude, Codex, shared agent scripts/skills, Neovim, tmux)"
)

# Installers that need a fresh apt package index (update only, not full upgrade).
# Omitted installers (e.g. "config") skip the apt phase entirely.
NEEDS_APT_UPDATE=(apt docker flatpak snap homebrew uv tailscale bazelisk buildtools gh claude codex cargo lazyvim)

# --- Help ---
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    for entry in "${INSTALLERS[@]}"; do
        IFS='|' read -r _ short long display <<< "$entry"
        printf "  -%s, --%-12s Install %s\n" "$short" "$long" "$display"
    done
    echo "      --all         Install all package types"
    echo "      --optionals   Auto-install apt optional packages (otherwise skipped non-interactively)"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --all                    Install everything"
    echo "  $0 -a -f                    Install APT and Flatpak only"
    echo "  $0 --apt --snap             Install APT and Snap only"
}

contains_item() {
    local needle="$1"; shift
    local item
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

get_step_label() {
    local name="$1"
    local entry entry_name label
    for entry in "${INSTALLERS[@]}"; do
        IFS='|' read -r entry_name _ _ label <<< "$entry"
        if [[ "$entry_name" == "$name" ]]; then
            echo "$label"
            return
        fi
    done
    echo "$name"
}

# Parse CLI flags dynamically.
declare -A INSTALL_FLAGS
INSTALL_ALL=false
INSTALL_OPTIONALS=false

for entry in "${INSTALLERS[@]}"; do
    IFS='|' read -r name _ _ _ <<< "$entry"
    INSTALL_FLAGS["$name"]=false
done

while [[ $# -gt 0 ]]; do
    matched=false
    for entry in "${INSTALLERS[@]}"; do
        IFS='|' read -r name short long _ <<< "$entry"
        if [[ "$1" == "-$short" || "$1" == "--$long" ]]; then
            INSTALL_FLAGS["$name"]=true
            matched=true
            break
        fi
    done

    if [[ "$matched" == false ]]; then
        case "$1" in
            --all) INSTALL_ALL=true ;;
            --optionals) INSTALL_OPTIONALS=true ;;
            -h|--help) show_help; exit 0 ;;
            *) echo "Unknown option: $1"; echo "Use --help for usage information"; exit 1 ;;
        esac
    fi
    shift
done

if [[ "$INSTALL_OPTIONALS" == true ]]; then
    export INSTALLER_INSTALL_OPTIONALS=1
fi

any_selected=false
if [[ "$INSTALL_ALL" == true ]]; then
    any_selected=true
else
    for name in "${!INSTALL_FLAGS[@]}"; do
        if [[ "${INSTALL_FLAGS[$name]}" == true ]]; then
            any_selected=true
            break
        fi
    done
fi

if [[ "$any_selected" == false ]]; then
    echo "No installation options specified. Use --help for usage information."
    exit 1
fi

# --- Streaming installer UI (append-only; no full-screen redraw) ---

TTY_MODE=false
if [[ -t 1 && -t 2 ]]; then
    TTY_MODE=true
fi

declare -a STEP_ORDER=()
declare -A STEP_STATUS
declare -A STEP_LABEL
declare -A STEP_MESSAGE

HAD_FAILURE=false
RUNNING_STEP_PID=""
RUNNING_STEP_KEY=""
STEP_INDEX=0
UI_STATUS_ACTIVE=false
UI_TERM_COLS=80

add_step() {
    local key="$1"
    local label="$2"
    STEP_ORDER+=("$key")
    STEP_STATUS["$key"]="pending"
    STEP_LABEL["$key"]="$label"
    STEP_MESSAGE["$key"]=""
}

ui_term_cols() {
    local cols
    cols="$(tput cols 2>/dev/null || echo 80)"
    if [[ "$cols" =~ ^[0-9]+$ ]] && (( cols >= 40 )); then
        UI_TERM_COLS=$cols
    else
        UI_TERM_COLS=80
    fi
}

ui_clear_status() {
    if [[ "$TTY_MODE" == true && "$UI_STATUS_ACTIVE" == true ]]; then
        printf '\r\033[K'
        UI_STATUS_ACTIVE=false
    fi
}

# Live progress on one line (apt % / "Reading package lists…").
ui_set_status() {
    local text="$1"
    local max shown

    if [[ "$TTY_MODE" != true ]]; then
        return
    fi

    ui_term_cols
    max=$(( UI_TERM_COLS - 4 ))
    if (( max < 20 )); then
        max=20
    fi
    shown="${text//$'\t'/ }"
    if (( ${#shown} > max )); then
        shown="${shown:0:max}..."
    fi
    printf '\r\033[K  %s%s%s' "${BLUE}" "$shown" "${NC}"
    UI_STATUS_ACTIVE=true
}

ui_event() {
    ui_clear_status
    printf '  %s\n' "$1"
}

ui_start() {
    local total=${#STEP_ORDER[@]}
    local key queue_color

    print_header "Linux Utils Installer"
    printf '%s%d steps queued%s\n' "${BLUE}" "$total" "${NC}"
    queue_color="$(_term_style setaf 8)"
    for key in "${STEP_ORDER[@]}"; do
        printf '  %s· %s%s\n' "${queue_color}" "${STEP_LABEL[$key]}" "${NC}"
    done
}

ui_step_begin() {
    local key="$1"
    local label="${STEP_LABEL[$key]}"
    local total=${#STEP_ORDER[@]}

    STEP_INDEX=$((STEP_INDEX + 1))
    ui_clear_status
    printf '\n%s●%s %s%s%s  %s(%d/%d)%s\n' \
        "${BLUE}${BOLD}" "${NC}" \
        "${WHITE}${BOLD}" "$label" "${NC}" \
        "${BLUE}" "$STEP_INDEX" "$total" "${NC}"
}

ui_step_end() {
    local key="$1"
    local label="${STEP_LABEL[$key]}"

    ui_clear_status
    case "${STEP_STATUS[$key]}" in
        done)
            printf '  %s✓%s %s\n' "${GREEN}" "${NC}" "$label"
            ;;
        failed|missing)
            printf '  %s✗%s %s\n' "${RED}" "${NC}" "$label"
            ;;
    esac
}

ui_finish() {
    local status_type="$1"
    local text="$2"
    ui_clear_status
    printf '\n'
    if [[ "$status_type" == "error" ]]; then
        print_error "$text"
    else
        print_success "$text"
    fi
}

cleanup_terminal() {
    ui_clear_status
}

interrupt_installer() {
    local pid="$RUNNING_STEP_PID"
    local key="$RUNNING_STEP_KEY"

    if [[ -n "$pid" ]]; then
        kill -INT "$pid" 2>/dev/null || true
        kill -TERM "$pid" 2>/dev/null || true
    fi
    if [[ -n "$key" ]]; then
        STEP_STATUS["$key"]="failed"
        STEP_MESSAGE["$key"]="Interrupted by user"
        ui_step_end "$key"
    fi

    cleanup_terminal
    exit 130
}

run_step_with_args() {
    local key="$1"
    shift
    local fd pid status line kind plain

    if (( $# == 0 )); then
        return 1
    fi

    STEP_STATUS["$key"]="running"
    STEP_MESSAGE["$key"]=""
    RUNNING_STEP_KEY="$key"
    ui_step_begin "$key"

    exec {fd}< <(
        "$@" 2>&1
    )
    pid=$!
    RUNNING_STEP_PID="$pid"

    while IFS= read -r -u "$fd" line || [[ -n "$line" ]]; do
        if [[ "$line" == *$'\r'* ]]; then
            line="${line##*$'\r'}"
        fi
        plain="$(normalize_output_line "$line")"
        [[ -z "$plain" ]] && continue

        classify_output_line "$plain"
        kind=$?

        case "$kind" in
            0) continue ;;
            1)
                STEP_MESSAGE["$key"]="$plain"
                ui_event "$plain"
                ;;
            2)
                STEP_MESSAGE["$key"]="$plain"
                ui_set_status "$plain"
                ;;
        esac
    done

    exec {fd}<&-
    wait "$pid"
    status=$?
    RUNNING_STEP_PID=""
    RUNNING_STEP_KEY=""

    if [[ $status -eq 0 ]]; then
        STEP_STATUS["$key"]="done"
        if [[ -z "${STEP_MESSAGE[$key]}" ]]; then
            STEP_MESSAGE["$key"]="${STEP_LABEL[$key]} complete"
        fi
    else
        STEP_STATUS["$key"]="failed"
        HAD_FAILURE=true
        if [[ -z "${STEP_MESSAGE[$key]}" ]]; then
            STEP_MESSAGE["$key"]="${STEP_LABEL[$key]} failed (exit $status)"
        fi
    fi

    ui_step_end "$key"
    return $status
}

run_step_script() {
    local key="$1"
    local script="$2"

    if [[ ! -f "$script" ]]; then
        STEP_STATUS["$key"]="missing"
        HAD_FAILURE=true
        STEP_MESSAGE["$key"]="${STEP_LABEL[$key]} installer not found at $script"
        ui_step_begin "$key"
        ui_event "${STEP_MESSAGE[$key]}"
        ui_step_end "$key"
        return 1
    fi

    if [[ "$script" == "$SCRIPT_DIR/config/install.sh" ]]; then
        run_step_with_args "$key" env INSTALLER_QUIET_CONFIG=1 bash "$script"
    else
        run_step_with_args "$key" bash "$script"
    fi
}

run_step_shell() {
    local key="$1"
    local command="$2"
    run_step_with_args "$key" bash -lc "$command"
}

trap cleanup_terminal EXIT
trap interrupt_installer INT TERM

declare -a SELECTED_INSTALLERS=()
needs_apt_update=false

for entry in "${INSTALLERS[@]}"; do
    IFS='|' read -r name _ _ display <<< "$entry"
    if [[ "$INSTALL_ALL" == true || "${INSTALL_FLAGS[$name]}" == true ]]; then
        SELECTED_INSTALLERS+=("$name")
        if contains_item "$name" "${NEEDS_APT_UPDATE[@]}"; then
            needs_apt_update=true
        fi
    fi
done

if [[ "$needs_apt_update" == true ]]; then
    add_step "system_update" "APT package index (update)"
fi

for name in "${SELECTED_INSTALLERS[@]}"; do
    add_step "$name" "$(get_step_label "$name")"
done

ui_start

if [[ "$needs_apt_update" == true ]]; then
    if ! run_step_shell "system_update" "sudo apt-get update"; then
        ui_finish "error" "Failed to update APT package index."
        exit 1
    fi
fi

for name in "${SELECTED_INSTALLERS[@]}"; do
    script="$SCRIPT_DIR/$name/install.sh"
    run_step_script "$name" "$script"
done

if [[ "$HAD_FAILURE" == true ]]; then
    ui_finish "error" "Some selected package installations failed."
    exit 1
fi

ui_finish "success" "All selected package installations completed!"
