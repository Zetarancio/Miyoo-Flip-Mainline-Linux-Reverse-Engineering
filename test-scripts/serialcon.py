#!/usr/bin/env python3
"""Minimal read/write helper for the Miyoo Flip serial console.

Usage: serialcon.py [baud] [seconds] [command-to-send]

No pyserial on this host, so termios does the work directly.
"""
import os
import select
import sys
import termios
import time

PORT = "/dev/ttyUSB0"

baud = int(sys.argv[1]) if len(sys.argv) > 1 else 1500000
duration = float(sys.argv[2]) if len(sys.argv) > 2 else 8.0
send = sys.argv[3] if len(sys.argv) > 3 else None

speed = getattr(termios, "B%d" % baud, None)
if speed is None:
    sys.exit("unsupported baud %d" % baud)

fd = os.open(PORT, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
try:
    iflag, oflag, cflag, lflag, _, _, cc = termios.tcgetattr(fd)
    cflag = termios.CS8 | termios.CREAD | termios.CLOCAL
    cc[termios.VMIN] = 0
    cc[termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, [0, 0, cflag, 0, speed, speed, cc])
    termios.tcflush(fd, termios.TCIFLUSH)

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
