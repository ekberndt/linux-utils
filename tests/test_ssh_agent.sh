#!/bin/bash
set -uo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

run="$tmp/run" # XDG_RUNTIME_DIR
link="$run/ssh-agent.sock"
mkdir -p "$run/gcr" "$tmp/home" "$tmp/bin"

# A bound Unix socket's file outlives its process, which is all `-S` checks.
make_socket() {
    python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$1"
}

# Each spawned agent gets its own socket, so reuse shows up as one spawn.
cat > "$tmp/bin/ssh-agent" <<MOCK
#!/bin/bash
sock="$tmp/spawned.\$\$"
python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "\$sock"
echo "SSH_AUTH_SOCK=\$sock; export SSH_AUTH_SOCK;"
MOCK
chmod +x "$tmp/bin/ssh-agent"

# new_shell [VAR=value]...: the agent path a fresh shell exports, and its target.
new_shell() {
    # shellcheck disable=SC2016 # Expanded by the child shell.
    env -i HOME="$tmp/home" PATH="$tmp/bin:$PATH" XDG_RUNTIME_DIR="$run" "$@" \
        bash -c '. "$1"; printf "%s -> %s\n" "$SSH_AUTH_SOCK" "$(readlink "$SSH_AUTH_SOCK")"' \
        _ "$ROOT/.bash_aliases"
}

make_socket "$run/gcr/ssh"
assert_eq "stale inherited socket falls back to gcr agent" \
    "$(new_shell SSH_AUTH_SOCK="$tmp/gone/agent.1")" "$link -> $run/gcr/ssh"

make_socket "$tmp/forwarded"
assert_eq "live forwarded agent takes over the link" \
    "$(new_shell SSH_AUTH_SOCK="$tmp/forwarded")" "$link -> $tmp/forwarded"
assert_eq "pane inheriting the link keeps the forwarded agent" \
    "$(new_shell SSH_AUTH_SOCK="$link")" "$link -> $tmp/forwarded"

rm "$tmp/forwarded"
assert_eq "closed forwarding falls back to gcr agent" \
    "$(new_shell SSH_AUTH_SOCK="$link")" "$link -> $run/gcr/ssh"

rm "$run/gcr/ssh"
first="$(new_shell)"
assert_contains "no live agent starts one behind the link" "$first" "$link -> $tmp/spawned."
assert_eq "later shells reuse the started agent" "$(new_shell)" "$first"
assert_eq "only one agent is started" \
    "$(find "$tmp" -maxdepth 1 -name 'spawned.*' | wc -l)" "1"

test_result
