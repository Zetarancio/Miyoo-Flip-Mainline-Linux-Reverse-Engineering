#!/bin/sh
#
# ROCKNIX Ports launcher — RESTORE the preloader. This one writes.
#
# Copy the files in this folder to /storage/roms/ports/ and they appear
# in the ROCKNIX "Ports" menu, so the tools can be run from the device
# UI with no SSH and no arguments.
#
# Undoes "2 Install": puts a stock preloader back, so the device boots
# stock from internal NAND and ignores the card again.
#
# The image is the newest valid backup in the app folder, or the bundled
# preloader-stock.img. A backup taken while the preloader was erased is
# 2 MiB of 0xff and is refused; so is the patched image itself, since
# restore has to mean undo.
#
# Method by apommel — https://github.com/apommel/baseos-my355

APP=
for d in /storage/games-external/App/apommel-multiboot \
	/storage/roms/App/apommel-multiboot \
	/storage/App/apommel-multiboot; do
	[ -f "$d/launch.sh" ] && APP=$d && break
done
if [ -z "$APP" ]; then
	F=$(find /storage /var/media -maxdepth 6 -name launch.sh \
		-path '*apommel-multiboot*' 2>/dev/null | head -n1)
	[ -n "$F" ] && APP=$(dirname "$F")
fi

if [ -z "$APP" ]; then
	echo "Could not find the apommel-multiboot folder on any card."
	sleep 10
	exit 1
fi

exec sh "$APP/restore-preloader.sh"
