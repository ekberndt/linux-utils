#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../installers/lib/package_list.sh
source "$ROOT/installers/lib/package_list.sh"
# shellcheck source=../installers/lib/stream_filter.sh
source "$ROOT/installers/lib/stream_filter.sh"

failures=0
assert_eq() {
    local name="$1" got="$2" want="$3"
    if [[ "$got" != "$want" ]]; then
        echo "FAIL $name: got=$got want=$want" >&2
        failures=$((failures + 1))
    else
        echo "ok   $name"
    fi
}

assert_parse() {
    local name="$1" line="$2" want_pkg="$3" want_opt="$4" want_ppa="$5"
    package=""; optional=false; ppa=""
    if ! parse_package_line "$line"; then
        assert_eq "$name skip" "skipped" "parsed"
        return
    fi
    assert_eq "$name package" "$package" "$want_pkg"
    assert_eq "$name optional" "$optional" "$want_opt"
    assert_eq "$name ppa" "$ppa" "$want_ppa"
}

assert_classify() {
    local name="$1" line="$2" want="$3"
    local got=0
    # classify uses exit statuses 0/1/2; do not trip set -e
    classify_output_line "$line" || got=$?
    assert_eq "$name" "$got" "$want"
}

echo "== parse_package_line =="
assert_parse "simple" "git # version control" "git" "false" ""
assert_parse "optional" "? sway # tiling" "sway" "true" ""
assert_parse "ppa" "foo | ppa:user/repo # desc" "foo" "false" "user/repo"
package=""; optional=false; ppa=""
if parse_package_line "# comment only"; then
    assert_eq "comment" "parsed" "skipped"
else
    assert_eq "comment" "skipped" "skipped"
fi
package=""; optional=false; ppa=""
if parse_package_line ""; then
    assert_eq "blank" "parsed" "skipped"
else
    assert_eq "blank" "skipped" "skipped"
fi

echo "== classify_output_line =="
rule="$(printf '%*s' 80 '' | tr ' ' '-')"
assert_classify "dash-rule" "$rule" "0"
assert_classify "homepage" "Homepage: https://neovim.io" "0"
assert_classify "reading" "Reading package lists..." "0"
assert_classify "percent" "Downloading... 50%" "2"
assert_classify "success" "✓ Already installed: git" "1"
assert_classify "failed" "✗ Failed to install: just" "1"
assert_classify "unable" "E: Unable to locate package just" "1"
assert_classify "installing" "Installing: mosh" "1"

echo "== inject-grok/codex toml =="
if python3 "$ROOT/tests/test_inject_toml_config.py"; then
    echo "ok   inject toml config"
else
    echo "FAIL inject toml config" >&2
    failures=$((failures + 1))
fi

echo "== babysit-pr next_check =="
if python3 "$ROOT/tests/test_next_check.py"; then
    echo "ok   next_check"
else
    echo "FAIL next_check" >&2
    failures=$((failures + 1))
fi

if (( failures > 0 )); then
    echo "$failures test(s) failed" >&2
    exit 1
fi
echo "All tests passed."
