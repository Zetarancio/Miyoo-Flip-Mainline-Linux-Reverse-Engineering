#!/bin/bash
# Rebuild rk3566-miyoo-flip.dtb using U-Boot's dtc so the blob structure is
# compatible with U-Boot's libfdt (avoids FDT_ERR_BADSTRUCTURE and "no kernel output").
#
# Run on the HOST (not in Docker), from project root, after a kernel build:
#   ./rebuild-dtb-for-uboot.sh
# Requires: gcc (for preprocessing), python3, and U-Boot built so dtc exists at
#   Extra/miyoo-flip-main/u-boot/scripts/dtc/dtc
# If you get "command not found" for gcc, install build-essential. If CPP was
# set for cross-compilation (e.g. aarch64-linux-gnu-gcc), the script uses HOST_CPP
# (default gcc -E) for DTS preprocessing only.
#
# For a full image build (kernel + uboot + rootfs + DTB), use Docker: make build
# (Step 2.5 there rebuilds the DTB with U-Boot's dtc inside the container).
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL_DIR="${KERNEL_DIR:-$SCRIPT_DIR/kernel}"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/output}"
UBOOT_DTC="${UBOOT_DTC:-${MIYOO_BUILD:-$SCRIPT_DIR/Extra/miyoo-flip-main}/u-boot/scripts/dtc/dtc}"
DTS_FILE="$KERNEL_DIR/arch/arm64/boot/dts/rockchip/rk3566-miyoo-flip.dts"

if [ ! -f "$DTS_FILE" ]; then
    echo "Error: DTS not found at $DTS_FILE"
    echo "Set KERNEL_DIR if your kernel is elsewhere."
    exit 1
fi
if [ ! -x "$UBOOT_DTC" ]; then
    echo "Error: U-Boot dtc not found or not executable: $UBOOT_DTC"
    echo "Build U-Boot first (e.g. make -C Extra/miyoo-flip-main/u-boot rk3566)."
    exit 1
fi

echo "Rebuilding DTB with U-Boot's dtc for FDT compatibility..."
mkdir -p "$OUTPUT_DIR"
DTS_PREPROC="$OUTPUT_DIR/rk3566-miyoo-flip.dts.preproc"
# Use host preprocessor (DTS is arch-independent); avoid CPP from cross-build env
HOST_CPP="${HOST_CPP:-gcc -E}"
$HOST_CPP -nostdinc -I "$KERNEL_DIR/include" -I "$KERNEL_DIR/arch/arm64/boot/dts" \
    -undef -D__DTS__ -x assembler-with-cpp "$DTS_FILE" -o "$DTS_PREPROC"
# U-Boot dtc 1.4.x does not support /omit-if-no-ref/ (newer devicetree directive); strip those lines
sed -i '/^[[:space:]]*\/omit-if-no-ref\/[[:space:]]*$/d' "$DTS_PREPROC"
# Avoid /plugin/ so phandle refs are resolved (0xffffffff in blob causes U-Boot FDT_ERR_BADSTRUCTURE)
sed -i '/\/plugin\//d' "$DTS_PREPROC"
DTB_OUT="$OUTPUT_DIR/rk3566-miyoo-flip.dtb"
DTB_NEW="${DTB_OUT}.new.$$"
"$UBOOT_DTC" -I dts -O dtb -V 17 -p 1024 -o "$DTB_NEW" "$DTS_PREPROC"
rm -f "$DTS_PREPROC"
# Verify no unresolved phandle in structure block
if ! python3 -c "
import struct, sys
with open('$DTB_NEW', 'rb') as f: d = f.read()
off = struct.unpack('>I', d[8:12])[0]
size = struct.unpack('>I', d[36:40])[0]
block = d[off:off+size]
for i in range(0, len(block)-3, 4):
    if struct.unpack('>I', block[i:i+4])[0] == 0xffffffff:
        print('DTB has 0xffffffff at structure offset', i)
        sys.exit(1)
" 2>/dev/null; then
    rm -f "$DTB_NEW"
    echo "Error: DTB contains 0xffffffff (unresolved phandle). U-Boot will report FDT_ERR_BADSTRUCTURE."
    echo "Fix: ensure no /plugin/ in preproc (script strips it), or fix the DTS &label reference."
    echo "Workaround: use the kernel-built DTB from a full Docker build (make build) and reflash."
    exit 1
fi
if mv -f "$DTB_NEW" "$DTB_OUT" 2>/dev/null; then
    echo "DTB rebuilt: $DTB_OUT"
else
    echo "DTB built successfully: $DTB_NEW"
    echo "Could not replace $DTB_OUT (permission?). Move manually: mv $DTB_NEW $DTB_OUT"
    exit 1
fi
echo "Re-run ./build-boot-img.sh and reflash boot.img to use this DTB."
