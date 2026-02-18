#!/bin/bash
# Build RTL8733BU WiFi driver as out-of-tree module and install BT firmware
# Runs inside Docker (/build/ workdir). Uses pre-patched sources from /build/RTL8733BU/.
set -e

NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
KERNEL_DIR="${KERNEL_DIR:-/build/kernel}"
OUTPUT_DIR="${OUTPUT_DIR:-/build/output}"
BUILDROOT_DIR="${BUILDROOT_DIR:-/build/buildroot}"
DRIVER_DIR="/build/RTL8733BU"

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
echo "Building RTL8733BU WiFi/BT driver"
echo "=========================================="

# Check if kernel is built
if [ ! -f "$KERNEL_DIR/arch/arm64/boot/Image" ]; then
    echo "Error: Kernel not built yet. Run 'make build-kernel' first."
    exit 1
fi

# Ensure kernel has Module.symvers (needed for out-of-tree module builds)
if [ ! -f "$KERNEL_DIR/Module.symvers" ]; then
    echo "Preparing kernel for module builds (modules_prepare)..."
    make -C "$KERNEL_DIR" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" modules_prepare
    touch "$KERNEL_DIR/Module.symvers"
fi

# Check driver sources exist (mounted from host)
if [ ! -d "$DRIVER_DIR" ]; then
    echo "Error: RTL8733BU source not found at $DRIVER_DIR"
    echo "Clone it on host: git clone --depth 1 -b v5.15.12-126-wb https://github.com/ROCKNIX/RTL8733BU.git RTL8733BU"
    exit 1
fi

cd "$DRIVER_DIR"

# Clean previous build and reset Makefile to pristine state
make clean 2>/dev/null || true
# Reset Makefile and .mk files to original (undo sed changes from previous runs)
git checkout -- Makefile *.mk 2>/dev/null || true

# --- Makefile / build-system configuration ---
echo "Configuring driver Makefile for cross-compilation..."

# Disable default platform and add our custom one
sed -i 's/^CONFIG_PLATFORM_WB = y/CONFIG_PLATFORM_WB = n/' Makefile
if ! grep -q 'CONFIG_PLATFORM_ARM_MIYOO' Makefile; then
    sed -i '/^CONFIG_PLATFORM_MTK9612 = n/a\CONFIG_PLATFORM_ARM_MIYOO = y' Makefile
    sed -i '/^########### CUSTOMER/i\
ifeq ($(CONFIG_PLATFORM_ARM_MIYOO), y)\
EXTRA_CFLAGS += -DCONFIG_LITTLE_ENDIAN\
EXTRA_CFLAGS += -DCONFIG_IOCTL_CFG80211 -DRTW_USE_CFG80211_STA_EVENT\
ARCH := arm64\
CROSS_COMPILE := '"$CROSS_COMPILE"'\
KSRC := '"$KERNEL_DIR"'\
endif\
' Makefile
fi

# Kernel 6.19+ dropped EXTRA_CFLAGS support in kbuild; convert to ccflags-y
# Must also convert in included .mk files (e.g. rtl8733b.mk defines -DCONFIG_RTL8733B)
sed -i -e 's/EXTRA_CFLAGS/ccflags-y/g' -e 's/EXTRA_LDFLAGS/ldflags-y/g' Makefile
for mkf in "$DRIVER_DIR"/*.mk; do
    [ -f "$mkf" ] && sed -i -e 's/EXTRA_CFLAGS/ccflags-y/g' -e 's/EXTRA_LDFLAGS/ldflags-y/g' "$mkf"
done

# Replace $(src) include paths with absolute paths ($(src) resolves unreliably in kbuild 6.19)
sed -i "s|-I\$(src)/include|-I$DRIVER_DIR/include|g" Makefile
sed -i "s|-I\$(src)/platform|-I$DRIVER_DIR/platform|g" Makefile
sed -i "s|-I\$(src)/hal/btc|-I$DRIVER_DIR/hal/btc|g" Makefile
sed -i "s|-I\$(src)/|-I$DRIVER_DIR/|g" Makefile

# Add missing include paths
sed -i "1i\\ccflags-y += -I$DRIVER_DIR/hal/phydm" Makefile

# Add warning suppressions and firmware loading config
sed -i '1i\ccflags-y += -Wno-error -Wno-incompatible-pointer-types -Wno-implicit-function-declaration -Wno-int-conversion -Wno-missing-prototypes -Wno-missing-declarations' Makefile
sed -i '1i\ccflags-y += -DCONFIG_FILE_FWIMG' Makefile

# Fix halmac include path (headers reference "halmac/" but source dir is "halmac-rs/")
ln -sfn halmac-rs "$DRIVER_DIR/hal/halmac" 2>/dev/null || true

# Build the module
echo ""
echo "Building RTL8733BU WiFi module..."
echo "  Kernel: $KERNEL_DIR"
echo "  Cross-compile: $CROSS_COMPILE"

make -j"$NPROC" \
    ARCH=arm64 \
    CROSS_COMPILE="$CROSS_COMPILE" \
    KSRC="$KERNEL_DIR" \
    KBUILD_MODPOST_WARN=1 \
    modules 2>&1 | tee "$OUTPUT_DIR/wifi-build.log" || {
    echo "Error: Failed to build RTL8733BU driver"
    echo "Full build log saved to: $OUTPUT_DIR/wifi-build.log"
    exit 1
}

# Find the built module
MODULE_FILE=$(find . -name "*.ko" -type f | head -1)
if [ -z "$MODULE_FILE" ] || [ ! -f "$MODULE_FILE" ]; then
    echo "Error: No .ko module found after build"
    exit 1
fi
echo "Built module: $MODULE_FILE"

# Get kernel version
KERNEL_VERSION=$(make -s -C "$KERNEL_DIR" kernelversion 2>/dev/null || echo "unknown")
echo "Kernel version: $KERNEL_VERSION"

# Copy module to output
mkdir -p "$OUTPUT_DIR/modules"
cp "$MODULE_FILE" "$OUTPUT_DIR/modules/rtl8733bu.ko"
echo "Module copied to: $OUTPUT_DIR/modules/rtl8733bu.ko"

# Install module into Buildroot rootfs target (if it exists)
BR_TARGET="$BUILDROOT_DIR/output/target"
if [ -d "$BR_TARGET/lib" ]; then
    MODULE_INSTALL_DIR="$BR_TARGET/lib/modules/$KERNEL_VERSION/extra"
    mkdir -p "$MODULE_INSTALL_DIR"
    cp "$MODULE_FILE" "$MODULE_INSTALL_DIR/rtl8733bu.ko"
    echo "Module installed to rootfs: $MODULE_INSTALL_DIR/rtl8733bu.ko"

    # Regenerate module indexes (depmod) so modprobe finds all extra modules (WiFi + Mali).
    # Do NOT overwrite modules.dep—build-mali may have added mali_kbase; use depmod to include all.
    MODULES_BASE="$BR_TARGET/lib/modules/$KERNEL_VERSION"
    if command -v depmod >/dev/null 2>&1; then
        depmod -b "$BR_TARGET" -r "$KERNEL_VERSION" 2>/dev/null || true
    else
        # Fallback: append if not already present (preserve mali_kbase if build-mali ran first)
        grep -q "rtl8733bu" "$MODULES_BASE/modules.dep" 2>/dev/null || \
            echo "extra/rtl8733bu.ko:" >> "$MODULES_BASE/modules.dep"
    fi
fi

# Install firmware files from stock sysroot (Bluetooth AND WiFi)
echo ""
echo "Installing firmware (BT + WiFi)..."
STOCK_FW="/build/Extra/flip-sysroot/usr/lib/firmware"
if [ -d "$STOCK_FW" ]; then
    if [ -d "$BR_TARGET" ]; then
        # Bluetooth firmware (btrtl expects rtl_bt/rtl8733bu_fw.bin)
        FW_DIR="$BR_TARGET/lib/firmware/rtl_bt"
        mkdir -p "$FW_DIR"
        [ -f "$STOCK_FW/rtl8733bu_fw" ] && cp "$STOCK_FW/rtl8733bu_fw" "$FW_DIR/rtl8733bu_fw.bin" && echo "  BT firmware: $FW_DIR/rtl8733bu_fw.bin"
        [ -f "$STOCK_FW/rtl8733bu_config" ] && cp "$STOCK_FW/rtl8733bu_config" "$FW_DIR/rtl8733bu_config.bin" && echo "  BT config:   $FW_DIR/rtl8733bu_config.bin"

        # WiFi firmware (request_firmware loads from /lib/firmware/)
        WIFI_FW_DIR="$BR_TARGET/lib/firmware"
        mkdir -p "$WIFI_FW_DIR"
        for fw_file in rtl8733bu_fw rtl8733bu_config; do
            [ -f "$STOCK_FW/$fw_file" ] && cp "$STOCK_FW/$fw_file" "$WIFI_FW_DIR/$fw_file" && echo "  WiFi firmware: $WIFI_FW_DIR/$fw_file"
        done
    fi

    mkdir -p "$OUTPUT_DIR/firmware/rtl_bt"
    [ -f "$STOCK_FW/rtl8733bu_fw" ] && cp "$STOCK_FW/rtl8733bu_fw" "$OUTPUT_DIR/firmware/rtl_bt/rtl8733bu_fw.bin"
    [ -f "$STOCK_FW/rtl8733bu_config" ] && cp "$STOCK_FW/rtl8733bu_config" "$OUTPUT_DIR/firmware/rtl_bt/rtl8733bu_config.bin"
else
    echo "Warning: Stock firmware not found at $STOCK_FW"
fi

# Rootfs squashfs: run 'make rootfs-img' after build-wifi and build-mali to pack.

echo ""
echo "=========================================="
echo "RTL8733BU build complete!"
echo "=========================================="
echo "  WiFi module: $OUTPUT_DIR/modules/rtl8733bu.ko"
echo "  BT firmware:  $OUTPUT_DIR/firmware/rtl_bt/"
echo ""
echo "On target:"
echo "  WiFi:  insmod /lib/modules/\$(uname -r)/extra/rtl8733bu.ko"
echo "  BT:    Firmware loaded automatically by btusb/btrtl"
