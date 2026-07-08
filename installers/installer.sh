#!/bin/bash

# Master installer script
# Installs packages from all supported package managers

# Needs bash 4+ (associative arrays, coproc, ${var,,}); macOS ships 3.2, so re-exec under a newer bash.
if [[ -z "${BASH_VERSINFO:-}" || "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash bash; do
        candidate_path="$(command -v "$candidate" 2>/dev/null)" || continue
        candidate_major="$("$candidate_path" -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null)"
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

# --- Installer Registry ---
# Format: "directory_name|short_flag|long_flag|display_name"
# To add a new installer: create <dir>/install.sh and add one line here.
INSTALLERS=(
    "apt|a|apt|APT Packages"
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
    "cargo|r|cargo|Cargo packages (via Rustup)"
    "lazyvim|l|lazyvim|LazyVim (Neovim + LazyVim starter)"
    "config|C|config|Config sync (Bash aliases, Claude, Codex, shared agent scripts/skills, Neovim, tmux)"
)

# Installers that need "sudo apt-get update && apt-get upgrade" run first. Anything
# omitted from this list (e.g. "config") runs without touching apt.
NEEDS_APT_UPDATE=(apt flatpak snap homebrew uv tailscale bazelisk buildtools gh claude codex cargo lazyvim)

# --- Help ---
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    for entry in "${INSTALLERS[@]}"; do
        IFS='|' read -r _ short long display <<< "$entry"
        printf "  -%s, --%-12s Install %s\n" "$short" "$long" "$display"
    done
    echo "      --all         Install all package types"
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
            -h|--help) show_help; exit 0 ;;
            *) echo "Unknown option: $1"; echo "Use --help for usage information"; exit 1 ;;
        esac
    fi
    shift
done

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

# --- Dashboard helpers ---
TTY_MODE=false
if [[ -t 1 && -t 2 ]]; then
    TTY_MODE=true
fi

declare -a STEP_ORDER=()
declare -A STEP_STATUS
declare -A STEP_LABEL
declare -A STEP_MESSAGE
declare -a CURRENT_STEP_LINES=()

DASHBOARD_MESSAGE=""
HAD_FAILURE=false
RUNNING_STEP_PID=""
RUNNING_STEP_KEY=""
DASHBOARD_TERM_COLUMNS=80
DASHBOARD_TERM_ROWS=24
DASHBOARD_HEADER_LINES=18
DASHBOARD_BODY_MAX_LINES=20
DASHBOARD_BODY_START=0
DASHBOARD_HEADER_REFRESH=1
DASHBOARD_LAST_HEADER_TS=0

ICON_PENDING="[ ]"
ICON_RUNNING="[-]"
ICON_DONE="[+]"
ICON_FAILED="[x]"
ICON_MISSING="[!]"
ICON_UNKNOWN="[?]"

add_step() {
    local key="$1"
    local label="$2"
    STEP_ORDER+=("$key")
    STEP_STATUS["$key"]="pending"
    STEP_LABEL["$key"]="$label"
    STEP_MESSAGE["$key"]=""
}

dashboard_recompute_layout() {
    if [[ "$TTY_MODE" != true ]]; then
        return
    fi
    local sz_rows sz_cols
    if command -v stty >/dev/null 2>&1 && [[ -t 1 ]]; then
        read -r sz_rows sz_cols < <(stty size < /dev/tty 2>/dev/null || true)
    fi
    if [[ "${sz_rows:-}" =~ ^[0-9]+$ && "${sz_cols:-}" =~ ^[0-9]+$ ]]; then
        DASHBOARD_TERM_ROWS="$sz_rows"
        DASHBOARD_TERM_COLUMNS="$sz_cols"
    else
        DASHBOARD_TERM_COLUMNS="$(tput cols 2>/dev/null || echo 80)"
        DASHBOARD_TERM_ROWS="$(tput lines 2>/dev/null || echo 24)"
    fi

    if (( DASHBOARD_TERM_COLUMNS < 20 )); then
        DASHBOARD_TERM_COLUMNS=80
    fi
    if (( DASHBOARD_TERM_ROWS < 10 )); then
        DASHBOARD_TERM_ROWS=24
    fi
    local available_body_lines=$((DASHBOARD_TERM_ROWS - DASHBOARD_HEADER_LINES - 3))
    if (( available_body_lines < 1 )); then
        available_body_lines=1
    fi
    DASHBOARD_BODY_MAX_LINES=$available_body_lines
    DASHBOARD_BODY_START=$DASHBOARD_HEADER_LINES
}

dashboard_clear_lines() {
    local lines="$1"
    local row=0
    while (( row < lines )); do
        tput cup "$row" 0
        tput el 2>/dev/null || true
        ((row++))
    done
}

dashboard_render_body() {
    if [[ "$TTY_MODE" != true ]]; then
        return
    fi

    local idx=0
    local line=""
    while (( idx < DASHBOARD_BODY_MAX_LINES )); do
        tput cup $((DASHBOARD_BODY_START + idx)) 0
        tput el 2>/dev/null || true

        if (( idx < ${#CURRENT_STEP_LINES[@]} )); then
            line="${CURRENT_STEP_LINES[$idx]}"
            if (( idx + 1 >= DASHBOARD_BODY_MAX_LINES )); then
                printf "%-*s" "$DASHBOARD_TERM_COLUMNS" "${line:0:$DASHBOARD_TERM_COLUMNS}"
            else
                printf "%-*s\n" "$DASHBOARD_TERM_COLUMNS" "${line:0:$DASHBOARD_TERM_COLUMNS}"
            fi
        else
            if (( idx + 1 >= DASHBOARD_BODY_MAX_LINES )); then
                printf "%*s" "$DASHBOARD_TERM_COLUMNS" ""
            else
                printf "%*s\n" "$DASHBOARD_TERM_COLUMNS" ""
            fi
        fi
        ((idx++))
    done
}

dashboard_clear_body_window() {
    if [[ "$TTY_MODE" != true ]]; then
        return
    fi

    local end_row
    local row="$DASHBOARD_BODY_START"
    end_row=$((DASHBOARD_BODY_START + DASHBOARD_BODY_MAX_LINES - 1))
    if (( end_row < DASHBOARD_BODY_START )); then
        end_row=$DASHBOARD_BODY_START
    fi
    while (( row <= end_row )); do
        tput cup "$row" 0
        tput el 2>/dev/null || true
        if (( row < end_row )); then
            printf "%*s\n" "$DASHBOARD_TERM_COLUMNS" ""
        else
            printf "%*s" "$DASHBOARD_TERM_COLUMNS" ""
        fi
        ((row++))
    done
}

dashboard_print_final_status() {
    local status_type="$1"
    local text="$2"
    local final_row

    if [[ "$TTY_MODE" != true ]]; then
        if [[ "$status_type" == "error" ]]; then
            print_error "$text"
        else
            print_success "$text"
        fi
        return
    fi

    final_row=$((DASHBOARD_BODY_START + DASHBOARD_BODY_MAX_LINES))
    if (( final_row > DASHBOARD_TERM_ROWS - 2 )); then
        final_row=$((DASHBOARD_TERM_ROWS - 2))
    fi
    if (( final_row < 0 )); then
        final_row=0
    fi
    tput cup "$final_row" 0
    tput el 2>/dev/null || true

    if [[ "$status_type" == "error" ]]; then
        print_error "$text"
    else
        print_success "$text"
    fi
}
dashboard_set_message() {
    local message="$1"
    local force="${2:-false}"
    local now

    DASHBOARD_MESSAGE="$message"
    if [[ "$TTY_MODE" != true ]]; then
        return
    fi

    now=$(date +%s)
  if [[ "$force" == true ]]; then
      DASHBOARD_LAST_HEADER_TS="$now"
      dashboard_render_header
  elif (( now - DASHBOARD_LAST_HEADER_TS >= DASHBOARD_HEADER_REFRESH )); then
      DASHBOARD_LAST_HEADER_TS="$now"
      dashboard_render_header
  fi
}

dashboard_render_header() {
    if [[ "$TTY_MODE" != true ]]; then
        return
    fi

    local completed=0
    local total=${#STEP_ORDER[@]}
    local key status icon status_line=""
    local latest_line=""
    local width="$DASHBOARD_TERM_COLUMNS"
    local checklist_columns=4
    local checklist_rows=0
    local checklist_gap=2
    local col_width=0
    local cell_text=""
    local status_color=""
    local display_step=""
    local pad=0
    local percent=0
    local completed_text=""
    local bar_width
    local filled
    local bar=""
    local i=0
    local row=0
    local col=0
    local cell_idx=0
    local step_key=""
    local extra_steps=0
    local displayed_steps=0
    local header_lines=0
    local previous_header_lines=$DASHBOARD_HEADER_LINES

    for key in "${STEP_ORDER[@]}"; do
        status="${STEP_STATUS[$key]:-pending}"
        case "$status" in
            done|failed|missing) completed=$((completed + 1)) ;;
        esac
    done

    if (( total > 0 )); then
        percent=$(( (completed * 100) / total ))
    fi

    bar_width=$(( width - 28 ))
    if (( bar_width < 16 )); then
        bar_width=16
    fi
    filled=$(( percent * bar_width / 100 ))
    local bar_filled=""
    local bar_empty=""
    while (( i < bar_width )); do
        if (( i < filled )); then
            bar_filled+="#"
        else
            bar_empty+="."
        fi
        ((i++))
    done
    bar="${GREEN}${bar_filled}${YELLOW}${bar_empty}${NC}"

    completed_text="${completed}/${total}"

    if (( width >= 120 )); then
        checklist_columns=4
    elif (( width >= 90 )); then
        checklist_columns=3
    elif (( width >= 60 )); then
        checklist_columns=2
    else
        checklist_columns=1
    fi

    if (( checklist_columns > total && total > 0 )); then
        checklist_columns=$total
    fi

    if (( checklist_columns <= 0 )); then
        checklist_columns=1
    fi

    checklist_rows=$(( (total + checklist_columns - 1) / checklist_columns ))
    if (( checklist_rows < 1 )); then
        checklist_rows=1
    fi

    col_width=$(( (width - (checklist_gap * (checklist_columns - 1))) / checklist_columns ))
    if (( col_width < 12 )); then
        col_width=12
        checklist_columns=1
        checklist_rows=$(( (total + checklist_columns - 1) / checklist_columns ))
    fi

    dashboard_clear_lines "$previous_header_lines"
    tput cup 0 0
    print_header "Linux Utils Installer"
    printf " %-9s : [" "PROGRESS"
    printf "%s" "$bar"
    printf "] %3d%% (%s)\n" "$percent" "$completed_text"

    printf " CHECKLIST\n"
    for ((row = 0; row < checklist_rows; row++)); do
        status_line=""
        for ((col = 0; col < checklist_columns; col++)); do
            cell_idx=$(( row * checklist_columns + col ))
            if (( cell_idx >= total )); then
                status_line+="$(printf "%*s" "$col_width" "")"
                if (( col + 1 < checklist_columns )); then
                    status_line+="$(printf "%*s" "$checklist_gap" "")"
                fi
                continue
            fi

            step_key="${STEP_ORDER[$cell_idx]}"
            status="${STEP_STATUS[$step_key]:-pending}"
            case "$status" in
                pending) icon="$ICON_PENDING"; status_color="${BLUE}" ;;
                running) icon="$ICON_RUNNING"; status_color="${YELLOW}" ;;
                done)    icon="$ICON_DONE"; status_color="${GREEN}" ;;
                failed)  icon="$ICON_FAILED"; status_color="${RED}" ;;
                missing) icon="$ICON_MISSING"; status_color="${YELLOW}" ;;
                *)       icon="$ICON_UNKNOWN"; status_color="${BOLD}" ;;
            esac
            display_step="$step_key"
            pad=$(( col_width - 5 - ${#display_step} ))
            if (( pad < 0 )); then
                display_step="${display_step:0:$((col_width - 5))}"
                pad=0
            fi
            cell_text="${status_color}${icon}${NC} ${display_step}"
            status_line+="${cell_text}$(printf "%*s" "$pad" "")"
            if (( col + 1 < checklist_columns )); then
                status_line+="$(printf "%*s" "$checklist_gap" "")"
            fi
            displayed_steps=$((displayed_steps + 1))
        done
        printf "%s\n" "$status_line"
    done

    extra_steps=$(( total - displayed_steps ))
    if (( extra_steps > 0 )); then
        printf "  ... and %d more\n" "$extra_steps"
    fi

    header_lines=$(( 3 + 1 + 1 + checklist_rows + 2 ))
    if (( extra_steps > 0 )); then
        header_lines=$(( header_lines + 1 ))
    fi
    if (( header_lines + 1 > DASHBOARD_TERM_ROWS )); then
        header_lines=$(( DASHBOARD_TERM_ROWS - 1 ))
    fi
    DASHBOARD_HEADER_LINES=$header_lines
    DASHBOARD_BODY_START=$DASHBOARD_HEADER_LINES
    dashboard_recompute_layout

    latest_line="CURRENT INSTALLER: ${DASHBOARD_MESSAGE}"
    if (( ${#latest_line} > width )); then
        latest_line="${latest_line:0:$width}"
    fi
    printf "%-*s\n" "$width" "$latest_line"
    dashboard_render_body
}

dashboard_start() {
    if [[ "$TTY_MODE" == true ]]; then
        tput clear 2>/dev/null || true
        tput civis 2>/dev/null || true
        dashboard_recompute_layout
        dashboard_render_header true
    fi
}

dashboard_stop() {
    if [[ "$TTY_MODE" == true ]]; then
        tput cnorm 2>/dev/null || true
    fi
}

cleanup_terminal() {
    dashboard_stop
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
    fi

    cleanup_terminal
    exit 130
}

run_step_tty_with_args() {
    local key="$1"
    shift
    local fd pid status line skip_line line_lc

    if (( $# == 0 )); then
        return 1
    fi

    STEP_STATUS["$key"]="running"
    STEP_MESSAGE["$key"]=""
    RUNNING_STEP_KEY="$key"
    CURRENT_STEP_LINES=()
    dashboard_set_message "${STEP_LABEL[$key]}" true

    coproc STEP_PROC { "$@" 2>&1; }
    fd="${STEP_PROC[0]}"
    pid="${STEP_PROC_PID}"
    RUNNING_STEP_PID="$pid"

    while IFS= read -r -u "$fd" line; do
        line="${line//$'\r'/}"
        if [[ -z "$line" ]]; then
            continue
        fi

        skip_line=false
        line_lc="${line,,}"
        case "$line_lc" in
            *"all packages are up to date"*|\
            *"all packages installed."*|*"all packages installed"*|\
            *"apt installation complete."*|*"flatpak installation complete."*|*"snap installation complete."*|\
            *"lazyvim installation complete."*|*"syncing claude config"*|*"syncing codex config"*|\
            *"syncing nvim config"*|*"syncing tmux config"*|*"Done."*)
                skip_line=true
                ;;
            *) skip_line=false ;;
        esac
        if [[ "$skip_line" == true ]]; then
            continue
        fi

        STEP_MESSAGE["$key"]="$line"
        CURRENT_STEP_LINES+=("$line")
        if (( ${#CURRENT_STEP_LINES[@]} > DASHBOARD_BODY_MAX_LINES )); then
            CURRENT_STEP_LINES=("${CURRENT_STEP_LINES[@]:1}")
        fi
        DASHBOARD_MESSAGE="${STEP_LABEL[$key]}: $line"
        dashboard_render_body
    done

    exec {fd}<&- 2>/dev/null || true
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

    dashboard_set_message "${STEP_MESSAGE[$key]}" true
    return $status
}

run_step_tty_script() {
    local key="$1"
    local script="$2"

    if [[ ! -f "$script" ]]; then
        STEP_STATUS["$key"]="missing"
        HAD_FAILURE=true
        STEP_MESSAGE["$key"]="${STEP_LABEL[$key]} installer not found at $script"
        dashboard_set_message "${STEP_MESSAGE[$key]}" true
        CURRENT_STEP_LINES=("${STEP_MESSAGE[$key]}")
        dashboard_render_body
        return 1
    fi

    if [[ "$script" == "$SCRIPT_DIR/config/install.sh" ]]; then
        run_step_tty_with_args "$key" env INSTALLER_QUIET_CONFIG=1 bash "$script"
    else
        run_step_tty_with_args "$key" bash "$script"
    fi
}

run_step_simple_script() {
    local key="$1"
    local script="$2"
    local label="${STEP_LABEL[$key]:-$key}"

    print_header "Installing $label"
    if [[ -f "$script" ]]; then
        if bash "$script"; then
            STEP_STATUS["$key"]="done"
            STEP_MESSAGE["$key"]="$label complete"
        else
            STEP_STATUS["$key"]="failed"
            STEP_MESSAGE["$key"]="$label failed"
            HAD_FAILURE=true
            return 1
        fi
    else
        STEP_STATUS["$key"]="missing"
        STEP_MESSAGE["$key"]="${label} installer not found at $script"
        print_warning "${STEP_MESSAGE[$key]}"
        HAD_FAILURE=true
        return 1
    fi
    return 0
}

run_step_tty_shell() {
    local key="$1"
    local command="$2"
    run_step_tty_with_args "$key" bash -lc "$command"
}

trap cleanup_terminal EXIT
trap interrupt_installer INT TERM
trap 'dashboard_recompute_layout; dashboard_set_message "$DASHBOARD_MESSAGE" true' WINCH

if [[ "$TTY_MODE" == true ]]; then
    dashboard_start
else
    print_header "Linux Utils Installer"
fi

# Build ordered selected step queue.
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
    add_step "system_update" "System Update (apt)"
fi

for name in "${SELECTED_INSTALLERS[@]}"; do
    add_step "$name" "$(get_step_label "$name")"
done

dashboard_set_message "Starting installation..." true

if [[ "$needs_apt_update" == true ]]; then
    if [[ "$TTY_MODE" == true ]]; then
        if ! run_step_tty_shell "system_update" "sudo apt-get update && sudo apt-get upgrade -y"; then
            cleanup_terminal
            exit 1
        fi
    else
        print_header "Updating System"
        if ! sudo apt-get update || ! sudo apt-get upgrade -y; then
            print_error "Failed to update system"
            exit 1
        fi
    fi
fi

for name in "${SELECTED_INSTALLERS[@]}"; do
    script="$SCRIPT_DIR/$name/install.sh"
    if [[ "$TTY_MODE" == true ]]; then
        run_step_tty_script "$name" "$script"
    else
        run_step_simple_script "$name" "$script"
    fi
done

if [[ "$HAD_FAILURE" == true ]]; then
    if [[ "$TTY_MODE" == true ]]; then
        cleanup_terminal
        dashboard_clear_body_window
        dashboard_print_final_status "error" "Some selected package installations failed."
    else
        print_error "Some selected package installations failed."
    fi
    exit 1
fi

if [[ "$TTY_MODE" == true ]]; then
    cleanup_terminal
    dashboard_clear_body_window
    dashboard_print_final_status "success" "All selected package installations completed!"
else
    print_success "All selected package installations completed!"
fi
