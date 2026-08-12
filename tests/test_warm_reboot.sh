#!/bin/bash
set -uo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fake_bin="$(mktemp -d)"
trap 'rm -r -- "$fake_bin"' EXIT

cat > "$fake_bin/systemctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*"
EOF
chmod +x "$fake_bin/systemctl"

output="$(PATH="$fake_bin:$PATH" bash "$ROOT/installers/warm-reboot/warm-reboot")"
assert_eq "warm reboot delegates to systemd soft reboot" "$output" "soft-reboot"

assert_eq "warm reboot rejects arguments" \
    "$(PATH="$fake_bin:$PATH" bash "$ROOT/installers/warm-reboot/warm-reboot" now \
        >/dev/null 2>&1; echo $?)" "2"

test_result
