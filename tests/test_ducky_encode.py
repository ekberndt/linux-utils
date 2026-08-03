#!/usr/bin/env python3
"""Unit tests for ducky/encode.py (classic DuckyScript → inject.bin)."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENCODE_PATH = ROOT / "ducky" / "encode.py"


def load_encode():
    spec = importlib.util.spec_from_file_location("ducky_encode", ENCODE_PATH)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules["ducky_encode"] = mod
    spec.loader.exec_module(mod)
    return mod


encode_mod = load_encode()


class TestDuckyEncode(unittest.TestCase):
    def test_delay_splits_over_255(self):
        out = encode_mod.encode_script("DELAY 300")
        self.assertEqual(out, bytes((0x00, 0xFF, 0x00, 0x2D)))

    def test_string_hello(self):
        # h=0x0b, e=0x08, l=0x0f, l=0x0f, o=0x12 — each with mod 0
        out = encode_mod.encode_script("STRING hello")
        self.assertEqual(
            out,
            bytes(
                (
                    0x0B,
                    0x00,
                    0x08,
                    0x00,
                    0x0F,
                    0x00,
                    0x0F,
                    0x00,
                    0x12,
                    0x00,
                )
            ),
        )

    def test_shift_letter_and_symbol(self):
        out = encode_mod.encode_script('STRING A!')
        # A = key 0x04 + shift; ! = key 0x1e + shift
        self.assertEqual(out, bytes((0x04, 0x02, 0x1E, 0x02)))

    def test_ctrl_alt_t(self):
        out = encode_mod.encode_script("CTRL-ALT t")
        # t = 0x17, modifiers CTRL|ALT = 0x01|0x04 = 0x05
        self.assertEqual(out, bytes((0x17, 0x05)))

    def test_enter_and_rem_ignored(self):
        out = encode_mod.encode_script("REM ignore me\nENTER\n// also ignore")
        self.assertEqual(out, bytes((0x28, 0x00)))

    def test_default_delay_after_command(self):
        out = encode_mod.encode_script("DEFAULT_DELAY 10\nENTER")
        self.assertEqual(out, bytes((0x28, 0x00, 0x00, 0x0A)))

    def test_repeat(self):
        out = encode_mod.encode_script("ENTER\nREPEAT 2")
        self.assertEqual(out, bytes((0x28, 0x00, 0x28, 0x00, 0x28, 0x00)))

    def test_ubuntu_payload_encodes(self):
        payload = (ROOT / "ducky" / "payloads" / "ubuntu-install.txt").read_text(encoding="utf-8")
        self.assertIn("bash installers/installer.sh personal", payload)
        self.assertNotIn("installer.sh --all", payload)
        out = encode_mod.encode_script(payload)
        self.assertGreater(len(out), 100)
        self.assertEqual(len(out) % 2, 0)

    def test_unsupported_char_raises(self):
        with self.assertRaises(ValueError):
            encode_mod.encode_script("STRING café")


if __name__ == "__main__":
    unittest.main()
