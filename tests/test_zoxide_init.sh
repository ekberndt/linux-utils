#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_HOME="$(mktemp -d)"
trap 'rm -rf -- "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.local/bin"
cat > "$TEST_HOME/.local/bin/zoxide" <<'EOF'
#!/bin/bash
case "${1:-}" in
    --version) echo "zoxide test" ;;
    init) echo 'z() { :; }' ;;
esac
EOF
chmod +x "$TEST_HOME/.local/bin/zoxide"
# shellcheck disable=SC2016 # This is the literal broken config under test.
printf '%s\n' 'eval "$(zoxide init bash)"' > "$TEST_HOME/.bashrc"

run_installer() {
    env -i \
        HOME="$TEST_HOME" \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        bash "$ROOT/installers/zoxide/install.sh"
}

run_installer >/dev/null
first="$(< "$TEST_HOME/.bashrc")"
run_installer >/dev/null
second="$(< "$TEST_HOME/.bashrc")"

[[ "$first" == "$second" ]]
[[ "$(grep -Fc '.local/bin' "$TEST_HOME/.bashrc")" == 1 ]]

output="$(
    env -i \
        HOME="$TEST_HOME" \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        TERM=xterm-256color \
        bash --noprofile --rcfile "$TEST_HOME/.bashrc" -i -c 'type z' 2>&1
)"
[[ "$output" == *'z is a function'* ]]
