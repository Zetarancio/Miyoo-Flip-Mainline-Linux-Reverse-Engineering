#!/usr/bin/env python3
"""Build a miyoo355_fw.img that runs a diagnostic script on stock instead of
updating anything.

Stock's `miyoo_fw_update` does exactly this, on both 20241119 and 20250527:

    dd if=miyoo355_fw.img of=/tmp/miyoo_fw_version.txt bs=128 count=1
    dd if=miyoo355_fw.img of=/tmp/miyoo_update.sh bs=512 skip=1 count=8
    chmod 777 /tmp/miyoo_update.sh
    /tmp/miyoo_update.sh&

So sector 0 is a text descriptor and sector 1 is an arbitrary root shell
script, at most 8 sectors (4096 B). The script is copied to tmpfs, so the FAT
volume's lack of execute bits does not matter.

On 20241119 `runmiyoo.sh` runs the updater whenever the file is present, with
no version comparison at all; 20250527 added the version gate. The descriptor
here declares a version different from either, so both firmwares proceed.

    mkdiagfw.py miyoo355_fw.img
"""

import sys

SECTOR = 512
MAX_SCRIPT = 8 * SECTOR

DESCRIPTOR = "model:miyoo355\nversion:29990101000000\n"

SCRIPT = r"""#!/bin/sh
# Diagnostic payload — collects why stock stalls, writes to the SD card.
# Touches /tmp/fwupdate_done at the end so stock's updater stops waiting.

DIR=
for d in /media/sdcard0 /media/sdcard1 /mnt/sdcard; do
	[ -f "$d/miyoo355_fw.img" ] && DIR="$d" && break
done
[ -z "$DIR" ] && DIR=/tmp

L="$DIR/stock-diag.txt"

{
	echo "### stock diagnostic $(date 2>/dev/null)"
	echo "uptime: $(cat /proc/uptime)"
	echo "version: $(cat /usr/miyoo/version 2>/dev/null)"
	echo "card dir: $DIR"
	echo
	echo "=== /proc/cmdline ==="; cat /proc/cmdline
	echo; echo "=== /proc/mounts ==="; cat /proc/mounts
	echo; echo "=== /proc/mtd ==="; cat /proc/mtd 2>/dev/null
	echo; echo "=== block devices ==="; ls -la /dev/mmcblk* /dev/mtd* 2>/dev/null
	echo; echo "=== processes ==="; ps
	echo; echo "=== runee.log ==="; cat /tmp/runee.log 2>/dev/null
	echo; echo "=== /tmp ==="; ls -la /tmp
	echo; echo "=== free ==="; free
	echo; echo "=== jsonval runee ==="; /usr/miyoo/bin/jsonval runee 2>&1
	echo; echo "=== joy_type ==="; cat /sys/class/miyooio_chr_dev/joy_type 2>&1
	echo; echo "=== drm status ==="
	for s in /sys/class/drm/card0-*/status; do echo "$s: $(cat $s 2>/dev/null)"; done
	echo; echo "=== dmesg ==="; dmesg
} >"$L" 2>&1

sync

# Run MainUI ourselves and capture what it says. It is the thing that never
# draws, so its stderr is the point of this whole exercise.
M="$DIR/mainui-out.txt"
cd /usr/miyoo/bin
LD_LIBRARY_PATH=/usr/miyoo/lib ./MainUI >"$M" 2>&1 &
MPID=$!

n=0
while [ $n -lt 20 ]; do
	sleep 1
	n=$((n + 1))
	kill -0 $MPID 2>/dev/null || break
done

if kill -0 $MPID 2>/dev/null; then
	echo "--- still running after ${n}s, killing ---" >>"$M"
	echo "--- /proc/$MPID/wchan: $(cat /proc/$MPID/wchan 2>/dev/null) ---" >>"$M"
	echo "--- /proc/$MPID/status ---" >>"$M"
	cat /proc/$MPID/status >>"$M" 2>&1
	kill -9 $MPID 2>/dev/null
else
	echo "--- exited on its own after ${n}s ---" >>"$M"
fi

{
	echo; echo "=== processes after MainUI attempt ==="; ps
	echo; echo "=== new dmesg tail ==="; dmesg | tail -40
} >>"$M" 2>&1

sync
echo 100 >/tmp/fwupdate_progress
touch /tmp/fwupdate_done
sync
"""


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[-1].strip(), file=sys.stderr)
        return 2

    script = SCRIPT.encode()
    if len(script) > MAX_SCRIPT:
        print(f"script is {len(script)} B, limit is {MAX_SCRIPT} B", file=sys.stderr)
        return 1

    img = bytearray()
    img += DESCRIPTOR.encode().ljust(SECTOR, b"\0")
    img += script.ljust(MAX_SCRIPT, b"\0")

    with open(sys.argv[1], "wb") as f:
        f.write(img)

    print(f"wrote {sys.argv[1]}  ({len(img)} bytes)")
    print(f"  descriptor : {DESCRIPTOR.strip().splitlines()}")
    print(f"  script     : {len(script)} B of {MAX_SCRIPT} B")
    return 0


if __name__ == "__main__":
    sys.exit(main())
