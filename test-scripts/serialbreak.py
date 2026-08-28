#!/usr/bin/env python3
"""Reboot the Flip over serial, hold it at the U-Boot prompt, run commands there.

serialcon.py sends its payload once at open and then only reads, which cannot
catch autoboot: the window is a second or two somewhere inside a boot whose
timing we do not control. This streams a keypress continuously from before the
reset until the prompt shows up, then stops so the spam does not land in
whatever comes next.

Usage:
  serialbreak.py [--baud N] [--seconds N] [--reboot-cmd CMD] [--no-break]
                 [--cmd "uboot command"]...

--no-break just captures, for a plain boot log. Without --reboot-cmd nothing is
sent to start with, so you can power the board on by hand instead.
"""
import argparse
import os
import re
import select
import sys
import termios
import time

PORT = "/dev/ttyUSB0"

# Only the prompt itself counts. "Hit any key to stop autoboot" is printed
# while the countdown is still running, so treating it as arrival stops the
# spam at the one moment it has to keep going.
# Anchored, because the driver's own "==> rtl8733bu_deinit" style logging
# appears during shutdown and would otherwise look like we had arrived.
PROMPT = re.compile(rb"(?m)^=>")


def open_port(baud):
    speed = getattr(termios, "B%d" % baud, None)
    if speed is None:
        sys.exit("unsupported baud %d" % baud)
    fd = os.open(PORT, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    _, _, cflag, _, _, _, cc = termios.tcgetattr(fd)
    cflag = termios.CS8 | termios.CREAD | termios.CLOCAL
    cc[termios.VMIN] = 0
    cc[termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, [0, 0, cflag, 0, speed, speed, cc])
    termios.tcflush(fd, termios.TCIFLUSH)
    return fd


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--baud", type=int, default=1500000)
    ap.add_argument("--seconds", type=float, default=90.0)
    ap.add_argument("--reboot-cmd", default=None)
    ap.add_argument("--no-break", action="store_true")
    ap.add_argument("--cmd", action="append", default=[])
    ap.add_argument("--cmd-gap", type=float, default=1.5)
    args = ap.parse_args()

    fd = open_port(args.baud)
    chunks = []
    at_prompt = False
    prompt_at = None
    sent = 0
    last_spam = 0.0

    try:
        if args.reboot_cmd:
            os.write(fd, (args.reboot_cmd + "\r\n").encode())

        deadline = time.time() + args.seconds
        while time.time() < deadline:
            now = time.time()

            if not at_prompt and not args.no_break and now - last_spam > 0.02:
                os.write(fd, b" ")
                last_spam = now

            if at_prompt and sent < len(args.cmd) and now - prompt_at > args.cmd_gap * (sent + 1):
                os.write(fd, (args.cmd[sent] + "\r\n").encode())
                sent += 1

            ready, _, _ = select.select([fd], [], [], 0.02)
            if not ready:
                continue
            try:
                data = os.read(fd, 4096)
            except BlockingIOError:
                continue
            if not data:
                continue
            chunks.append(data)

            if not at_prompt and PROMPT.search(b"".join(chunks[-8:])):
                at_prompt = True
                prompt_at = time.time()
                # A bare newline settles the prompt after the spam.
                os.write(fd, b"\r\n")

            if at_prompt and sent >= len(args.cmd) and args.cmd:
                # Give the last command room to finish, then stop early.
                if time.time() - prompt_at > args.cmd_gap * (sent + 2):
                    break
    finally:
        os.close(fd)

    out = b"".join(chunks).decode("utf-8", "replace")
    sys.stdout.write(out)
    sys.stdout.write("\n--- %d bytes, prompt=%s ---\n" % (len(out), at_prompt))


if __name__ == "__main__":
    main()
