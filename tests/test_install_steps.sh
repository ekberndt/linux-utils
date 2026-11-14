#!/bin/bash
set -uo pipefail

# The step runner: one status line per step, output in per-step logs, and
# failures loud even when the quiet output would otherwise hide them.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=../installers/lib/common.sh
source "$ROOT/installers/lib/common.sh"
# shellcheck source=../installers/lib/steps.sh
source "$ROOT/installers/lib/steps.sh"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
STEPS_LOG_ROOT="$tmp/logs"

# Steps run in a subshell, so these are visible to run_step.
# shellcheck disable=SC2329
current_step() { echo "noise from a converged step"; }
# shellcheck disable=SC2329
installing_step() { echo "package manager chatter"; print_installed "just"; print_installed "dust"; }
# shellcheck disable=SC2329
updating_step() { print_updated "tmux-resurrect"; }
# shellcheck disable=SC2329
skipping_step() { print_skipped "no NVIDIA GPU"; }
# shellcheck disable=SC2329
warning_step() { print_warning "run 'gh auth login'"; }
# shellcheck disable=SC2329
failing_step() { echo "E: Unable to locate package nope"; return 3; }
# shellcheck disable=SC2329
erroring_step() { print_error "half the packages failed"; return 0; }
# shellcheck disable=SC2329
buried_error_step() {
    print_error "Failed to install: bad-package"
    seq 1 40 | sed 's/^/apt chatter /'
    return 1
}
# shellcheck disable=SC2329
prompting_step() { printf 'Continue? [y/N] '; read -r answer && [[ "$answer" == y ]]; }

output="$(
    start_steps "Test" "8 steps" 8
    run_step current "Current thing" current_step
    run_step installing "Installing thing" installing_step
    run_step updating "Updating thing" updating_step
    run_step skipping "Skipping thing" skipping_step
    run_step warning "Warning thing" warning_step
    run_step failing "Failing thing" failing_step
    run_step erroring "Erroring thing" erroring_step
    run_step prompting "Prompting thing" prompting_step
    finish_steps
    echo "finish=$?"
)"
run_dir="$(echo "$tmp"/logs/*/)"

line_for() { grep -F "$1" <<<"$output" | head -1; }

assert_contains "a quiet step is already current" "$(line_for "Current thing")" "already current"
assert_not_contains "step output stays out of the terminal" "$output" "noise from a converged step"
assert_contains "step output lands in its log" "$(< "$run_dir/current.log")" \
    "noise from a converged step"
assert_contains "an install reads as installed" "$(line_for "Installing thing")" "installed"
assert_contains "the installed items are named" "$(line_for "Installing thing")" "just, dust"
assert_not_contains "package manager output stays in the log" "$output" "package manager chatter"
assert_contains "an update reads as updated" "$(line_for "Updating thing")" "updated"
assert_contains "a skip reads as skipped with its reason" "$(line_for "Skipping thing")" \
    "skipped"
assert_contains "the skip reason is shown" "$(line_for "Skipping thing")" "no NVIDIA GPU"
assert_contains "warnings surface under their step" "$output" "⚠ run 'gh auth login'"
assert_contains "a step's time is shown" "$(line_for "Current thing")" "0."

assert_contains "a failing step reads as failed" "$(line_for "Failing thing")" "failed"
assert_contains "a failure shows its exit code" "$(line_for "Failing thing")" "exit 3"
assert_contains "a failure shows the log tail" "$output" "│ E: Unable to locate package nope"
assert_contains "a failure names its full log" "$output" "full log: $run_dir"failing.log
assert_contains "an error reported under exit 0 still fails" \
    "$(line_for "Erroring thing")" "failed"
assert_contains "a prompt on stdin fails instead of hanging" \
    "$(line_for "Prompting thing")" "failed"
assert_contains "the prompt it wrote shows in the log tail" "$output" "│ Continue? [y/N]"

buried="$(
    start_steps "Test" "1 step" 1
    run_step buried "Buried thing" buried_error_step
)"
assert_contains "an error above the log tail is still shown" "$buried" \
    "✗ Failed to install: bad-package"
assert_not_contains "the tail itself is bounded" "$buried" "│ apt chatter 1"

assert_contains "the summary counts every state" "$output" \
    "8 steps in"
assert_contains "the summary counts failures" "$output" "3 failed"
assert_contains "the summary counts warnings" "$output" "1 warning"
assert_contains "the run names every failed step" "$output" "Failed: failing erroring prompting"
assert_contains "a failed step fails the run" "$output" "finish=1"

clean="$(
    start_steps "Test" "1 step" 1
    run_step current "Current thing" current_step
    finish_steps
    echo "finish=$?"
)"
assert_contains "a clean run completes" "$clean" "Installation complete"
assert_contains "a clean run succeeds" "$clean" "finish=0"
assert_contains "a clean run says 1 step" "$clean" "1 step in"

for i in $(seq 1 25); do
    mkdir -p "$STEPS_LOG_ROOT/20200101-0000$(printf '%02d' "$i")-old"
done
(start_steps "Test" "0 steps" 0 >/dev/null)
assert_eq "old runs are pruned to the newest $STEPS_KEEP_RUNS" \
    "$(find "$STEPS_LOG_ROOT" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" \
    "$STEPS_KEEP_RUNS"
assert_eq "the newest runs survive pruning" \
    "$(test -d "$STEPS_LOG_ROOT/20200101-000025-old" && echo kept || echo pruned)" "kept"

assert_eq "durations under a minute keep a decimal" "$(format_duration 1234)" "1.2s"
assert_eq "durations over a minute show minutes" "$(format_duration 65432)" "1m05s"

test_result
