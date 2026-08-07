#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -r "$test_dir"' EXIT

cp "$ROOT/tests/fixtures/tmux-clipboard" "$test_dir/tmux"
chmod +x "$test_dir/tmux"
export TMUX_CLIPBOARD_TEST_DIR="$test_dir"
export PATH="$test_dir:$PATH"

# OSC 52 path: client answers with a new buffer.
touch "$test_dir/will_respond"
bash "$ROOT/scripts/tmux-paste-clipboard" %7 /dev/pts/4
request="$(< "$test_dir/request")"
paste="$(< "$test_dir/paste")"
[[ "$request" == "refresh-client -l -t /dev/pts/4" ]]
[[ "$paste" == "paste-buffer -p -b buffer1 -t %7" ]]
rm -f "$test_dir/will_respond" "$test_dir/responded" "$test_dir/request" "$test_dir/paste"

# Fallback: no client answer, paste the existing buffer and exit 0.
touch "$test_dir/has_buffer"
bash "$ROOT/scripts/tmux-paste-clipboard" %3 /dev/pts/2
paste="$(< "$test_dir/paste")"
[[ "$paste" == "paste-buffer -p -b buffer0 -t %3" ]]
[[ ! -f "$test_dir/message" ]]

# Empty: no buffers and no client → soft message, exit 0 (no run-shell error).
rm -f "$test_dir/has_buffer" "$test_dir/paste" "$test_dir/request"
bash "$ROOT/scripts/tmux-paste-clipboard" %1 /dev/pts/9
[[ -f "$test_dir/message" ]]
