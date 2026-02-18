#!/bin/bash
# Build U-Boot for Miyoo Flip (RK3566)
set -e

# Parent dir of u-boot and rkbin (make.sh expects ../rkbin)
MIYOO_SOURCE="${MIYOO_SOURCE:-/build/Extra/miyoo-flip-main}"
MIYOO_BUILD="${MIYOO_BUILD:-/build/miyoo-flip-build}"
UBOOT_SOURCE="$MIYOO_SOURCE/u-boot"
OUTPUT_DIR="${OUTPUT_DIR:-/build/output}"

export ARCH=arm64
export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-none-linux-gnu-}"

# Setup ccache if available
if command -v ccache >/dev/null 2>&1; then
    export CC="ccache ${CROSS_COMPILE}gcc"
    export CXX="ccache ${CROSS_COMPILE}g++"
    export PATH="/usr/lib/ccache:$PATH"
    echo "Using ccache for faster builds"
fi

echo "Building U-Boot for RK3566..."

# Check source (Extra/ is bind-mounted read-only; u-boot needs sibling ../rkbin)
if [ ! -d "$UBOOT_SOURCE" ] || [ ! -f "$UBOOT_SOURCE/make.sh" ]; then
    echo "Error: U-Boot source not found at $UBOOT_SOURCE"
    echo "Please ensure the miyoo-flip-main directory is extracted"
    exit 1
fi
if [ ! -d "$MIYOO_SOURCE/rkbin" ]; then
    echo "Error: rkbin not found at $MIYOO_SOURCE/rkbin (required by make.sh)"
    exit 1
fi

# Copy whole miyoo-flip-main so u-boot and rkbin stay siblings (make.sh uses ../rkbin)
echo "Copying miyoo-flip-main (u-boot + rkbin) to writable directory..."
rm -rf "$MIYOO_BUILD"
cp -a "$MIYOO_SOURCE" "$MIYOO_BUILD"
cd "$MIYOO_BUILD/u-boot"

# Build U-Boot using the provided make script
echo "Building U-Boot with make.sh rk3566..."
./make.sh rk3566

# Find and copy output files
mkdir -p "$OUTPUT_DIR"

# Look for uboot.img
if [ -f "uboot.img" ]; then
    cp uboot.img "$OUTPUT_DIR/"
    echo "U-Boot image: $OUTPUT_DIR/uboot.img"
fi

# Look for loader files
find . -maxdepth 1 -name "*loader*.bin" -o -name "*spl*.bin" 2>/dev/null | head -1 | while read f; do
    if [ -f "$f" ]; then
        cp "$f" "$OUTPUT_DIR/"
        echo "Loader: $OUTPUT_DIR/$(basename $f)"
    fi
done

# Also check for any generated files in current directory
if [ -f "idbloader.img" ]; then
    cp idbloader.img "$OUTPUT_DIR/"
fi

echo "U-Boot build complete!"
