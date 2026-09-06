#!/bin/bash
set -uo pipefail

# flash.sh must take identity from env, write only inject.bin to the mount, and
# leave no secret in the repo or a payload.txt on the stick.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

FLASH="$ROOT/ducky/flash.sh"
PAYLOAD="$ROOT/ducky/payloads/ubuntu-install.txt"
WORKDIR="$(mktemp -d)"
trap 'rm -rf -- "$WORKDIR"' EXIT

MOUNT="$WORKDIR/mnt"
mkdir -p "$MOUNT"
chmod 700 "$WORKDIR"

PASSWORD='flash-test-pw-NOTREAL!'
PUBKEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyMaterial alice@example'
printf '%s\n' "$PUBKEY" >"$WORKDIR/id.pub"

DUCKY_USERNAME=alice \
    DUCKY_FULLNAME='Alice Example' \
    DUCKY_PASSWORD="$PASSWORD" \
    DUCKY_PUBKEY_FILE="$WORKDIR/id.pub" \
    DUCKY_MOUNT="$MOUNT" \
    bash "$FLASH" "$PAYLOAD" >/dev/null

assert_eq "inject.bin is on the stick" "$([[ -f $MOUNT/inject.bin ]] && echo yes)" "yes"
assert_eq "inject.bin is non-empty" "$([[ -s $MOUNT/inject.bin ]] && echo yes)" "yes"
assert_eq "no plaintext payload.txt on the stick" "$([[ -e $MOUNT/payload.txt ]] && echo yes || echo no)" "no"

tracked="$(grep -F "$PASSWORD" "$PAYLOAD" "$ROOT/ducky/flash.sh" "$ROOT/ducky/encode.py" 2>/dev/null || true)"
assert_eq "password is not in tracked ducky sources" "$tracked" ""

leftover="$(grep -RFl --exclude-dir=.git --exclude-dir=__pycache__ --exclude-dir=tests "$PASSWORD" "$ROOT" 2>/dev/null || true)"
assert_eq "password is not left in the repo" "$leftover" ""

# Missing identity must not flash the ubuntu payload.
no_id="$WORKDIR/no-id"
mkdir -p "$no_id"
status=0
DUCKY_MOUNT="$no_id" bash "$FLASH" "$PAYLOAD" >/dev/null 2>"$WORKDIR/err" </dev/null || status=$?
assert_eq "flash without identity fails" "$status" "1"
assert_contains "error names the missing username env" "$(< "$WORKDIR/err")" "DUCKY_USERNAME"

# Tilde in DUCKY_PUBKEY_FILE expands; the picker is skipped when the env is set.
tilde_mnt="$WORKDIR/tilde-mnt"
mkdir -p "$tilde_mnt" "$WORKDIR/fake-home/.ssh"
printf '%s\n' "$PUBKEY" >"$WORKDIR/fake-home/.ssh/id_ed25519.pub"
# shellcheck disable=SC2088
DUCKY_USERNAME=alice \
    DUCKY_FULLNAME='Alice Example' \
    DUCKY_PASSWORD="$PASSWORD" \
    DUCKY_PUBKEY_FILE='~/.ssh/id_ed25519.pub' \
    DUCKY_MOUNT="$tilde_mnt" \
    HOME="$WORKDIR/fake-home" \
    bash "$FLASH" "$PAYLOAD" >/dev/null
assert_eq "tilde pubkey path flashes" "$([[ -s $tilde_mnt/inject.bin ]] && echo yes)" "yes"

test_result
