#!/bin/bash

# Assertions shared by the shell tests. Each test file sources this, runs its
# assertions, and exits with `test_result`.

# shellcheck disable=SC2034  # ROOT is for the sourcing test file.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

assert_eq() {
    local name="$1" got="$2" want="$3"
    if [[ "$got" == "$want" ]]; then
        echo "ok   $name"
    else
        echo "FAIL $name: got=$got want=$want" >&2
        failures=$((failures + 1))
    fi
}

assert_contains() {
    local name="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "ok   $name"
    else
        echo "FAIL $name: missing '$needle'" >&2
        failures=$((failures + 1))
    fi
}

assert_not_contains() {
    local name="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "FAIL $name: found '$needle'" >&2
        failures=$((failures + 1))
    else
        echo "ok   $name"
    fi
}

test_result() {
    (( failures == 0 ))
}
