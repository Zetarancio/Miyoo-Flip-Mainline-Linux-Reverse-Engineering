#!/bin/sh
#
# Miyoo Flip — CHECK the preloader (read-only, writes nothing)
#
# Pick this file in a file manager and choose Execute, or run it from the
# ROCKNIX Ports menu. Safe to run at any time: it reads the current
# preloader, reports what it is, and stops before the erase.
#
# Use it to answer, without risking anything:
#   - is this board recognised (model, SoC, NAND geometry)?
#   - is the preloader stock, patched, or erased?
#   - does this unit's DRAM blob match the bundled images, i.e. is
#     install-multiboot.sh safe here?
#
# It is the same code path as install, stopped before the first write, so
# a clean run here means install has already passed every gate.
#
# A copy of the current preloader is left beside this script as
# preloader-backup-<date>.img — but only if it is worth keeping. An
# erased region reads back as 2 MiB of 0xff, which is not a restore
# point, so that copy is discarded rather than left here implying it is.
#
# Note the copy is not automatically an undo either: after installing,
# the newest backup IS the patched preloader, so restore-preloader.sh
# deliberately skips it and falls back to the bundled stock image.
#
# Method by apommel — https://github.com/apommel/baseos-my355
#
# Output is echoed and also written to backup-log.txt next to this
# script, which matters when a launcher shows no console.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$SCRIPT_DIR/launch.sh" ]; then
	echo "ERROR: launch.sh is missing from $SCRIPT_DIR"
	echo "Copy the whole apommel-multiboot folder, not just this file."
	sleep 10
	exit 1
fi

exec sh "$SCRIPT_DIR/launch.sh" backup "$@"
