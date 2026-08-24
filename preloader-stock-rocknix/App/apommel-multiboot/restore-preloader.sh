#!/bin/sh
#
# Miyoo Flip — RESTORE the preloader (undo SD multiboot)
#
# Pick this file in a file manager and choose Execute. It puts a stock
# preloader back, so the device boots stock from internal SPI NAND and
# SD multiboot is switched off.
#
# It is a thin wrapper around launch.sh, which does the real work:
# validate, back up, erase, write, verify, roll back on failure. Keep
# both files in the same folder.
#
# Image chosen, in this order:
#   1. a path given as the first argument
#   2. the newest VALID preloader-backup-*.img in this folder
#      (preferred: IDB entry 1 is DRAM init and belongs to this board)
#   3. the bundled preloader-stock.img
#
# A backup taken while the preloader was ERASED is 2 MiB of 0xff and is
# not a restore point. launch.sh detects those and refuses them.
#
# Writes only work where the preloader is an MTD node, i.e. on ROCKNIX
# (mtd0 = "preloader"). On stock it reports and writes nothing; see
# README.md in this folder.
#
# Output is echoed and also written to restore-log.txt next to this
# script, which matters when a file manager shows no console.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$SCRIPT_DIR/launch.sh" ]; then
	echo "ERROR: launch.sh is missing from $SCRIPT_DIR"
	echo "Copy the whole apommel-multiboot folder, not just this file."
	sleep 10
	exit 1
fi

exec sh "$SCRIPT_DIR/launch.sh" restore "$@"
