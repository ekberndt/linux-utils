#!/usr/bin/env python3
"""Encode classic DuckyScript 1.0 to inject.bin (US keyboard layout).

Compatible with Hak5 USB Rubber Ducky inject.bin payloads. Supports the
subset needed for bootstrap scripts: REM, DELAY, DEFAULT_DELAY, STRING,
ENTER, TAB, SPACE, ESC, modifier combos (CTRL-ALT, GUI, …), and single keys.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# USB HID usage IDs (keyboard/keypad page) and left-hand modifiers.
_MOD_CTRL = 0x01
_MOD_SHIFT = 0x02
_MOD_ALT = 0x04
_MOD_GUI = 0x08

# Unshifted letter/digit scancodes.
_ALPHA = {chr(ord("a") + i): 0x04 + i for i in range(26)}
_DIGIT = {
    "1": 0x1E,
    "2": 0x1F,
    "3": 0x20,
    "4": 0x21,
    "5": 0x22,
    "6": 0x23,
    "7": 0x24,
    "8": 0x25,
    "9": 0x26,
    "0": 0x27,
}

# char -> (keycode, needs_shift)
_US_PUNCT: dict[str, tuple[int, bool]] = {
    " ": (0x2C, False),
    "-": (0x2D, False),
    "=": (0x2E, False),
    "[": (0x2F, False),
    "]": (0x30, False),
    "\\": (0x31, False),
    ";": (0x33, False),
    "'": (0x34, False),
    "`": (0x35, False),
    ",": (0x36, False),
    ".": (0x37, False),
    "/": (0x38, False),
    "!": (0x1E, True),
    "@": (0x1F, True),
    "#": (0x20, True),
    "$": (0x21, True),
    "%": (0x22, True),
    "^": (0x23, True),
    "&": (0x24, True),
    "*": (0x25, True),
    "(": (0x26, True),
    ")": (0x27, True),
    "_": (0x2D, True),
    "+": (0x2E, True),
    "{": (0x2F, True),
    "}": (0x30, True),
    "|": (0x31, True),
    ":": (0x33, True),
    '"': (0x34, True),
    "~": (0x35, True),
    "<": (0x36, True),
    ">": (0x37, True),
    "?": (0x38, True),
}

_NAMED_KEYS: dict[str, int] = {
    "ENTER": 0x28,
    "RETURN": 0x28,
    "ESC": 0x29,
    "ESCAPE": 0x29,
    "BACKSPACE": 0x2A,
    "TAB": 0x2B,
    "SPACE": 0x2C,
    "CAPSLOCK": 0x39,
    "F1": 0x3A,
    "F2": 0x3B,
    "F3": 0x3C,
    "F4": 0x3D,
    "F5": 0x3E,
    "F6": 0x3F,
    "F7": 0x40,
    "F8": 0x41,
    "F9": 0x42,
    "F10": 0x43,
    "F11": 0x44,
    "F12": 0x45,
    "PRINTSCREEN": 0x46,
    "SCROLLLOCK": 0x47,
    "PAUSE": 0x48,
    "INSERT": 0x49,
    "HOME": 0x4A,
    "PAGEUP": 0x4B,
    "DELETE": 0x4C,
    "END": 0x4D,
    "PAGEDOWN": 0x4E,
    "RIGHT": 0x4F,
    "RIGHTARROW": 0x4F,
    "LEFT": 0x50,
    "LEFTARROW": 0x50,
    "DOWN": 0x51,
    "DOWNARROW": 0x51,
    "UP": 0x52,
    "UPARROW": 0x52,
}


def _pair(keycode: int, modifier: int = 0) -> bytes:
    return bytes((keycode & 0xFF, modifier & 0xFF))


def _delay_bytes(ms: int) -> bytes:
    if ms < 0:
        raise ValueError(f"DELAY must be non-negative, got {ms}")
    out = bytearray()
    while ms > 0:
        chunk = min(ms, 255)
        out.extend((0x00, chunk))
        ms -= chunk
    return bytes(out)


def _char_bytes(ch: str) -> bytes:
    if ch in _ALPHA:
        return _pair(_ALPHA[ch])
    if "A" <= ch <= "Z":
        return _pair(_ALPHA[ch.lower()], _MOD_SHIFT)
    if ch in _DIGIT:
        return _pair(_DIGIT[ch])
    if ch in _US_PUNCT:
        key, shift = _US_PUNCT[ch]
        return _pair(key, _MOD_SHIFT if shift else 0)
    raise ValueError(f"unsupported character for US layout: {ch!r} (U+{ord(ch):04X})")


def _named_key(name: str) -> int:
    key = _NAMED_KEYS.get(name.upper())
    if key is None and len(name) == 1:
        ch = name.lower()
        if ch in _ALPHA:
            return _ALPHA[ch]
        if ch in _DIGIT:
            return _DIGIT[ch]
    if key is None:
        raise ValueError(f"unknown key: {name}")
    return key


def _modifier_combo(cmd: str, args: str) -> bytes:
    parts = cmd.upper().replace("+", "-").split("-")
    mod = 0
    key_name: str | None = None
    for part in parts:
        if part in ("CTRL", "CONTROL"):
            mod |= _MOD_CTRL
        elif part == "SHIFT":
            mod |= _MOD_SHIFT
        elif part == "ALT":
            mod |= _MOD_ALT
        elif part in ("GUI", "WINDOWS", "COMMAND"):
            mod |= _MOD_GUI
        else:
            key_name = part
    if args:
        key_name = args.strip()
    if not key_name:
        # Bare modifier key press (e.g. GUI alone).
        if mod == _MOD_GUI:
            return _pair(0xE3, _MOD_GUI)  # Left GUI key
        if mod == _MOD_CTRL:
            return _pair(0xE0, 0)
        if mod == _MOD_ALT:
            return _pair(0xE2, 0)
        if mod == _MOD_SHIFT:
            return _pair(0xE1, 0)
        raise ValueError(f"{cmd} requires a key argument")
    return _pair(_named_key(key_name), mod)


def encode_script(source: str) -> bytes:
    """Compile DuckyScript source into inject.bin bytes."""
    out = bytearray()
    default_delay = 0
    last_instruction: bytes | None = None

    for raw_line in source.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("REM") or line.startswith("//"):
            continue

        if line.upper().startswith("REPEAT"):
            _, _, count_s = line.partition(" ")
            if not count_s.strip() or last_instruction is None:
                raise ValueError(f"REPEAT requires a prior instruction: {line}")
            count = int(count_s.strip())
            out.extend(last_instruction * count)
            if default_delay:
                out.extend(_delay_bytes(default_delay) * count)
            continue

        cmd, _, args = line.partition(" ")
        cmd_u = cmd.upper()
        args = args.strip()
        instruction = bytearray()

        if cmd_u == "DEFAULT_DELAY" or cmd_u == "DEFAULTDELAY":
            default_delay = int(args)
            last_instruction = None
            continue
        if cmd_u == "DELAY":
            instruction.extend(_delay_bytes(int(args)))
        elif cmd_u == "STRING":
            for ch in args:
                instruction.extend(_char_bytes(ch))
        elif cmd_u in ("ENTER", "RETURN", "TAB", "SPACE", "ESC", "ESCAPE", "BACKSPACE"):
            instruction.extend(_pair(_named_key(cmd_u)))
        elif cmd_u in _NAMED_KEYS:
            instruction.extend(_pair(_named_key(cmd_u)))
        elif any(tok in cmd_u for tok in ("CTRL", "CONTROL", "ALT", "SHIFT", "GUI", "WINDOWS", "COMMAND")):
            instruction.extend(_modifier_combo(cmd_u, args))
        elif len(cmd) == 1 and not args:
            instruction.extend(_char_bytes(cmd if cmd.islower() or not cmd.isalpha() else cmd))
            if cmd.isalpha() and cmd.isupper():
                instruction[:] = _char_bytes(cmd)
        else:
            # Single named key possibly with no args, e.g. "DOWNARROW"
            instruction.extend(_pair(_named_key(cmd_u if not args else args)))

        out.extend(instruction)
        last_instruction = bytes(instruction)
        if default_delay and instruction:
            out.extend(_delay_bytes(default_delay))

    return bytes(out)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Encode DuckyScript 1.0 → inject.bin (US layout)")
    parser.add_argument("-i", "--input", type=Path, required=True, help="DuckyScript source file")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("inject.bin"),
        help="Output path (default: inject.bin)",
    )
    args = parser.parse_args(argv)

    source = args.input.read_text(encoding="utf-8")
    try:
        payload = encode_script(source)
    except ValueError as exc:
        print(f"encode error: {exc}", file=sys.stderr)
        return 1

    args.output.write_bytes(payload)
    print(f"wrote {args.output} ({len(payload)} bytes) from {args.input}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
