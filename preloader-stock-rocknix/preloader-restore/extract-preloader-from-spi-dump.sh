#!/bin/sh
# Extract the first 2 MiB (preloader / IDBLOCK region) from a full SPI NAND dump.
# Card OTA packages (miyoo355_fw.img) do NOT contain this region — use a raw full dump.
#
# Usage:
#   ./extract-preloader-from-spi-dump.sh spi_20241119160817.img preloader.img
set -e
if [ "$#" -lt 2 ]; then
	echo "Usage: $0 <full_spi_dump.img> <preloader_out.img>" >&2
	exit 1
fi
dd if="$1" of="$2" bs=512 count=4096 conv=fsync
echo "Wrote $2 (4096 × 512 bytes = 2 MiB from offset 0)."
