#!/usr/bin/env python3
"""Minimal read/write helper for the Miyoo Flip serial console.

Usage: serialcon.py [baud] [seconds] [command-to-send]

No pyserial on this host, so termios does the work directly.
1500000 is not always a termios.Bxxxx constant; we fall back to stty.
"""
import os
import select
import subprocess
import sys
import termios
import time

PORT = "/dev/ttyUSB0"


def open_port(baud, port=PORT):
    """NOTES §1: stty the custom baud, then open. Do not use termios.B1500000.

    On this host B1500000 may exist as the integer 1500000. Passing that to
    tcsetattr still yields 0 bytes; stty sets BOTHER correctly.
    """
    subprocess.check_call(
        [
            "stty",
            "-F",
            port,
            str(baud),
            "raw",
            "-echo",
            "-ixon",
            "-ixoff",
            "cs8",
            "-cstopb",
            "-parenb",
            "clocal",
        ],
        timeout=5,
    )
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    _, _, cflag, _, ispeed, ospeed, cc = termios.tcgetattr(fd)
    cflag = termios.CS8 | termios.CREAD | termios.CLOCAL
    cc[termios.VMIN] = 0
    cc[termios.VTIME] = 0
    # Keep ispeed/ospeed from stty. Do not overwrite with B1500000.
    termios.tcsetattr(fd, termios.TCSANOW, [0, 0, cflag, 0, ispeed, ospeed, cc])
    termios.tcflush(fd, termios.TCIFLUSH)
    return fd


baud = int(sys.argv[1]) if len(sys.argv) > 1 else 1500000
duration = float(sys.argv[2]) if len(sys.argv) > 2 else 8.0
send = sys.argv[3] if len(sys.argv) > 3 else None

fd = open_port(baud)
try:
    if send is not None:
        # Interpret escapes so control characters (\x03, \x04) can be sent.
        payload = send.encode().decode("unicode_escape")
        if not payload.endswith("\x03"):
            payload += "\r\n"
        os.write(fd, payload.encode("latin-1"))

    deadline = time.time() + duration
    chunks = []
    while time.time() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.2)
        if not ready:
            continue
        try:
            data = os.read(fd, 4096)
        except BlockingIOError:
            continue
        if data:
            chunks.append(data)
finally:
    os.close(fd)

out = b"".join(chunks).decode("utf-8", "replace")
sys.stdout.write(out)
sys.stdout.write("\n--- %d bytes at %d baud ---\n" % (len(out), baud))
