#!/bin/sh
#
# ROCKNIX Ports launcher — READ-ONLY CHECK. Writes nothing.
#
# Copy the files in this folder to /storage/roms/ports/ and they appear
# in the ROCKNIX "Ports" menu, so the tools can be run from the device
# UI with no SSH and no arguments.
#
# Run this one first. A clean result here means "2 Install" has already
# passed every safety gate.
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

exec sh "$APP/check-preloader.sh"
