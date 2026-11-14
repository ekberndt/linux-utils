#!/bin/bash
set -uo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TEST_HOME="$(mktemp -d)"
trap 'rm -rf -- "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.local/bin" "$TEST_HOME/stub"
cat > "$TEST_HOME/.local/bin/zoxide" <<'MOCK'
#!/bin/bash
case "${1:-}" in
    --version) echo "zoxide 0.10.0" ;;
    init) echo 'z() { :; }' ;;
esac
MOCK
# The installed zoxide is the latest release, so nothing is downloaded.
cat > "$TEST_HOME/stub/curl" <<'MOCK'
#!/bin/bash
printf 'https://github.com/ajeetdsouza/zoxide/releases/tag/v0.10.0'
MOCK
chmod +x "$TEST_HOME/.local/bin/zoxide" "$TEST_HOME/stub/curl"
# shellcheck disable=SC2016 # This is the literal broken config under test.
printf '%s\n' 'eval "$(zoxide init bash)"' > "$TEST_HOME/.bashrc"

run_installer() {
    env -i \
        HOME="$TEST_HOME" \
        PATH="$TEST_HOME/stub":/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        bash "$ROOT/installers/zoxide/install.sh"
}

run_installer >/dev/null
first="$(< "$TEST_HOME/.bashrc")"
run_installer >/dev/null
second="$(< "$TEST_HOME/.bashrc")"

assert_eq "zoxide installer is idempotent on .bashrc" "$first" "$second"
assert_eq "zoxide PATH setup is added once" \
    "$(grep -Fc '.local/bin' "$TEST_HOME/.bashrc")" "1"

output="$(
    env -i \
        HOME="$TEST_HOME" \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        TERM=xterm-256color \
        bash --noprofile --rcfile "$TEST_HOME/.bashrc" -i -c 'type z' 2>&1
)"
assert_contains "non-login interactive shell initializes z function" \
    "$output" "z is a function"

test_result
