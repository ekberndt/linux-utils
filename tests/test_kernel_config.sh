#!/bin/bash
set -uo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/proc/fs/inotify"

cat > "$tmp/bin/uname" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == -s ]]; then
    echo "${FAKE_OS:-Linux}"
    exit 0
fi
exec /usr/bin/uname "$@"
EOF

cat > "$tmp/bin/sudo" <<'EOF'
#!/bin/bash
printf 'sudo:%s\n' "$*" >> "$SUDO_LOG"
"$@"
EOF

cat > "$tmp/bin/sysctl" <<'EOF'
#!/bin/bash
printf 'sysctl:%s\n' "$*" >> "$SUDO_LOG"
echo 8192 > "$PROC_SYS_DIR/fs/inotify/max_user_instances"
echo 1048576 > "$PROC_SYS_DIR/fs/inotify/max_user_watches"
EOF

chmod +x "$tmp/bin/uname" "$tmp/bin/sudo" "$tmp/bin/sysctl"
export PATH="$tmp/bin:$PATH"
export SUDO_LOG="$tmp/sudo.log"
export SYSCTL_TARGET_CONFIG="$tmp/etc/sysctl.d/99-linux-utils.conf"
export PROC_SYS_DIR="$tmp/proc"

echo 128 > "$PROC_SYS_DIR/fs/inotify/max_user_instances"
echo 524288 > "$PROC_SYS_DIR/fs/inotify/max_user_watches"
: > "$SUDO_LOG"

dry_output="$(DRY_RUN=true bash "$ROOT/installers/config/kernel.sh")"
assert_contains "dry run reports planned sysctl file install" \
    "$dry_output" "would install kernel sysctl config: $SYSCTL_TARGET_CONFIG"
assert_contains "dry run reports planned sysctl apply" \
    "$dry_output" "would apply kernel sysctl settings"
assert_eq "dry run does not invoke sudo" "$(< "$SUDO_LOG")" ""

apply_output="$(bash "$ROOT/installers/config/kernel.sh")"
assert_contains "installs sysctl config" \
    "$apply_output" "Installed kernel sysctl config: $SYSCTL_TARGET_CONFIG"
assert_contains "applies sysctl config" \
    "$apply_output" "Applied kernel sysctl settings"
assert_contains "writes max_user_instances" \
    "$(< "$SYSCTL_TARGET_CONFIG")" "fs.inotify.max_user_instances = 8192"
assert_contains "writes max_user_watches" \
    "$(< "$SYSCTL_TARGET_CONFIG")" "fs.inotify.max_user_watches = 1048576"

: > "$SUDO_LOG"
converged_output="$(bash "$ROOT/installers/config/kernel.sh")"
assert_contains "converged run reports config already installed" \
    "$converged_output" "Kernel sysctl config already installed"
assert_contains "converged run reports settings already active" \
    "$converged_output" "Kernel sysctl settings already active"
assert_eq "converged run does not invoke sudo" "$(< "$SUDO_LOG")" ""

darwin_output="$(FAKE_OS=Darwin bash "$ROOT/installers/config/kernel.sh")"
assert_contains "Darwin skips kernel config" \
    "$darwin_output" "skipping kernel config (not Linux)"

assert_contains "tmux boot unit sets OOMPolicy=continue" \
    "$(< "$ROOT/installers/tmux/install.sh")" "OOMPolicy=continue"

test_result
