#!/bin/bash
set -euo pipefail

# Every interactive shell used to fork its own ssh-agent, and none of them ever
# exited. Drive the real .bash_aliases against stub agent binaries so a spawn is
# countable and no daemon survives the test.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TEST_HOME="$(mktemp -d)"
trap 'rm -rf -- "$TEST_HOME"' EXIT

BIN="$TEST_HOME/bin"
RUNTIME="$TEST_HOME/run"
COUNT_FILE="$TEST_HOME/spawns"
mkdir -p "$BIN" "$RUNTIME"

# Each -s call records a spawn and leaves a file standing in for the socket.
cat > "$BIN/ssh-agent" <<'EOF'
#!/bin/bash
count=$(( $(cat "$FAKE_AGENT_COUNT" 2>/dev/null || echo 0) + 1 ))
printf '%s' "$count" > "$FAKE_AGENT_COUNT"
socket="$FAKE_AGENT_DIR/agent.$count"
: > "$socket"
printf 'SSH_AUTH_SOCK=%s; export SSH_AUTH_SOCK;\n' "$socket"
printf 'SSH_AGENT_PID=%s; export SSH_AGENT_PID;\n' "$count"
printf 'echo Agent pid %s;\n' "$count"
EOF

# Liveness follows the socket file: gone means nothing answers, hence exit 2.
cat > "$BIN/ssh-add" <<'EOF'
#!/bin/bash
[ -e "${SSH_AUTH_SOCK:-}" ] || exit 2
exit 1
EOF
chmod +x "$BIN/ssh-agent" "$BIN/ssh-add"

spawns() { cat "$COUNT_FILE" 2>/dev/null || echo 0; }

# shellcheck disable=SC2016 # Expanded by the shell under test, not by this one.
PRINT_SOCK='printf "%s" "$SSH_AUTH_SOCK"'

# $1: "interactive" or "script", $2: snippet run after .bash_aliases is sourced.
run_shell() {
    local flags=()
    [[ "$1" == interactive ]] && flags=(-i)

    env -i \
        HOME="$TEST_HOME" \
        PATH="$BIN:/usr/local/bin:/usr/bin:/bin" \
        XDG_RUNTIME_DIR="$RUNTIME" \
        SSH_AUTH_SOCK="${INHERITED_SOCK:-}" \
        FAKE_AGENT_COUNT="$COUNT_FILE" \
        FAKE_AGENT_DIR="$RUNTIME" \
        bash --noprofile --norc "${flags[@]}" -c \
        "source '$ROOT/.bash_aliases'; $2"
}

# A script that sources the file must not leave a daemon behind.
run_shell script ":" >/dev/null 2>&1
assert_eq "non-interactive source spawns no agent" "$(spawns)" "0"

# An interactive shell with no agent gets exactly one.
first_sock="$(run_shell interactive "$PRINT_SOCK" 2>/dev/null)"
assert_eq "interactive shell starts one agent" "$(spawns)" "1"
assert_eq "interactive shell exports the socket" "$first_sock" "$RUNTIME/agent.1"

# The bug: every later shell forked its own. They must reuse this one instead.
second_sock="$(run_shell interactive "$PRINT_SOCK" 2>/dev/null)"
assert_eq "later shells reuse the running agent" "$(spawns)" "1"
assert_eq "later shells share one socket" "$second_sock" "$first_sock"

# Sourcing the env file echoes "Agent pid N" unless it is silenced.
reuse_output="$(run_shell interactive ':' 2>/dev/null)"
assert_eq "reuse prints nothing" "$reuse_output" ""

# A reboot leaves the env file pointing at a socket nobody answers on.
rm -f "$RUNTIME/agent.1"
stale_sock="$(run_shell interactive "$PRINT_SOCK" 2>/dev/null)"
assert_eq "a dead socket is replaced" "$(spawns)" "2"
assert_eq "the replacement is exported" "$stale_sock" "$RUNTIME/agent.2"

# A forwarded agent must survive: it holds the keys this machine does not.
INHERITED_SOCK="$RUNTIME/agent.2"
forwarded_sock="$(run_shell interactive "$PRINT_SOCK" 2>/dev/null)"
assert_eq "a forwarded agent is left alone" "$(spawns)" "2"
assert_eq "a forwarded socket is kept" "$forwarded_sock" "$RUNTIME/agent.2"
unset INHERITED_SOCK

test_result
