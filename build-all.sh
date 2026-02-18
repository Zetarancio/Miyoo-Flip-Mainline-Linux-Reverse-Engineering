#!/bin/bash
# Main build orchestration script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)

echo "=========================================="
echo "Miyoo Flip Build System (Buildroot-based)"
echo "=========================================="

# Step 1: Build kernel (uses static rk3566-miyoo-flip.dts from project root)
echo ""
echo "Step 1: Building mainline Linux kernel..."
bash "$SCRIPT_DIR/build-kernel.sh"

# Step 2: Build U-Boot
echo ""
echo "Step 2: Building U-Boot..."
bash "$SCRIPT_DIR/build-uboot.sh"

# Step 2.5: Rebuild DTB with U-Boot's dtc so the blob is compliant with U-Boot's libfdt (no FDT_ERR_BADSTRUCTURE)
# Kernel DTS uses #include <dt-bindings/...> and #include "rk3566.dtsi"; we must preprocess like the kernel does.
# Prefer host path so Step 2.5 runs when building from project root (not only in Docker).
KERNEL_DIR="${KERNEL_DIR:-$SCRIPT_DIR/kernel}"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/output}"
# Prefer MIYOO_BUILD (e.g. Docker) then in-tree U-Boot so Step 2.5 runs on host too
UBOOT_DTC="${UBOOT_DTC:-${MIYOO_BUILD:-$SCRIPT_DIR/Extra/miyoo-flip-main}/u-boot/scripts/dtc/dtc}"
DTS_FILE="$KERNEL_DIR/arch/arm64/boot/dts/rockchip/rk3566-miyoo-flip.dts"
if [ -x "$UBOOT_DTC" ] && [ -f "$DTS_FILE" ]; then
    echo ""
    echo "Step 2.5: Rebuilding DTB with U-Boot's dtc (compliant with U-Boot and device expectations)..."
    DTS_PREPROC="$OUTPUT_DIR/rk3566-miyoo-flip.dts.preproc"
    HOST_CPP="${HOST_CPP:-gcc -E}"
    $HOST_CPP -nostdinc -I "$KERNEL_DIR/include" -I "$KERNEL_DIR/arch/arm64/boot/dts" \
        -undef -D__DTS__ -x assembler-with-cpp "$DTS_FILE" -o "$DTS_PREPROC"
    # U-Boot dtc 1.4.x does not support /omit-if-no-ref/ (newer devicetree directive); strip those lines
    sed -i '/^[[:space:]]*\/omit-if-no-ref\/[[:space:]]*$/d' "$DTS_PREPROC"
    # Avoid /plugin/ so phandle refs are resolved (0xffffffff in blob causes U-Boot FDT_ERR_BADSTRUCTURE)
    sed -i '/\/plugin\//d' "$DTS_PREPROC"
    # Build to temp file so we can keep kernel DTB if U-Boot dtc output is invalid
    DTB_TMP="$OUTPUT_DIR/rk3566-miyoo-flip.dtb.step25.$$"
    # Force version 17 and add padding so U-Boot libfdt can fix up memory without NOSPACE
    "$UBOOT_DTC" -I dts -O dtb -V 17 -p 1024 -o "$DTB_TMP" "$DTS_PREPROC"
    rm -f "$DTS_PREPROC"
    # If DTB has no 0xffffffff in structure block, use it; else keep kernel DTB and warn (build continues)
    if python3 -c "
import struct, sys
with open('$DTB_TMP', 'rb') as f: d = f.read()
off = struct.unpack('>I', d[8:12])[0]
size = struct.unpack('>I', d[36:40])[0]
block = d[off:off+size]
for i in range(0, len(block)-3, 4):
    if struct.unpack('>I', block[i:i+4])[0] == 0xffffffff:
        sys.exit(1)
" 2>/dev/null; then
        mv -f "$DTB_TMP" "$OUTPUT_DIR/rk3566-miyoo-flip.dtb"
        echo "DTB rebuilt: $OUTPUT_DIR/rk3566-miyoo-flip.dtb"
    else
        rm -f "$DTB_TMP"
        echo "Warning: U-Boot dtc produced DTB with 0xffffffff (unresolved phandle). Keeping kernel-built DTB."
        echo "         Boot may show FDT_ERR_BADSTRUCTURE. To fix: ensure no /plugin/ in preproc or fix DTS &refs."
    fi
else
    [ ! -x "$UBOOT_DTC" ] && echo "Warning: U-Boot dtc not found; using kernel-built DTB (may trigger FDT_ERR_BADSTRUCTURE in U-Boot)."
    [ -x "$UBOOT_DTC" ] && [ ! -f "$DTS_FILE" ] && echo "Warning: DTS not found at $DTS_FILE; skipping Step 2.5."
fi

# Step 3: Build rootfs with Buildroot
echo ""
echo "Step 3: Building minimal rootfs with Buildroot..."
bash "$SCRIPT_DIR/build-rootfs-buildroot.sh"

# Step 4: Build RTL8733BU WiFi driver + BT firmware
echo ""
echo "Step 4: Building RTL8733BU WiFi/BT driver..."
if bash "$SCRIPT_DIR/build-rtl8733bu.sh"; then
    echo "RTL8733BU WiFi/BT driver built successfully"
else
    echo "Warning: RTL8733BU driver build failed (WiFi may not work)"
    echo "You can build it separately later with: make build-wifi"
fi

# Summary
echo ""
echo "=========================================="
echo "Build Complete!"
echo "=========================================="
echo "Output files in /build/output/:"
ls -lh /build/output/ 2>/dev/null || echo "  (check build logs for any errors)"
echo ""
echo "Next steps:"
echo "  1. Flash uboot.img to device (optional)"
echo "  2. Create SD card with:"
echo "     - FAT32 partition (boot) with Image and .dtb"
echo "     - ext4 partition (root) - extract rootfs.tar to it"
echo "  3. Boot from SD card"
echo ""
echo "Files:"
echo "  - Image: Kernel image"
echo "  - rk3566-miyoo-flip.dtb: Device tree blob"
echo "  - uboot.img: U-Boot bootloader"
echo "  - rootfs.squashfs: For MTD flash (compressed, read-only)"
echo "  - rootfs.ext4: For SD card testing (ext4 image)"
echo "  - rootfs.tar: Rootfs tarball (extract to SD card partition)"
echo "  - modules/rtl8733bu.ko: WiFi driver module (if built)"
