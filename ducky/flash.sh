#!/usr/bin/env bash
# Encode a DuckyScript payload and write inject.bin onto a mounted Rubber Ducky.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD="${1:-${SCRIPT_DIR}/payloads/ubuntu-install.txt}"
OUT_BIN="${SCRIPT_DIR}/build/inject.bin"
MOUNT="${DUCKY_MOUNT:-}"

die() {
    echo "error: $*" >&2
    exit 1
}

find_mount() {
    local candidate
    for candidate in \
        "${DUCKY_MOUNT:-}" \
        /Volumes/DUCKY \
        /media/"${USER}"/DUCKY \
        /run/media/"${USER}"/DUCKY \
        /mnt/DUCKY; do
        [[ -n "${candidate}" && -d "${candidate}" ]] || continue
        # Rubber Ducky arming volume always exposes inject.bin path as writable root.
        if [[ -w "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 1
}

command -v python3 >/dev/null || die "python3 is required"
[[ -f "${PAYLOAD}" ]] || die "payload not found: ${PAYLOAD}"

if [[ -z "${MOUNT}" ]]; then
    MOUNT="$(find_mount)" || die "no mounted Ducky found (set DUCKY_MOUNT or plug in arming mode)"
fi
[[ -d "${MOUNT}" && -w "${MOUNT}" ]] || die "mount not writable: ${MOUNT}"

mkdir -p "${SCRIPT_DIR}/build"
python3 "${SCRIPT_DIR}/encode.py" -i "${PAYLOAD}" -o "${OUT_BIN}"

# Keep a copy of the payload source next to inject.bin on the stick for reference.
cp "${OUT_BIN}" "${MOUNT}/inject.bin"
cp "${PAYLOAD}" "${MOUNT}/payload.txt"
# Force FAT cache flush so the ducky sees the new bin after eject.
if command -v sync >/dev/null; then
    sync
fi

echo "flashed ${OUT_BIN} -> ${MOUNT}/inject.bin"
echo "also wrote ${MOUNT}/payload.txt (human-readable source)"
echo
echo "This host only wrote inject.bin (arming). Target is Ubuntu, not this machine."
echo "Next steps:"
echo "  1. Eject the volume (${MOUNT})"
echo "  2. Unplug the Ducky"
echo "  3. On a logged-in Ubuntu desktop, plug it in"
echo "  4. Enter your sudo password when the bootstrap script prompts"
echo
echo "Eject now with:"
if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "  diskutil eject ${MOUNT}"
else
    echo "  udisksctl unmount -b \$(findmnt -n -o SOURCE --target ${MOUNT})  # or: umount ${MOUNT}"
fi
