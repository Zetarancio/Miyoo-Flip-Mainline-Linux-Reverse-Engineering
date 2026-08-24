#!/bin/sh
#
# Miyoo Flip — INSTALL SD multiboot (patch the preloader)
#
# Pick this file in a file manager and choose Execute. It writes the
# patched preloader, after which:
#   no card                      -> stock from internal SPI NAND
#   card with a bootable U-Boot  -> that OS from SD
#
# Same thing the launcher entry does (config.json runs launch.sh); this
# name just makes it obvious in a file listing next to
# restore-preloader.sh. Keep both beside launch.sh.
#
# Method by apommel — https://github.com/apommel/baseos-my355
#
# Writes only work where the preloader is an MTD node, i.e. on ROCKNIX
# (mtd0 = "preloader"). On stock it reports and writes nothing; see
# README.md in this folder.
#
# Output is echoed and also written to install-log.txt next to this
# script, which matters when a file manager shows no console.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$SCRIPT_DIR/launch.sh" ]; then
	echo "ERROR: launch.sh is missing from $SCRIPT_DIR"
	echo "Copy the whole apommel-multiboot folder, not just this file."
	sleep 10
	exit 1
fi

exec sh "$SCRIPT_DIR/launch.sh" install "$@"
