#!/bin/sh
#
# write-preloader-mtd.sh — Pure shell: write preloader.img to internal SPI NAND
#
# Uses Busybox flash_eraseall + nandwrite on the MTD "preloader" partition
# (first 2 MiB of SPI NAND). No C binary.
#
# Intended for Miyoo Flip images from github.com/Zetarancio/distribution branch
# "flip" (GitHub Actions), which expose the "preloader" MTD partition.
#
# Usage (as root):
#   Copy this script and preloader.img into the same folder, then run:
#     ./write-preloader-mtd.sh
#   Optional: ./write-preloader-mtd.sh /path/to/other.img
#
# Obtain preloader.img from a full SPI dump (not from miyoo355_fw OTA):
#   ./extract-preloader-from-spi-dump.sh spi_*.img

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
	echo "ERROR: Must run as root." >&2
	exit 1
fi

if [ $# -ge 1 ]; then
	IMG="$1"
else
	IMG="$SCRIPT_DIR/preloader.img"
fi

if [ ! -f "$IMG" ]; then
	echo "ERROR: Preloader image not found: $IMG" >&2
	echo "Place preloader.img in the same folder as this script ($SCRIPT_DIR)" >&2
	echo "or pass the path: $0 /path/to/preloader.img" >&2
	exit 1
fi

IMG_SIZE=$(stat -c%s "$IMG" 2>/dev/null || stat -f%z "$IMG" 2>/dev/null)
MAX=2097152
if [ "$IMG_SIZE" -gt "$MAX" ]; then
	echo "ERROR: Image too large ($IMG_SIZE bytes, max $MAX)" >&2
	exit 1
fi
if [ "$IMG_SIZE" -eq 0 ]; then
	echo "ERROR: Image is empty" >&2
	exit 1
fi

PRELOADER_CHR=
if [ -c /dev/mtd/by-name/preloader ]; then
	PRELOADER_CHR=/dev/mtd/by-name/preloader
else
	n=$(grep '"preloader"' /proc/mtd 2>/dev/null | head -n1 | cut -d: -f1)
	if [ -n "$n" ] && [ -c "/dev/$n" ]; then
		PRELOADER_CHR="/dev/$n"
	fi
fi

if [ -z "$PRELOADER_CHR" ]; then
	echo "ERROR: No MTD device \"preloader\"." >&2
	echo "Use a current Miyoo Flip image from github.com/Zetarancio/distribution (branch flip)." >&2
	exit 1
fi

echo "============================================"
echo "  Write preloader (MTD, shell only)"
echo "============================================"
echo ""
echo "Image:  $IMG ($IMG_SIZE bytes)"
echo "Device: $PRELOADER_CHR"
echo ""
echo "Press Ctrl+C within 5 seconds to cancel..."
sleep 5

echo "Erasing (flash_eraseall) ..."
flash_eraseall "$PRELOADER_CHR"

echo "Writing (nandwrite -p) ..."
nandwrite -p "$PRELOADER_CHR" "$IMG"

echo ""
echo "Done. Reboot to boot from internal SPI NAND."
