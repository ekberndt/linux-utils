#!/bin/bash
set -uo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

test_dir="$(mktemp -d)"
trap 'rm -r "$test_dir"' EXIT

cp "$ROOT/tests/fixtures/tmux-clipboard" "$test_dir/tmux"
chmod +x "$test_dir/tmux"
export TMUX_CLIPBOARD_TEST_DIR="$test_dir"
export PATH="$test_dir:$PATH"

# OSC 52 path: client answers with a new buffer.
touch "$test_dir/will_respond"
bash "$ROOT/scripts/tmux-paste-clipboard" %7 /dev/pts/4
assert_eq "requests clipboard from client tty" \
    "$(< "$test_dir/request")" "refresh-client -l -t /dev/pts/4"
assert_eq "pastes newly imported buffer" \
    "$(< "$test_dir/paste")" "paste-buffer -p -b buffer1 -t %7"
rm -f "$test_dir/will_respond" "$test_dir/responded" "$test_dir/request" "$test_dir/paste"

# Fallback: no client answer, paste the existing buffer and exit 0.
touch "$test_dir/has_buffer"
bash "$ROOT/scripts/tmux-paste-clipboard" %3 /dev/pts/2
assert_eq "falls back to existing tmux buffer" \
    "$(< "$test_dir/paste")" "paste-buffer -p -b buffer0 -t %3"
assert_eq "does not show empty-buffer message on fallback" \
    "$([[ -f "$test_dir/message" ]] && echo present || echo absent)" "absent"

# Empty: no buffers and no client -> soft message, exit 0 (no run-shell error).
rm -f "$test_dir/has_buffer" "$test_dir/paste" "$test_dir/request"
bash "$ROOT/scripts/tmux-paste-clipboard" %1 /dev/pts/9
assert_eq "displays soft message when no buffer exists" \
    "$([[ -f "$test_dir/message" ]] && echo present || echo absent)" "present"

test_result
