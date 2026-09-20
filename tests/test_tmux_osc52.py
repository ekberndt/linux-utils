#!/usr/bin/env python3
"""Clipboard paths must reach the client as an explicit "c" selection.

Asserting on config text cannot catch this class of failure: the override that
broke it (Ms hardcoding the selection, so tparm never expanded it) read exactly
like the fix. So drive a real tmux server through a pty and read the bytes.

  application OSC 52 in a pane -> set-clipboard forwards it
  copy-mode Enter binding      -> @osc52-copy-command writes it
  DCS-wrapped OSC 52           -> allow-passthrough unwraps it

mosh forwards only ESC ] 52 ; c ; …, never the empty-selection form tmux uses
for its own copies, so a path that emits ESC ] 52 ; ; … is a regression here.
Grok and Neovim wrap OSC 52 in DCS when they see $TMUX; tmux 3.3+ drops that
unless allow-passthrough is enabled, which is the grok doctor dcs-passthrough
finding. `all` (not `on`) is required: `on` only unwraps visible panes, and a
CI pty often has no size so the pane is not visible.
"""

import base64
import fcntl
import os
import pty
import re
import shutil
import struct
import subprocess
import sys
import termios
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONF = os.path.join(ROOT, "tmux", "tmux.conf")
SOCKET = f"linux-utils-osc52-{os.getpid()}"
OSC52 = re.compile(rb"\x1b\]52;([^;]*);([A-Za-z0-9+/=]*)(?:\x07|\x1b\\)")


def tmux(*args, capture=True):
    """Run a tmux client command.

    Never capture the calls that spawn the server: it daemonizes off this
    process, and a captured pipe it inherits is never closed, so reading to EOF
    would block forever. Bound the rest, so a wedged tmux fails the test rather
    than hanging the run with nothing to say which call stopped.
    """
    sink = subprocess.PIPE if capture else subprocess.DEVNULL
    return subprocess.run(["tmux", "-L", SOCKET, *args],
                          stdout=sink, stderr=sink, text=True, timeout=30)


class Terminal:
    """Everything the attached client has written, read without pause.

    Draining only in bursts lets the pty fill while the test is between reads.
    The client then blocks writing to it, the server blocks on the client, and
    the next tmux command never returns — which is how this hung a CI runner
    while passing locally, where the client happens to be less chatty.
    """

    def __init__(self, fd):
        self._fd = fd
        self._seen = bytearray()
        self._lock = threading.Lock()
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        while True:
            try:
                chunk = os.read(self._fd, 65536)
            except OSError:
                return
            if not chunk:
                return
            with self._lock:
                self._seen.extend(chunk)

    def snapshot(self):
        with self._lock:
            return bytes(self._seen)

    def wait_for(self, predicate, seconds):
        """Poll until predicate accepts the stream, then return it either way."""
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            data = self.snapshot()
            if predicate(data):
                return data
            time.sleep(0.05)
        return self.snapshot()


def copies(data):
    """(selection, decoded payload) for every clipboard write in the stream."""
    out = []
    for selection, payload in OSC52.findall(data):
        try:
            decoded = base64.b64decode(payload).decode("utf-8", "replace")
        except ValueError:
            decoded = ""
        out.append((selection.decode(), decoded))
    return out


def check(name, ok, detail=""):
    if ok:
        print(f"ok   {name}")
        return 0
    print(f"FAIL {name}{': ' + detail if detail else ''}", file=sys.stderr)
    return 1


if shutil.which("tmux") is None:
    print("skip tmux OSC 52 (tmux not installed)")
    sys.exit(0)

tmux("kill-server", capture=False)
tmux("-f", CONF, "new-session", "-d", "-s", "t", "-x", "80", "-y", "24",
     capture=False)

# pty.fork gives the client a controlling terminal; without one tmux attach
# exits with "open terminal failed" and every assertion below trivially passes.
pid, master = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"
    os.environ.pop("TMUX", None)
    os.execvp("tmux", ["tmux", "-L", SOCKET, "attach", "-t", "t"])
# A GitHub Actions runner pty is often 0x0, so tmux does not treat the pane as
# visible. Size it before we start reading so attach sees a real terminal.
fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))

failures = 0
try:
    term = Terminal(master)

    startup = term.wait_for(bool, 5.0)
    failures += check("tmux client attaches to the probe server", len(startup) > 0,
                      "client wrote nothing; the rest of this file proves nothing")

    features = tmux("display-message", "-p", "#{client_termfeatures}").stdout
    failures += check("tmux resolves the clipboard capability",
                      "clipboard" in features, f"features={features.strip()}")

    passthrough = tmux("show-options", "-wgv", "allow-passthrough").stdout.strip()
    failures += check("allow-passthrough is all for DCS-wrapped OSC 52",
                      passthrough == "all", f"allow-passthrough={passthrough}")

    # Path 1: an application inside a pane sets the clipboard.
    pane_tty = tmux("display-message", "-p", "#{pane_tty}").stdout.strip()
    with open(pane_tty, "wb") as fh:
        fh.write(b"\x1b]52;c;" + base64.b64encode(b"APPCLIPBOARD") + b"\x07")
    seen = copies(term.wait_for(
        lambda data: ("c", "APPCLIPBOARD") in copies(data), 5.0))
    failures += check("application OSC 52 reaches the client as 'c'",
                      ("c", "APPCLIPBOARD") in seen, f"saw {seen}")

    # Path 2: Grok/Neovim wrap OSC 52 in DCS when $TMUX is set. Writing the
    # envelope to the pane tty is what those apps do to stdout. Do this before
    # copy-mode: Enter's copy-selection-and-cancel plus the background
    # run-shell left CI's pane in a state that dropped the next DCS.
    dcs_payload = base64.b64encode(b"DCSCLIPBOARD")
    with open(pane_tty, "wb") as fh:
        fh.write(b"\x1bPtmux;\x1b\x1b]52;c;" + dcs_payload + b"\x07\x1b\\")
    seen = copies(term.wait_for(
        lambda data: ("c", "DCSCLIPBOARD") in copies(data), 5.0))
    failures += check("DCS-wrapped OSC 52 reaches the client as 'c'",
                      ("c", "DCSCLIPBOARD") in seen, f"saw {seen}")

    # Path 3: the real Enter binding, which is copy-selection plus the
    # @osc52-copy-command run-shell. send-keys -X would skip the run-shell.
    #
    # Put the text on screen by writing to the pane's tty rather than having its
    # shell echo it: asking the shell to run a command is a round-trip through
    # whatever shell the machine happens to start, and waiting on that is what
    # wedged this on a CI runner.
    with open(pane_tty, "wb") as fh:
        fh.write(b"COPYMODEPROBE\r\n")
    term.wait_for(lambda data: b"COPYMODEPROBE" in data, 5.0)
    tmux("copy-mode", "-t", "t")
    tmux("send-keys", "-X", "-t", "t", "cursor-up")
    tmux("send-keys", "-X", "-t", "t", "select-line")
    tmux("send-keys", "-t", "t", "Enter")

    def copied_probe(data):
        return any("COPYMODEPROBE" in payload
                   for selection, payload in copies(data) if selection == "c")

    seen = copies(term.wait_for(copied_probe, 5.0))
    explicit = [payload for selection, payload in seen if selection == "c"]
    failures += check("copy-mode copy reaches the client as 'c'",
                      any("COPYMODEPROBE" in p for p in explicit), f"saw {seen}")

    # The same envelope must not leak through if passthrough is off: that is
    # the silent failure grok doctor is reporting today. Set both the global
    # default and this window — a window created while it was on keeps a local
    # copy that -wg alone would not change.
    tmux("set-option", "-wg", "allow-passthrough", "off")
    tmux("set-option", "-w", "allow-passthrough", "off")
    dropped = base64.b64encode(b"DCSDROPPED")
    with open(pane_tty, "wb") as fh:
        fh.write(b"\x1bPtmux;\x1b\x1b]52;c;" + dropped + b"\x07\x1b\\")
    time.sleep(0.5)
    seen = copies(term.snapshot())
    failures += check("DCS-wrapped OSC 52 is dropped when passthrough is off",
                      ("c", "DCSDROPPED") not in seen, f"saw {seen}")
finally:
    os.kill(pid, 15)
    # Reap it: an orphan holding the pty keeps a CI step alive after we exit.
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass
    tmux("kill-server", capture=False)

sys.exit(1 if failures else 0)
