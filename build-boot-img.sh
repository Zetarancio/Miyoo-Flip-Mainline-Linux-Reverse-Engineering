#!/bin/bash
# Build Android-format boot.img from Image (or Image.lz4) + DTB for flashing to stock boot partition.
# U-Boot's boot_android expects this format on the "boot" MTD partition.
# The boot partition is 38 MB; if Image is large (~37 MB), the DTB would sit past the partition.
# Use Image.lz4 (LZ4-compressed kernel) so the whole image fits and U-Boot can decompress on load.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/output}"
# Default BOOT_IMG to output dir so "make shell" + ./build-boot-img.sh writes to host-mounted output/ (same as make boot-img)
BOOT_IMG="${BOOT_IMG:-$OUTPUT_DIR/boot.img}"

# Prefer LZ4 kernel so boot image fits in 38 MB partition (kernel + DTB).
# If Image is newer than Image.lz4 (or Image.lz4 missing), regenerate Image.lz4 from Image
# so boot.img always uses the kernel from the last build (avoids stale Image.lz4).
if [ -f "$OUTPUT_DIR/Image" ]; then
    IMAGE_MTIME=$(stat -c %Y "$OUTPUT_DIR/Image" 2>/dev/null || stat -f %m "$OUTPUT_DIR/Image" 2>/dev/null)
    LZ4_MTIME=$(stat -c %Y "$OUTPUT_DIR/Image.lz4" 2>/dev/null || stat -f %m "$OUTPUT_DIR/Image.lz4" 2>/dev/null || echo 0)
    if [ ! -f "$OUTPUT_DIR/Image.lz4" ] || [ "$IMAGE_MTIME" -gt "$LZ4_MTIME" ]; then
        if command -v lz4 >/dev/null 2>&1; then
            echo "Regenerating Image.lz4 from Image (Image is newer or Image.lz4 missing)."
            lz4 -f "$OUTPUT_DIR/Image" "$OUTPUT_DIR/Image.lz4"
        else
            echo "Error: Image is newer than Image.lz4 (or Image.lz4 missing). Install lz4 so this script can pack the latest kernel (e.g. apt install lz4)."
            exit 1
        fi
    fi
fi
if [ -f "$OUTPUT_DIR/Image.lz4" ]; then
    KERNEL_FILE="$OUTPUT_DIR/Image.lz4"
    echo "Using LZ4 kernel: $KERNEL_FILE"
elif [ -f "$OUTPUT_DIR/Image" ]; then
    KERNEL_FILE="$OUTPUT_DIR/Image"
    KERNEL_SIZE=$(stat -c%s "$OUTPUT_DIR/Image" 2>/dev/null || stat -f%z "$OUTPUT_DIR/Image" 2>/dev/null)
    # Boot partition 38 MB; need room for header + kernel + DTB (~40 KB)
    if [ -n "$KERNEL_SIZE" ] && [ "$KERNEL_SIZE" -gt 36000000 ]; then
        echo "Warning: Image is ${KERNEL_SIZE} bytes (~$((KERNEL_SIZE/1024/1024)) MB). Boot partition is 38 MB; DTB would be past the end."
        echo "Install lz4 and re-run so this script can create Image.lz4 from Image."
    fi
else
    echo "Error: Need $OUTPUT_DIR/Image or $OUTPUT_DIR/Image.lz4, and $OUTPUT_DIR/rk3566-miyoo-flip.dtb. Run the build first."
    exit 1
fi

if [ ! -f "$OUTPUT_DIR/rk3566-miyoo-flip.dtb" ]; then
    echo "Error: Need $OUTPUT_DIR/rk3566-miyoo-flip.dtb. Run the build first."
    exit 1
fi
# Warn if DTB contains 0xffffffff in structure block (causes U-Boot FDT_ERR_BADSTRUCTURE)
if python3 -c "
import struct, sys
with open('$OUTPUT_DIR/rk3566-miyoo-flip.dtb', 'rb') as f: d = f.read()
off = struct.unpack('>I', d[8:12])[0]
size = struct.unpack('>I', d[36:40])[0]
block = d[off:off+size]
for i in range(0, len(block)-3, 4):
    if struct.unpack('>I', block[i:i+4])[0] == 0xffffffff:
        sys.exit(1)
" 2>/dev/null; then
    : # DTB OK
else
    echo "Warning: DTB contains unresolved phandle (0xffffffff). U-Boot may report FDT_ERR_BADSTRUCTURE."
    echo "Run ./rebuild-dtb-for-uboot.sh (after building U-Boot) and re-run this script."
fi

# Empty ramdisk (some mkbootimg require a ramdisk file)
EMPTY_RAMDISK="$SCRIPT_DIR/empty_ramdisk"
if [ ! -f "$EMPTY_RAMDISK" ]; then
    touch "$EMPTY_RAMDISK"
    echo "Created empty ramdisk: $EMPTY_RAMDISK"
fi

# Same layout as stock and Extra/repack_boot.img/run.sh: header v0, second = DTB.
# Refs: https://steward-fu.github.io/website/handheld/miyoo_flip_repack_boot.htm
BOARD_KERNEL_BASE=0x10000000
BOARD_PAGE_SIZE=2048
BOARD_KERNEL_OFFSET=0x00008000
BOARD_RAMDISK_OFFSET=0xf0000000
BOARD_SECOND_OFFSET=0x00f00000
BOARD_TAGS_OFFSET=0x00000100
BOARD_HASH_TYPE=sha1

# 1) Prefer mkbootimg from Extra/miyoo-flip-main when available (same as stock repack)
EXTRA_DIR="${EXTRA_DIR:-$SCRIPT_DIR/Extra}"
ROCKCHIP_MKBOOTIMG=""
for candidate in \
    "$EXTRA_DIR/miyoo-flip-main/u-boot/scripts/mkbootimg" \
    "$EXTRA_DIR/miyoo-flip-main/scripts/mkbootimg" \
    "$EXTRA_DIR/miyoo-flip-main/mkbootimg"; do
    if [ -f "$candidate" ]; then
        ROCKCHIP_MKBOOTIMG="$candidate"
        break
    fi
done
if [ -n "$ROCKCHIP_MKBOOTIMG" ]; then
    echo "Using mkbootimg from Extra/miyoo-flip-main: $ROCKCHIP_MKBOOTIMG"
    echo "Building boot.img (header v0, second=DTB)..."
    if python3 "$ROCKCHIP_MKBOOTIMG" \
        --kernel "$KERNEL_FILE" \
        --second "$OUTPUT_DIR/rk3566-miyoo-flip.dtb" \
        --ramdisk "$EMPTY_RAMDISK" \
        --base "$BOARD_KERNEL_BASE" --kernel_offset "$BOARD_KERNEL_OFFSET" \
        --ramdisk_offset "$BOARD_RAMDISK_OFFSET" --second_offset "$BOARD_SECOND_OFFSET" \
        --tags_offset "$BOARD_TAGS_OFFSET" --pagesize "$BOARD_PAGE_SIZE" \
        --header_version 0 \
        -o "$BOOT_IMG"; then
        : # success
    else
        echo "Rockchip mkbootimg failed, falling back to built-in mkbootimg."
        ROCKCHIP_MKBOOTIMG=""
    fi
fi

# 2) Otherwise use container/host mkbootimg (our tools/mkbootimg.py: v0, second=DTB)
if [ -z "$ROCKCHIP_MKBOOTIMG" ]; then
    if command -v mkbootimg >/dev/null 2>&1 && (mkbootimg --help 2>&1 || true) | grep -q -e '--dtb'; then
        echo "Building boot.img with mkbootimg (--dtb, stock layout)..."
        mkbootimg --kernel "$KERNEL_FILE" \
            --ramdisk "$EMPTY_RAMDISK" \
            --dtb "$OUTPUT_DIR/rk3566-miyoo-flip.dtb" \
            --pagesize "$BOARD_PAGE_SIZE" \
            --base "$BOARD_KERNEL_BASE" --kernel_offset "$BOARD_KERNEL_OFFSET" \
            --ramdisk_offset "$BOARD_RAMDISK_OFFSET" --second_offset "$BOARD_SECOND_OFFSET" \
            --output "$BOOT_IMG"
    elif command -v mkbootimg.py >/dev/null 2>&1 && mkbootimg.py --help 2>&1 | grep -q -e '--dtb'; then
        echo "Building boot.img with mkbootimg.py (v0, second=DTB, same as stock repack)..."
        mkbootimg.py --kernel "$KERNEL_FILE" --ramdisk "$EMPTY_RAMDISK" \
            --dtb "$OUTPUT_DIR/rk3566-miyoo-flip.dtb" \
            --pagesize "$BOARD_PAGE_SIZE" \
            --base "$BOARD_KERNEL_BASE" --kernel_offset "$BOARD_KERNEL_OFFSET" \
            --ramdisk_offset "$BOARD_RAMDISK_OFFSET" --second_offset "$BOARD_SECOND_OFFSET" \
            --output "$BOOT_IMG"
    else
        echo "No mkbootimg found. Install one or ensure Extra is mounted for Rockchip mkbootimg. See FLASH-STOCK-PARTITIONS.md."
        exit 1
    fi
fi

# DTB offset must match U-Boot: page_size + ALIGN(kernel_size, page_size) with page_size 2048.
# Use kernel_size from the boot image header (offset 8, 4 bytes LE) so we match U-Boot exactly.
HDR_KERNEL_SIZE=$(od -An -t u4 -N 4 -j 8 "$BOOT_IMG" 2>/dev/null | tr -d ' ')
[ -z "$HDR_KERNEL_SIZE" ] && HDR_KERNEL_SIZE=$(stat -c%s "$KERNEL_FILE" 2>/dev/null || stat -f%z "$KERNEL_FILE" 2>/dev/null)
# ALIGN(k, 2048) = ((k+2047)&~2047) in U-Boot; same as ((k+2047)/2048)*2048 in integer math
ALIGNED_KERNEL=$(( ((HDR_KERNEL_SIZE + 2047) / 2048) * 2048 ))
DTB_OFFSET=$(( 2048 + ALIGNED_KERNEL ))
BOOT_IMG_SIZE=$(stat -c%s "$BOOT_IMG" 2>/dev/null || stat -f%z "$BOOT_IMG" 2>/dev/null)
FDT_MAGIC=$(xxd -s "$DTB_OFFSET" -l 4 -p "$BOOT_IMG" 2>/dev/null | tr -d '\n')
# FDT magic is 0xd00dfeed (big) or 0xedfe0dd0 (little) in hex bytes
if [ "$BOOT_IMG_SIZE" -lt $(( DTB_OFFSET + 1000 )) ] || { [ "$FDT_MAGIC" != "d00dfeed" ] && [ "$FDT_MAGIC" != "edfe0dd0" ]; }; then
    echo "Warning: mkbootimg did not include DTB or used different alignment. Writing DTB at offset $DTB_OFFSET (header kernel_size=$HDR_KERNEL_SIZE)..."
    DTB_FILE="$OUTPUT_DIR/rk3566-miyoo-flip.dtb"
    DTB_SIZE=$(stat -c%s "$DTB_FILE" 2>/dev/null || stat -f%z "$DTB_FILE" 2>/dev/null)
    NEED_SIZE=$(( DTB_OFFSET + DTB_SIZE ))
    if [ "$BOOT_IMG_SIZE" -lt "$NEED_SIZE" ]; then
        PAD=$(( NEED_SIZE - BOOT_IMG_SIZE ))
        dd if=/dev/zero bs=1 count="$PAD" 2>/dev/null >> "$BOOT_IMG"
    fi
    dd if="$DTB_FILE" of="$BOOT_IMG" bs=1 seek="$DTB_OFFSET" conv=notrunc 2>/dev/null
    echo "Wrote DTB at offset $DTB_OFFSET. Size: $(stat -c%s "$BOOT_IMG" 2>/dev/null || stat -f%z "$BOOT_IMG") bytes."
fi

# Final check
FDT_MAGIC=$(xxd -s "$DTB_OFFSET" -l 4 -p "$BOOT_IMG" 2>/dev/null | tr -d '\n')
if [ "$FDT_MAGIC" = "d00dfeed" ] || [ "$FDT_MAGIC" = "edfe0dd0" ]; then
    echo "Created: $BOOT_IMG (DTB at offset $DTB_OFFSET, FDT magic OK)"
else
    echo "Created: $BOOT_IMG"
    echo "WARNING: DTB not found at offset $DTB_OFFSET (first 4 bytes: $FDT_MAGIC). U-Boot may fail to load DTB."
fi

# Pad to boot partition size (38 MB) so xrock "flash write" accepts the image (many tools require exact partition size)
BOOT_PART_SIZE=$(( 38 * 1024 * 1024 ))
BOOT_IMG_SIZE=$(stat -c%s "$BOOT_IMG" 2>/dev/null || stat -f%z "$BOOT_IMG" 2>/dev/null)
if [ "$BOOT_IMG_SIZE" -lt "$BOOT_PART_SIZE" ]; then
    PAD=$(( BOOT_PART_SIZE - BOOT_IMG_SIZE ))
    # Use 64K blocks so padding finishes in seconds (bs=1 would take many minutes for ~18 MB)
    DD_BS=65536
    DD_COUNT=$(( PAD / DD_BS ))
    DD_REM=$(( PAD % DD_BS ))
    if [ "$DD_COUNT" -gt 0 ]; then
        dd if=/dev/zero bs=$DD_BS count=$DD_COUNT 2>/dev/null >> "$BOOT_IMG"
    fi
    if [ "$DD_REM" -gt 0 ]; then
        dd if=/dev/zero bs=1 count=$DD_REM 2>/dev/null >> "$BOOT_IMG"
    fi
    echo "Padded to partition size: $BOOT_PART_SIZE bytes (for xrock flash write)."
elif [ "$BOOT_IMG_SIZE" -gt "$BOOT_PART_SIZE" ]; then
    echo "Warning: boot.img ($BOOT_IMG_SIZE) exceeds boot partition ($BOOT_PART_SIZE). xrock may refuse to flash."
fi

echo "Next: flash to boot partition (sector 14336) and rootfs to rootfs (sector 92160). See FLASH-STOCK-PARTITIONS.md."
exit 0
