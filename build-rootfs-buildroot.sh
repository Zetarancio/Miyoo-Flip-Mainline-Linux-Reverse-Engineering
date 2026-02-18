#!/bin/bash
# Build minimal rootfs using Buildroot for Miyoo Flip
# Uses Buildroot internal toolchain only; works with mainline kernel
set -e

NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
BUILDROOT_VERSION="${BUILDROOT_VERSION:-2024.02}"
BUILDROOT_DIR="${BUILDROOT_DIR:-/build/buildroot}"
OUTPUT_DIR="${OUTPUT_DIR:-/build/output}"
# Log file for debugging (in output/ so it persists on host)
BUILDROOT_LOG="${BUILDROOT_LOG:-$OUTPUT_DIR/buildroot-build.log}"

echo "Using Buildroot internal toolchain (only supported option)."

export ARCH=arm64

# Setup ccache if available (Buildroot will use it automatically)
if command -v ccache >/dev/null 2>&1; then
    export BR2_CCACHE=y
    export BR2_CCACHE_DIR="/build/.ccache"
    export BR2_CCACHE_INITIAL_SETUP=""
    echo "Using ccache for Buildroot builds"
fi

echo "=========================================="
echo "Building rootfs with Buildroot ${BUILDROOT_VERSION}"
echo "=========================================="

# Download Buildroot if not present
if [ ! -d "$BUILDROOT_DIR" ] || [ ! -f "$BUILDROOT_DIR/Makefile" ]; then
    echo "Downloading Buildroot ${BUILDROOT_VERSION}..."
    mkdir -p "$(dirname $BUILDROOT_DIR)"
    cd "$(dirname $BUILDROOT_DIR)"
    
    if [ ! -f "buildroot-${BUILDROOT_VERSION}.tar.xz" ]; then
        echo "Downloading from buildroot.org..."
        wget -q --show-progress "https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.xz"
    fi
    
    echo "Extracting Buildroot..."
    tar -xf "buildroot-${BUILDROOT_VERSION}.tar.xz"
    EXTRACTED="buildroot-${BUILDROOT_VERSION}"
    TARGET="$(basename $BUILDROOT_DIR)"
    if [ -d "$TARGET" ]; then
        # Target exists (e.g. bind mount); copy contents into it so Makefile/configs/ end up at top level
        cp -a "${EXTRACTED}/." "$TARGET/"
        rm -rf "$EXTRACTED"
    else
        mv "$EXTRACTED" "$TARGET"
    fi
fi

cd "$BUILDROOT_DIR"

# Avoid "duplicate filename / already applied" patch error in host-gcc-final (Buildroot quirk when build dir is reused).
if [ -d output/build ]; then
    rm -rf output/build/host-gcc-final-* 2>/dev/null || true
fi

# Ensure skeleton has etc/shells and etc/hosts (used by our Makefile patch and by Buildroot).
mkdir -p system/skeleton/etc
[ -f system/skeleton/etc/shells ] || touch system/skeleton/etc/shells
[ -f system/skeleton/etc/hosts ] || echo '127.0.0.1	localhost' > system/skeleton/etc/hosts
# Do NOT remove output/build/skeleton-init-common or output/per-package/skeleton_init_common here:
# that can break the per-package merge and leave the rootfs missing binaries (e.g. busybox) when building squashfs.
# Apply documented Makefile patch so etc/shells, etc/inittab and etc/hosts exist before target-finalize hooks (see patches/README-buildroot-makefile.md).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PATCH_FILE="${REPO_ROOT}/patches/buildroot-makefile-target-finalize.patch"
if [ -f "$PATCH_FILE" ] && [ -f Makefile ]; then
	if grep -q 'system/skeleton/etc/hosts' Makefile; then
		: # already patched
	elif patch -p1 -d "$BUILDROOT_DIR" --forward -s < "$PATCH_FILE"; then
		: # applied
	else
		echo "Warning: Could not apply $PATCH_FILE (Buildroot version may differ; see patches/README-buildroot-makefile.md)"
	fi
fi

# Apply fix for relocatable custom toolchain: use BR2 path when gcc-reported sysroot doesn't exist (e.g. in Docker).
# Fixes "Incorrect selection of the C library" when SDK gcc returns a host path that doesn't exist in the container.
MK="$BUILDROOT_DIR/toolchain/toolchain-external/pkg-toolchain-external.mk"
if [ -f "$MK" ] && ! grep -q 'TOOLCHAIN_EXTERNAL_INSTALL_DIR).*sysroot' "$MK" 2>/dev/null; then
	echo "Applying relocatable custom toolchain sysroot fix..."
	INSERT_TMP=$(mktemp)
	# Insert fallback SYSROOT_DIR for CONFIGURE_CMDS (so C library check uses actual path in Docker).
	cat << 'INSEOF' > "$INSERT_TMP"
	if test ! -d "$${SYSROOT_DIR}" ; then \
		if test "$(BR2_TOOLCHAIN_EXTERNAL_CUSTOM)" = "y" ; then \
			SYSROOT_DIR="$(TOOLCHAIN_EXTERNAL_INSTALL_DIR)/$(TOOLCHAIN_EXTERNAL_PREFIX)/sysroot" ; \
		fi ; \
	fi ; \
INSEOF
	# Match only the CONFIGURE_CMDS block (line with $$(Q)$$...SYSROOT_DIR), then insert after it.
	# In sed $ is end-of-line; pass \$\$ so sed sees literal $$. In script: \\\$\\\$ gives \$\$ to sed.
	sed -i "/\\\$\\\$(Q).*SYSROOT_DIR=.*toolchain_find_sysroot.*TOOLCHAIN_EXTERNAL_CC))/r $INSERT_TMP" "$MK"
	rm -f "$INSERT_TMP"
	echo "Relocatable toolchain fix applied."
	# Force toolchain-external-custom to reconfigure from scratch so the patched check runs.
	rm -rf output/build/toolchain-external-custom 2>/dev/null || true
fi

# Fix 2: Pass Make-expanded sysroot path to check_glibc for custom toolchain (avoids shell variable
# being empty when check_glibc runs in same recipe). Without this, $(call check_glibc,$${SYSROOT_DIR})
# gets empty because Make expands ${SYSROOT_DIR} at recipe build time, not the shell's value.
if [ -f "$MK" ] && grep -q 'call check_glibc,.*SYSROOT_DIR}' "$MK" 2>/dev/null && ! grep -q 'if \$(BR2_TOOLCHAIN_EXTERNAL_CUSTOM).*TOOLCHAIN_EXTERNAL_INSTALL_DIR.*sysroot' "$MK" 2>/dev/null; then
	echo "Applying check_glibc path fix for custom toolchain..."
	sed -i 's|$$(call check_glibc,$$$${SYSROOT_DIR})|$$(call check_glibc,$(if $(BR2_TOOLCHAIN_EXTERNAL_CUSTOM),$(TOOLCHAIN_EXTERNAL_INSTALL_DIR)/$(TOOLCHAIN_EXTERNAL_PREFIX)/sysroot,$$$${SYSROOT_DIR}))|' "$MK"
	echo "check_glibc path fix applied."
	rm -rf output/build/toolchain-external-custom 2>/dev/null || true
fi

# Fix 3: check_glibc uses find -maxdepth 2; ld-linux can be in sysroot/usr/lib/ (depth 3). Use maxdepth 4.
HELPERS_MK="$BUILDROOT_DIR/toolchain/helpers.mk"
if [ -f "$HELPERS_MK" ] && grep -q 'maxdepth 2.*ld-linux' "$HELPERS_MK" 2>/dev/null; then
	echo "Applying check_glibc maxdepth fix..."
	sed -i 's/-maxdepth 2 /-maxdepth 4 /g' "$HELPERS_MK"
	echo "check_glibc maxdepth fix applied."
	rm -rf output/build/toolchain-external-custom 2>/dev/null || true
fi

# Ensure regulatory.db for WiFi (Buildroot wireless-regdb package provides it; fallback download if package fails)
WIRELESS_REGDB_VER="2024.10.07"
REGDB_URL="https://cdn.kernel.org/pub/software/network/wireless-regdb/wireless-regdb-${WIRELESS_REGDB_VER}.tar.xz"
REGDB_OVERLAY="/tmp/regulatory-overlay"
mkdir -p "$REGDB_OVERLAY/lib/firmware"
if [ ! -f "$REGDB_OVERLAY/lib/firmware/regulatory.db" ]; then
    echo "Downloading wireless-regdb for regulatory.db fallback..."
    if (cd /tmp && wget -q -O regdb.tar.xz "$REGDB_URL" && tar -xf regdb.tar.xz 2>/dev/null); then
        cp "/tmp/wireless-regdb-${WIRELESS_REGDB_VER}/regulatory.db" "/tmp/wireless-regdb-${WIRELESS_REGDB_VER}/regulatory.db.p7s" "$REGDB_OVERLAY/lib/firmware/" 2>/dev/null
        rm -rf /tmp/regdb.tar.xz "/tmp/wireless-regdb-${WIRELESS_REGDB_VER}"
        echo "regulatory.db installed to overlay fallback"
    else
        echo "Warning: Could not download regulatory.db; WiFi may show 'failed to load regulatory.db'"
    fi
fi

# Create defconfig for Miyoo Flip
echo "Creating Miyoo Flip defconfig..."
cat > configs/miyoo_flip_defconfig << 'EOF'
# Architecture
BR2_aarch64=y
BR2_ARM_FPU_VFPV4=y

# Toolchain type: Buildroot internal (must be explicit so we do not default to external)
BR2_TOOLCHAIN_BUILDROOT=y
BR2_TOOLCHAIN_BUILDROOT_GLIBC=y
BR2_TOOLCHAIN_BUILDROOT_CXX=y
BR2_TOOLCHAIN_BUILDROOT_WCHAR=y

# System configuration - devtmpfs only (no eudev/kmod; matches minimal SDK, avoids liblzma/kmod deps)
BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_DEVTMPFS=y
BR2_SYSTEM_BIN_SH_BASH=y
# Serial console on ttyS2 @ 1500000 (matches kernel console=ttyS2,1500000n8); overlay provides inittab with 1500000
BR2_TARGET_GENERIC_GETTY_PORT="ttyS2"
BR2_TARGET_GENERIC_GETTY_BAUDRATE_115200=y
BR2_TARGET_GENERIC_GETTY_TERM="linux"
BR2_SYSTEM_DHCP="eth0"
# Overlay with etc/inittab so getty runs on ttyS2 at 1500000 (Buildroot has no 1500000 baud option)
BR2_ROOTFS_OVERLAY="/build/rootfs-overlay-serial"

# Kernel - disabled (we use mainline kernel built separately)
# BR2_LINUX_KERNEL is not set

# Packages
BR2_PACKAGE_BUSYBOX=y
BR2_PACKAGE_BUSYBOX_CONFIG="package/busybox/busybox.config"
BR2_PACKAGE_BUSYBOX_SHOW_OTHERS=y

# Audio (ALSA)
BR2_PACKAGE_ALSA_LIB=y
BR2_PACKAGE_ALSA_UTILS=y
BR2_PACKAGE_ALSA_UTILS_APLAY=y
BR2_PACKAGE_ALSA_UTILS_AMIXER=y
BR2_PACKAGE_ALSA_UTILS_ALSACTL=y

# WiFi (wpa_supplicant for WPA2/WPA3 connections; iw for scanning)
BR2_PACKAGE_WPA_SUPPLICANT=y
BR2_PACKAGE_WPA_SUPPLICANT_NL80211=y
BR2_PACKAGE_WPA_SUPPLICANT_CLI=y
BR2_PACKAGE_IW=y
BR2_PACKAGE_WIRELESS_TOOLS=y

# Bluetooth (BlueZ 5 stack + tools; depends on dbus)
BR2_PACKAGE_BLUEZ5_UTILS=y
BR2_PACKAGE_BLUEZ5_UTILS_TOOLS=y
BR2_PACKAGE_BLUEZ5_UTILS_DEPRECATED=y

# Wireless regulatory database (regulatory.db for RTL8733BU/cfg80211; avoids "failed to load regulatory.db")
BR2_PACKAGE_WIRELESS_REGDB=y

# Ensure dbus user exists (dbus-daemon fails with "Could not get UID and GID for username dbus" otherwise)
BR2_ROOTFS_USERS_TABLES="/build/dbus-users.table"

# Kernel module loading support
BR2_PACKAGE_KMOD=y
BR2_PACKAGE_KMOD_TOOLS=y

# Filesystem tools
BR2_PACKAGE_E2FSPROGS=y
BR2_PACKAGE_E2FSPROGS_RESIZE2FS=y
BR2_PACKAGE_SQUASHFS=y

# Root filesystem formats
BR2_TARGET_ROOTFS_SQUASHFS=y
BR2_TARGET_ROOTFS_SQUASHFS4_GZIP=y
BR2_TARGET_ROOTFS_TAR=y

# Network
BR2_PACKAGE_DROPBEAR=y
BR2_PACKAGE_IFUPDOWN=y
BR2_PACKAGE_IPROUTE2=y
BR2_PACKAGE_IPUTILS=y
BR2_PACKAGE_IPUTILS_PING=y
BR2_PACKAGE_IPUTILS_PING6=y
BR2_PACKAGE_CA_CERTIFICATES=y
BR2_PACKAGE_OPENSSH=y
BR2_PACKAGE_OPENSSH_CLIENT=y
BR2_PACKAGE_OPENSSH_SERVER=y

# System utilities
BR2_PACKAGE_UTIL_LINUX=y
BR2_PACKAGE_UTIL_LINUX_MOUNT=y
BR2_PACKAGE_UTIL_LINUX_UMOUNT=y
BR2_PACKAGE_UTIL_LINUX_FSCK=y
BR2_PACKAGE_UTIL_LINUX_PARTX=y
BR2_PACKAGE_UTIL_LINUX_MKFS=y
BR2_PACKAGE_UTIL_LINUX_SWAPONOFF=y
BR2_PACKAGE_PROCPS_NG=y
BR2_PACKAGE_PSMISC=y

# MTD tools (for SPI flash)
BR2_PACKAGE_MTD=y
BR2_PACKAGE_MTD_UTILS=y

# Text editors
BR2_PACKAGE_NANO=y
BR2_PACKAGE_LESS=y

# Basic utilities
BR2_PACKAGE_WHICH=y
BR2_PACKAGE_TREE=y
BR2_PACKAGE_GREP=y
BR2_PACKAGE_SED=y
BR2_PACKAGE_FINDUTILS=y
BR2_PACKAGE_TAR=y
BR2_PACKAGE_GZIP=y
BR2_PACKAGE_BZIP2=y
BR2_PACKAGE_XZ=y
BR2_PACKAGE_COREUTILS=y
EOF

# Add regulatory.db overlay if we downloaded it (fallback when wireless-regdb package doesn't install)
if [ -f "$REGDB_OVERLAY/lib/firmware/regulatory.db" ]; then
    sed -i "s|BR2_ROOTFS_OVERLAY=\"/build/rootfs-overlay-serial\"|BR2_ROOTFS_OVERLAY=\"/build/rootfs-overlay-serial $REGDB_OVERLAY\"|" configs/miyoo_flip_defconfig
fi

# Configure Buildroot
echo "Configuring Buildroot..."
make -j$NPROC miyoo_flip_defconfig

# Buildroot internal toolchain: disable C++ to avoid libstdc++ configure error
# "Link tests are not allowed after GCC_NO_EXECUTABLES" when cross-compiling.
sed -i -e 's/^BR2_TOOLCHAIN_BUILDROOT_CXX=y$/# BR2_TOOLCHAIN_BUILDROOT_CXX is not set/' \
       -e 's/^BR2_INSTALL_LIBSTDCPP=y$/# BR2_INSTALL_LIBSTDCPP is not set/' .config
make -j$NPROC olddefconfig
rm -rf output/build/host-gcc-final-* 2>/dev/null || true
echo "Internal toolchain: C only (no libstdc++)."

# (Kernel already disabled in miyoo_flip_defconfig above; do not append again to avoid override warning.)

# Build glibc first, then ensure crt*.o are in sysroot so host-gcc-final and target libs can link.
mkdir -p "$(dirname "$BUILDROOT_LOG")"
echo "Building glibc first (internal toolchain)..."
make -j$NPROC glibc 2>&1 | tee "$BUILDROOT_LOG"
STAGING_SYSROOT="$(pwd)/output/host/aarch64-buildroot-linux-gnu/sysroot"
GLIBC_CSU=$(find output/build -type d -name csu -path '*/glibc-*/build/csu' 2>/dev/null | head -1)
if [ -n "$GLIBC_CSU" ] && [ -f "$GLIBC_CSU/crt1.o" ] && [ -f "$GLIBC_CSU/crti.o" ] && [ -f "$GLIBC_CSU/crtn.o" ]; then
	for LIBDIR in usr/lib64 usr/lib lib lib64; do
		STAGING_LIB="$STAGING_SYSROOT/$LIBDIR"
		mkdir -p "$STAGING_LIB"
		if [ -d "$STAGING_LIB" ]; then
			if [ ! -f "$STAGING_LIB/crt1.o" ] || [ ! -f "$STAGING_LIB/crti.o" ] || [ ! -f "$STAGING_LIB/Scrt1.o" ]; then
				echo "Installing crt*.o and Scrt1.o into sysroot ($LIBDIR) for host-gcc-final and target packages..."
				cp -f "$GLIBC_CSU"/crt*.o "$STAGING_LIB/"
				[ -f "$GLIBC_CSU/Scrt1.o" ] && cp -f "$GLIBC_CSU/Scrt1.o" "$STAGING_LIB/"
				[ -f "$GLIBC_CSU/rcrt1.o" ] && cp -f "$GLIBC_CSU/rcrt1.o" "$STAGING_LIB/"
			fi
		fi
	done
else
	echo "Warning: glibc csu/crt1.o, crti.o or crtn.o not found in $GLIBC_CSU - host-gcc-final may fail"
fi

# Build (tee to log file for debugging)
mkdir -p "$(dirname "$BUILDROOT_LOG")"
echo ""
echo "Building rootfs (this may take 30-60 minutes on first build)..."
echo "Subsequent builds will be much faster due to caching."
echo "Log file: $BUILDROOT_LOG"
make -j$NPROC 2>&1 | tee -a "$BUILDROOT_LOG"
make_exit=${PIPESTATUS[0]}
if [ "$make_exit" -ne 0 ]; then
    echo "Buildroot build failed (exit $make_exit). See $BUILDROOT_LOG"
    exit "$make_exit"
fi

# Copy outputs
mkdir -p "$OUTPUT_DIR"
if [ -f output/images/rootfs.squashfs ]; then
    cp output/images/rootfs.squashfs "$OUTPUT_DIR/rootfs.squashfs"
    echo "✓ Squashfs rootfs: $OUTPUT_DIR/rootfs.squashfs ($(du -h "$OUTPUT_DIR/rootfs.squashfs" | cut -f1))"
    # Verify regulatory.db is in rootfs (for WiFi)
    if [ -f output/target/lib/firmware/regulatory.db ]; then
        echo "✓ regulatory.db present in rootfs"
    else
        echo "Warning: regulatory.db NOT found in rootfs - WiFi will show 'failed to load regulatory.db'"
    fi
fi

if [ -f output/images/rootfs.tar ]; then
    cp output/images/rootfs.tar "$OUTPUT_DIR/rootfs.tar"
    echo "✓ Rootfs tarball: $OUTPUT_DIR/rootfs.tar ($(du -h "$OUTPUT_DIR/rootfs.tar" | cut -f1))"
    
    # Create ext4 image for SD card testing (optional; loop mount may fail in Docker without --privileged)
    echo "Creating ext4 image for SD card testing..."
    ROOTFS_EXT4="$OUTPUT_DIR/rootfs.ext4"
    if dd if=/dev/zero of="$ROOTFS_EXT4" bs=1M count=256 2>/dev/null && mkfs.ext4 -F "$ROOTFS_EXT4" > /dev/null 2>&1; then
        TMP_MOUNT=$(mktemp -d)
        if mount -o loop "$ROOTFS_EXT4" "$TMP_MOUNT" 2>/dev/null; then
            tar -C "$TMP_MOUNT" -xf "$OUTPUT_DIR/rootfs.tar"
            umount "$TMP_MOUNT"
            echo "✓ Ext4 rootfs: $OUTPUT_DIR/rootfs.ext4 ($(du -h "$ROOTFS_EXT4" | cut -f1))"
        else
            echo "Skipping ext4 image: loop mount not permitted (e.g. in Docker without --privileged)."
            rm -f "$ROOTFS_EXT4"
        fi
        rmdir "$TMP_MOUNT" 2>/dev/null || true
    else
        echo "Skipping ext4 image: could not create image file."
    fi
fi

echo ""
echo "Buildroot build complete!"
echo ""
echo "Output files:"
ls -lh "$OUTPUT_DIR"/rootfs.* 2>/dev/null || true
