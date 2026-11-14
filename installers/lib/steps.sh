#!/bin/bash

# The step runner behind installer.sh and macos/install.sh. Each step's output
# goes to its own log; the terminal gets one status line per step, the warnings
# it raised, and, when it fails, the tail of its log. Sourced after common.sh,
# and kept bash 3.2 compatible for macOS.

STEPS_LOG_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/linux-utils/install"
STEPS_KEEP_RUNS=20
STEPS_TAIL_LINES=20

# Wall clock in milliseconds. EPOCHREALTIME is bash 5; macOS's bash 3.2 gets
# whole seconds. The separator follows LC_NUMERIC.
now_ms() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        local us="${EPOCHREALTIME/[.,]/}"
        echo $(( us / 1000 ))
    else
        echo $(( $(date +%s) * 1000 ))
    fi
}

format_duration() {
    local ms="$1"
    if (( ms < 60000 )); then
        printf '%d.%ds' $(( ms / 1000 )) $(( ms % 1000 / 100 ))
    else
        printf '%dm%02ds' $(( ms / 60000 )) $(( ms % 60000 / 1000 ))
    fi
}

plural() {
    if (( $1 == 1 )); then printf '1 %s' "$2"; else printf '%d %ss' "$1" "$2"; fi
}

tilde() {
    case "$1" in
        "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
        *) printf '%s' "$1" ;;
    esac
}

# Up to three items, then a count of the rest.
join_items() {
    local item shown=""
    for item in "${@:1:3}"; do
        shown="$shown${shown:+, }$(tilde "$item")"
    done
    (( $# > 3 )) && shown="$shown +$(( $# - 3 )) more"
    printf '%s' "$shown"
}

# start_steps <title> <subtitle> <step-count>
start_steps() {
    local i
    local -a runs

    mkdir -p "$STEPS_LOG_ROOT" &&
        STEPS_RUN_DIR="$(mktemp -d "$STEPS_LOG_ROOT/$(date +%Y%m%d-%H%M%S)-XXXX")" || return 1
    # Run directories sort oldest first by their timestamp names.
    runs=("$STEPS_LOG_ROOT"/*/)
    for (( i = 0; i < ${#runs[@]} - STEPS_KEEP_RUNS; i++ )); do
        rm -rf -- "${runs[i]}"
    done

    STEPS_PLANNED="$3"
    STEPS_STARTED_MS="$(now_ms)"
    STEPS_TOTAL=0 STEPS_CURRENT=0 STEPS_INSTALLED=0 STEPS_UPDATED=0
    STEPS_SKIPPED=0 STEPS_WARNINGS=0
    STEPS_FAILED=()

    print_header "$1"
    printf '  %s\n' "$2"
    printf '  %slogs: %s%s\n\n' "$DIM" "$(tilde "$STEPS_RUN_DIR")" "$NC"

    # The pending status line has no newline; end it before the shell goes.
    trap 'printf "\n"; print_error "Interrupted; logs in $(tilde "$STEPS_RUN_DIR")"; exit 130' INT
}

# run_step <name> <label> <command>...
# Runs one step in a subshell with stdin closed, so a prompt written into the
# log fails fast rather than hanging out of sight. sudo asks on /dev/tty, which
# stays the terminal.
run_step() {
    local name="$1" label="$2"
    shift 2
    local log="$STEPS_RUN_DIR/$name.log" status_file="$STEPS_RUN_DIR/$name.status"
    local started elapsed rc=0 kind text state color icon=✓ detail
    local -a installed=() updated=() skipped=() warnings=() errors=()

    STEPS_TOTAL=$((STEPS_TOTAL + 1))
    : > "$status_file"
    [[ -t 1 ]] && printf '  %s⋯ %s (%d/%d)%s' "$DIM" "$label" "$STEPS_TOTAL" "$STEPS_PLANNED" "$NC"
    started="$(now_ms)"
    (
        export INSTALLER_STATUS_FILE="$status_file"
        "$@"
    ) > "$log" 2>&1 < /dev/null || rc=$?
    elapsed="$(format_duration $(( $(now_ms) - started )))"
    [[ -t 1 ]] && printf '\r\033[K'

    while IFS=$'\t' read -r kind text; do
        case "$kind" in
            installed) installed+=("$text") ;;
            updated) updated+=("$text") ;;
            skipped) skipped+=("$text") ;;
            warn) warnings+=("$text") ;;
            error) errors+=("$text") ;;
        esac
    done < "$status_file"

    # A reported error fails the step even if the script still exited 0.
    if (( rc != 0 || ${#errors[@]} > 0 )); then
        state=failed color="$RED" icon=✗ detail="exit $rc"
        (( rc == 0 )) && detail="reported an error"
        STEPS_FAILED+=("$name")
    elif (( ${#installed[@]} > 0 )); then
        state=installed color="$BLUE" detail="$(join_items "${installed[@]}")"
        STEPS_INSTALLED=$((STEPS_INSTALLED + 1))
    elif (( ${#updated[@]} > 0 )); then
        state=updated color="$BLUE" detail="$(join_items "${updated[@]}")"
        STEPS_UPDATED=$((STEPS_UPDATED + 1))
    elif (( ${#skipped[@]} > 0 )); then
        state=skipped color="$YELLOW" detail="$(join_items "${skipped[@]}")"
        STEPS_SKIPPED=$((STEPS_SKIPPED + 1))
    else
        state="already current" color="$GREEN" detail=""
        STEPS_CURRENT=$((STEPS_CURRENT + 1))
    fi

    printf '  %s%s%s %-26s %s%-15s%s %s%6s%s  %s\n' \
        "$color" "$icon" "$NC" "$label" "$color" "$state" "$NC" \
        "$DIM" "$elapsed" "$NC" "$detail"

    if (( ${#warnings[@]} > 0 )); then
        STEPS_WARNINGS=$((STEPS_WARNINGS + ${#warnings[@]}))
        for text in "${warnings[@]}"; do
            printf '      %s⚠ %s%s\n' "$YELLOW" "$(tilde "$text")" "$NC"
        done
    fi

    if [[ "$state" == failed ]]; then
        # The line naming what failed can sit above the tail, under the apt
        # output that followed it.
        if (( ${#errors[@]} > 0 )); then
            for text in "${errors[@]}"; do
                printf '      %s✗ %s%s\n' "$RED" "$(tilde "$text")" "$NC"
            done
        fi
        tail -n "$STEPS_TAIL_LINES" "$log" | sed 's/^/      │ /'
        printf '      %s└ full log: %s%s\n' "$RED" "$(tilde "$log")" "$NC"
    fi
}

# Print the run summary; fails when any step failed.
finish_steps() {
    local summary

    summary="$(plural "$STEPS_TOTAL" step) in $(format_duration $(( $(now_ms) - STEPS_STARTED_MS )))"
    (( STEPS_INSTALLED > 0 )) && summary="$summary · $STEPS_INSTALLED installed"
    (( STEPS_UPDATED > 0 )) && summary="$summary · $STEPS_UPDATED updated"
    (( STEPS_CURRENT > 0 )) && summary="$summary · $STEPS_CURRENT already current"
    (( STEPS_SKIPPED > 0 )) && summary="$summary · $STEPS_SKIPPED skipped"
    (( STEPS_WARNINGS > 0 )) && summary="$summary · $(plural "$STEPS_WARNINGS" warning)"
    (( ${#STEPS_FAILED[@]} > 0 )) && summary="$summary · ${#STEPS_FAILED[@]} failed"
    printf '\n  %s\n' "$summary"

    if (( ${#STEPS_FAILED[@]} > 0 )); then
        print_error "Failed: ${STEPS_FAILED[*]}. Logs: $(tilde "$STEPS_RUN_DIR")"
        return 1
    fi
    print_success "Installation complete"
}
