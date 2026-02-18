#!/bin/bash
# Build mali_kbase kernel module (out-of-tree) + install libmali userspace to rootfs.
# Runs inside Docker (/build/ workdir). Sources bind-mounted from host.
#
# Uses ROCKNIX/mali_kbase (bifrost_port branch) which is already ported to mainline Linux 6.18+.
# No kernel compatibility patches needed.
set -e

NPROC=$(nproc 2>/dev/null || echo 1)
KERNEL_DIR="${KERNEL_DIR:-/build/kernel}"
OUTPUT_DIR="${OUTPUT_DIR:-/build/output}"
BUILDROOT_DIR="${BUILDROOT_DIR:-/build/buildroot}"
KBASE_DIR="/build/mali-bifrost"
LIBMALI_DIR="/build/libmali"

# ─── GPU config (RK3566 = Bifrost G52) ───
MALI_GPU="bifrost-g52"
MALI_VERSION="g24p0"
MALI_PLATFORM="gbm"
MALI_BLOB="libmali-${MALI_GPU}-${MALI_VERSION}-${MALI_PLATFORM}.so"

export ARCH=arm64
export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-buildroot-linux-gnu-}"

# Use Buildroot toolchain if available
BR_HOST="$BUILDROOT_DIR/output/host"
if [ -d "$BR_HOST/bin" ]; then
    export PATH="$BR_HOST/bin:$PATH"
fi
# Fallback to system cross-compiler
if ! command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1; then
    export CROSS_COMPILE="aarch64-linux-gnu-"
fi

echo "=========================================="
echo "Building Mali GPU Driver"
echo "=========================================="
echo "  GPU:      $MALI_GPU ($MALI_VERSION)"
echo "  Platform: $MALI_PLATFORM"
echo "  Source:   ROCKNIX/mali_kbase (bifrost_port)"
echo "  Kernel:   $KERNEL_DIR"
echo ""

# ─── Prerequisites ───
if [ ! -f "$KERNEL_DIR/arch/arm64/boot/Image" ]; then
    echo "Error: Kernel not built yet. Run 'make build-kernel' first."
    exit 1
fi

if [ ! -s "$KERNEL_DIR/Module.symvers" ]; then
    echo "Module.symvers missing or empty. Running modules_prepare..."
    rm -f "$KERNEL_DIR/Module.symvers"
    make -C "$KERNEL_DIR" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" modules_prepare
fi

# ROCKNIX layout: product/kernel/drivers/gpu/arm/midgard (no driver/ prefix)
MIDGARD_DIR="$KBASE_DIR/product/kernel/drivers/gpu/arm/midgard"

if [ ! -d "$MIDGARD_DIR" ]; then
    echo "Error: mali_kbase source not found at $MIDGARD_DIR"
    echo "Run: make download-mali"
    exit 1
fi

if [ ! -f "$LIBMALI_DIR/lib/aarch64-linux-gnu/$MALI_BLOB" ]; then
    echo "Error: libmali blob not found: $LIBMALI_DIR/lib/aarch64-linux-gnu/$MALI_BLOB"
    echo "Run: make download-mali"
    exit 1
fi

KERNEL_VERSION=$(make -s -C "$KERNEL_DIR" kernelversion 2>/dev/null || echo "unknown")
echo "  Kernel version: $KERNEL_VERSION"
echo ""

# ═══════════════════════════════════════════
# Part 1: Build mali_kbase.ko
# ═══════════════════════════════════════════
echo "--- Building mali_kbase kernel module ---"

MALI_MAKEFILE="$MIDGARD_DIR/Makefile"

if [ ! -f "$MALI_MAKEFILE" ]; then
    echo "Error: Mali Makefile not found at $MALI_MAKEFILE"
    exit 1
fi

# Clean previous build artifacts
make -C "$MIDGARD_DIR" KDIR="$KERNEL_DIR" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" clean 2>/dev/null || true

# Build (ROCKNIX sources are already compatible with modern kernels)
echo "  Compiling (this may take a few minutes)..."
make -C "$MIDGARD_DIR" \
    KDIR="$KERNEL_DIR" \
    ARCH=arm64 \
    CROSS_COMPILE="$CROSS_COMPILE" \
    CONFIG_MALI_MIDGARD=m \
    CONFIG_MALI_PLATFORM_NAME="devicetree" \
    CONFIG_MALI_DEVFREQ=y \
    CONFIG_MALI_GATOR_SUPPORT=n \
    KBUILD_MODPOST_WARN=1 \
    -j"$NPROC" 2>&1 | tee "$OUTPUT_DIR/mali-build.log" || {
    echo ""
    echo "Error: Failed to build mali_kbase module"
    echo "Full log: $OUTPUT_DIR/mali-build.log"
    exit 1
}

# Find built module
MODULE_FILE=$(find "$MIDGARD_DIR" -name "mali_kbase.ko" -type f | head -1)
if [ -z "$MODULE_FILE" ] || [ ! -f "$MODULE_FILE" ]; then
    echo "Error: mali_kbase.ko not found after build"
    echo "Check: $OUTPUT_DIR/mali-build.log"
    exit 1
fi
echo "  Built: $MODULE_FILE"

# Copy to output
mkdir -p "$OUTPUT_DIR/modules"
cp "$MODULE_FILE" "$OUTPUT_DIR/modules/mali_kbase.ko"
echo "  Saved: $OUTPUT_DIR/modules/mali_kbase.ko"

# Install to rootfs
BR_TARGET="$BUILDROOT_DIR/output/target"
if [ -d "$BR_TARGET/lib" ]; then
    MODULE_INSTALL_DIR="$BR_TARGET/lib/modules/$KERNEL_VERSION/extra"
    mkdir -p "$MODULE_INSTALL_DIR"
    cp "$MODULE_FILE" "$MODULE_INSTALL_DIR/mali_kbase.ko"
    echo "  Rootfs: $MODULE_INSTALL_DIR/mali_kbase.ko"

    # Regenerate module indexes so modprobe can find mali_kbase (manual append to modules.dep
    # is insufficient — depmod creates modules.alias, modules.symbols, etc. that modprobe needs).
    MODULES_BASE="$BR_TARGET/lib/modules/$KERNEL_VERSION"
    if command -v depmod >/dev/null 2>&1; then
        depmod -b "$BR_TARGET" -r "$KERNEL_VERSION" 2>/dev/null || true
    fi
    # Fallback: ensure modules.dep has our module if depmod didn't run (e.g. in minimal container)
    if [ -f "$MODULES_BASE/modules.dep" ]; then
        grep -q "mali_kbase" "$MODULES_BASE/modules.dep" || \
            echo "extra/mali_kbase.ko:" >> "$MODULES_BASE/modules.dep"
    else
        echo "extra/mali_kbase.ko:" > "$MODULES_BASE/modules.dep"
    fi

    # Blacklist panfrost (conflicts with mali_kbase; both match "arm,mali-bifrost")
    mkdir -p "$BR_TARGET/etc/modprobe.d"
    cat > "$BR_TARGET/etc/modprobe.d/mali.conf" << 'MODCONF'
# Use proprietary mali_kbase instead of open-source panfrost
blacklist panfrost
# Auto-load mali_kbase
alias mali0 mali_kbase
MODCONF
    echo "  Panfrost blacklisted: /etc/modprobe.d/mali.conf"

    # Auto-load mali_kbase on boot (BusyBox init doesn't read modules-load.d; use init.d script)
    mkdir -p "$BR_TARGET/etc/init.d"
    cat > "$BR_TARGET/etc/init.d/S00mali" << 'MALIINIT'
#!/bin/sh
# Load Mali GPU kernel module at boot (required for libmali/OpenGL ES)
case "$1" in
    start)
        modprobe mali_kbase 2>/dev/null || insmod /lib/modules/$(uname -r)/extra/mali_kbase.ko 2>/dev/null
        ;;
    stop)
        modprobe -r mali_kbase 2>/dev/null
        ;;
esac
MALIINIT
    chmod 0755 "$BR_TARGET/etc/init.d/S00mali"
    echo "  Auto-load: /etc/init.d/S00mali"
fi

# ═══════════════════════════════════════════
# Part 2: Install libmali userspace
# ═══════════════════════════════════════════
echo ""
echo "--- Installing libmali userspace ---"

if [ -d "$BR_TARGET" ]; then
    LIB_DIR="$BR_TARGET/usr/lib"
    INC_DIR="$BR_TARGET/usr/include"
    mkdir -p "$LIB_DIR" "$INC_DIR"

    # Install the blob
    cp "$LIBMALI_DIR/lib/aarch64-linux-gnu/$MALI_BLOB" "$LIB_DIR/"
    echo "  Blob: $LIB_DIR/$MALI_BLOB"

    # Create standard library symlinks (libmali is a mega-library providing EGL+GLES+GBM+CL)
    cd "$LIB_DIR"

    # EGL
    ln -sf "$MALI_BLOB" libEGL.so.1.0.0
    ln -sf libEGL.so.1.0.0 libEGL.so.1
    ln -sf libEGL.so.1 libEGL.so

    # GLESv1
    ln -sf "$MALI_BLOB" libGLESv1_CM.so.1.1.0
    ln -sf libGLESv1_CM.so.1.1.0 libGLESv1_CM.so.1
    ln -sf libGLESv1_CM.so.1 libGLESv1_CM.so

    # GLESv2
    ln -sf "$MALI_BLOB" libGLESv2.so.2.0.0
    ln -sf libGLESv2.so.2.0.0 libGLESv2.so.2
    ln -sf libGLESv2.so.2 libGLESv2.so

    # GBM
    ln -sf "$MALI_BLOB" libgbm.so.1.0.0
    ln -sf libgbm.so.1.0.0 libgbm.so.1
    ln -sf libgbm.so.1 libgbm.so

    # OpenCL (included in non-nocl variant)
    ln -sf "$MALI_BLOB" libOpenCL.so.1.0.0
    ln -sf libOpenCL.so.1.0.0 libOpenCL.so.1
    ln -sf libOpenCL.so.1 libOpenCL.so

    # libmali.so.1: blob's SONAME (dynamic linker loads this when running EGL/GLES apps)
    ln -sf "$MALI_BLOB" libmali.so.1
    ln -sf libmali.so.1 libmali.so

    echo "  Symlinks: libEGL, libGLESv1_CM, libGLESv2, libgbm, libOpenCL, libmali.so.1"

    # Install headers (EGL, GLES, GLES2, GLES3, GBM, KHR, CL)
    if [ -d "$LIBMALI_DIR/include" ]; then
        for hdir in EGL GLES GLES2 GLES3 GBM KHR CL; do
            if [ -d "$LIBMALI_DIR/include/$hdir" ]; then
                cp -r "$LIBMALI_DIR/include/$hdir" "$INC_DIR/"
            fi
        done
        echo "  Headers: EGL GLES GLES2 GLES3 GBM KHR CL -> $INC_DIR/"
    fi

    # Remove conflicting mesa EGL/GLES libraries if present
    for conflict in libEGL_mesa libGLESv2_mesa; do
        rm -f "$LIB_DIR/${conflict}"*.so* 2>/dev/null || true
    done
else
    echo "Warning: Buildroot target not found ($BR_TARGET). Skipping rootfs install."
    echo "  Run 'make build-rootfs' first, then 'make build-mali'."
fi

# Copy blob to output for reference
mkdir -p "$OUTPUT_DIR/mali"
cp "$LIBMALI_DIR/lib/aarch64-linux-gnu/$MALI_BLOB" "$OUTPUT_DIR/mali/"

# Rootfs squashfs: run 'make rootfs-img' after build-wifi and build-mali to pack.

echo ""
echo "=========================================="
echo "Mali GPU driver build complete!"
echo "=========================================="
echo "  Kernel module:  $OUTPUT_DIR/modules/mali_kbase.ko"
echo "  Userspace blob: $OUTPUT_DIR/mali/$MALI_BLOB"
echo ""
echo "On target:"
echo "  modprobe mali_kbase    (or: insmod /lib/modules/\$(uname -r)/extra/mali_kbase.ko)"
echo "  # Panfrost is blacklisted; mali_kbase auto-loads via /etc/modules-load.d/mali.conf"
echo ""
echo "Important: panfrost must be disabled in kernel config or built as module (not built-in)."
echo "  Both panfrost and mali_kbase match 'arm,mali-bifrost' in DT. Only one can bind."
echo "  If panfrost is built-in, mali_kbase cannot claim the GPU. Options:"
echo "    1. CONFIG_DRM_PANFROST=n (disable panfrost in kernel .config)"
echo "    2. CONFIG_DRM_PANFROST=m + blacklist (current setup)"
