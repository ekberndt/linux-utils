#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -r "$test_dir"' EXIT

cp "$ROOT/tests/fixtures/tmux-clipboard" "$test_dir/tmux"
chmod +x "$test_dir/tmux"
export TMUX_CLIPBOARD_TEST_DIR="$test_dir"

PATH="$test_dir:$PATH" bash "$ROOT/scripts/tmux-paste-clipboard" %7 /dev/pts/4

request="$(< "$test_dir/request")"
paste="$(< "$test_dir/paste")"

[[ "$request" == "refresh-client -l -t /dev/pts/4" ]]
[[ "$paste" == "paste-buffer -p -b buffer1 -t %7" ]]
