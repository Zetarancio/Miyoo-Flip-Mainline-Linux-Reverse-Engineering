#!/bin/bash
# Pack Buildroot target into rootfs.squashfs for flashing.
# Run after build-rootfs, and after build-wifi / build-mali to include out-of-tree modules.
# Similar to build-boot-img.sh for the boot partition—this recreates the rootfs image.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/output}"
BUILDROOT_DIR="${BUILDROOT_DIR:-$SCRIPT_DIR/buildroot}"
BR_TARGET="$BUILDROOT_DIR/output/target"

if [ ! -d "$BR_TARGET" ]; then
    echo "Error: Buildroot target not found at $BR_TARGET"
    echo "Run 'make build-rootfs' first."
    exit 1
fi

echo "Packing rootfs from $BR_TARGET..."
mkdir -p "$OUTPUT_DIR"

if command -v mksquashfs >/dev/null 2>&1; then
    mksquashfs "$BR_TARGET" "$OUTPUT_DIR/rootfs.squashfs" \
        -noappend -comp gzip -all-root -quiet \
        -e "THIS_IS_NOT_YOUR_ROOT_FILESYSTEM" 2>/dev/null || true
    echo "  Created: $OUTPUT_DIR/rootfs.squashfs ($(du -h "$OUTPUT_DIR/rootfs.squashfs" | cut -f1))"
else
    echo "Error: mksquashfs not found. Install squashfs-tools."
    exit 1
fi

echo ""
echo "Next: flash rootfs partition with output/rootfs.squashfs. See docs/FLASH-STOCK-PARTITIONS.md."
exit 0
