#!/bin/bash
# Build rk3568_dmc kernel module (out-of-tree DDR devfreq) + install to rootfs.
# Runs inside Docker (/build/ workdir).
set -e

NPROC=$(nproc 2>/dev/null || echo 1)
KERNEL_DIR="${KERNEL_DIR:-/build/kernel}"
OUTPUT_DIR="${OUTPUT_DIR:-/build/output}"
BUILDROOT_DIR="${BUILDROOT_DIR:-/build/buildroot}"
DMC_DIR="/build/modules/rk3568_dmc"

export ARCH=arm64
export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-buildroot-linux-gnu-}"

BR_HOST="$BUILDROOT_DIR/output/host"
if [ -d "$BR_HOST/bin" ]; then
    export PATH="$BR_HOST/bin:$PATH"
fi
if ! command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1; then
    export CROSS_COMPILE="aarch64-linux-gnu-"
fi

echo "=========================================="
echo "Building RK3568 DDR devfreq module"
echo "=========================================="
echo "  Source:  $DMC_DIR"
echo "  Kernel:  $KERNEL_DIR"
echo ""

if [ ! -f "$KERNEL_DIR/arch/arm64/boot/Image" ]; then
    echo "Error: Kernel not built yet. Run 'make build-kernel' first."
    exit 1
fi

if [ ! -s "$KERNEL_DIR/Module.symvers" ]; then
    echo "Module.symvers missing or empty. Running modules_prepare..."
    rm -f "$KERNEL_DIR/Module.symvers"
    make -C "$KERNEL_DIR" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" modules_prepare
    if [ ! -s "$KERNEL_DIR/Module.symvers" ]; then
        echo "Warning: Module.symvers still empty after modules_prepare."
        echo "  You may need to rebuild the kernel: make build-kernel"
        echo "  (make Image generates Module.symvers with exported symbols)"
    fi
fi

if [ ! -d "$DMC_DIR" ]; then
    echo "Error: DMC module source not found at $DMC_DIR"
    exit 1
fi

KERNEL_VERSION=$(make -s -C "$KERNEL_DIR" kernelversion 2>/dev/null || echo "unknown")
echo "  Kernel version: $KERNEL_VERSION"
echo ""

echo "--- Building rk3568_dmc kernel module ---"

make -C "$DMC_DIR" KDIR="$KERNEL_DIR" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" clean 2>/dev/null || true

make -C "$DMC_DIR" \
    KDIR="$KERNEL_DIR" \
    ARCH=arm64 \
    CROSS_COMPILE="$CROSS_COMPILE" \
    KBUILD_MODPOST_WARN=1 \
    -j"$NPROC" 2>&1 | tee "$OUTPUT_DIR/dmc-build.log" || {
    echo ""
    echo "Error: Failed to build rk3568_dmc module"
    echo "Full log: $OUTPUT_DIR/dmc-build.log"
    exit 1
}

MODULE_FILE="$DMC_DIR/rk3568_dmc.ko"
if [ ! -f "$MODULE_FILE" ]; then
    echo "Error: rk3568_dmc.ko not found after build"
    exit 1
fi
echo "  Built: $MODULE_FILE"

mkdir -p "$OUTPUT_DIR/modules"
cp "$MODULE_FILE" "$OUTPUT_DIR/modules/rk3568_dmc.ko"
echo "  Saved: $OUTPUT_DIR/modules/rk3568_dmc.ko"

BR_TARGET="$BUILDROOT_DIR/output/target"
if [ -d "$BR_TARGET/lib" ]; then
    MODULE_INSTALL_DIR="$BR_TARGET/lib/modules/$KERNEL_VERSION/extra"
    mkdir -p "$MODULE_INSTALL_DIR"
    cp "$MODULE_FILE" "$MODULE_INSTALL_DIR/rk3568_dmc.ko"
    echo "  Rootfs: $MODULE_INSTALL_DIR/rk3568_dmc.ko"

    MODULES_BASE="$BR_TARGET/lib/modules/$KERNEL_VERSION"
    if command -v depmod >/dev/null 2>&1; then
        depmod -b "$BR_TARGET" -r "$KERNEL_VERSION" 2>/dev/null || true
    fi
    if [ -f "$MODULES_BASE/modules.dep" ]; then
        grep -q "rk3568_dmc" "$MODULES_BASE/modules.dep" || \
            echo "extra/rk3568_dmc.ko:" >> "$MODULES_BASE/modules.dep"
    else
        echo "extra/rk3568_dmc.ko:" > "$MODULES_BASE/modules.dep"
    fi

    mkdir -p "$BR_TARGET/etc/init.d"
    cat > "$BR_TARGET/etc/init.d/S01dmc" << 'DMCINIT'
#!/bin/sh
# Load DDR devfreq module at boot for DDR frequency scaling (battery saving)
case "$1" in
    start)
        modprobe rk3568_dmc 2>/dev/null || insmod /lib/modules/$(uname -r)/extra/rk3568_dmc.ko 2>/dev/null
        ;;
    stop)
        modprobe -r rk3568_dmc 2>/dev/null
        ;;
esac
DMCINIT
    chmod 0755 "$BR_TARGET/etc/init.d/S01dmc"
    echo "  Auto-load: /etc/init.d/S01dmc"
fi

echo ""
echo "=========================================="
echo "RK3568 DDR devfreq module build complete!"
echo "=========================================="
echo "  Kernel module:  $OUTPUT_DIR/modules/rk3568_dmc.ko"
echo ""
echo "On target:"
echo "  modprobe rk3568_dmc"
echo "  cat /sys/class/devfreq/dmc/cur_freq"
echo "  cat /sys/class/devfreq/dmc/available_frequencies"
