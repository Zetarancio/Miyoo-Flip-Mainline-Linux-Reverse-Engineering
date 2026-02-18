#!/bin/bash
# Download and extract Miyoo Flip assets from steward-fu's GitHub releases.
#
# Usage:
#   ./setup-extra.sh              # Download all required + reference assets
#   ./setup-extra.sh --essential  # Download only build-essential assets
#   ./setup-extra.sh --all        # Download everything including stock firmware
#
# Assets are cached in $CACHE_DIR (default: ~/Downloads/miyoo-flip-assets/).
# If a file already exists in the cache, it is reused instead of re-downloaded.
#
# Source: https://github.com/steward-fu/website/releases/tag/miyoo-flip
set -e

RELEASE_URL="https://github.com/steward-fu/website/releases/download/miyoo-flip"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRA_DIR="$SCRIPT_DIR/Extra"
CACHE_DIR="${CACHE_DIR:-$HOME/Downloads/miyoo-flip-assets}"

MODE="${1:---default}"

mkdir -p "$EXTRA_DIR" "$CACHE_DIR"

fetch() {
    local filename="$1"
    local dest="$CACHE_DIR/$filename"

    if [ -f "$dest" ]; then
        echo "  cached: $filename"
        return 0
    fi

    echo "  downloading: $filename ..."
    if ! wget -q --show-progress -O "$dest.part" "$RELEASE_URL/$filename"; then
        rm -f "$dest.part"
        echo "  FAILED: $filename"
        return 1
    fi
    mv "$dest.part" "$dest"
}

# ── 1. SDK Release (cross-compilation toolchain) ─────────────────────────
#    Used by: docker-entrypoint.sh, build-kernel.sh
#    Archive: miyoo355_sdk_release/ (top-level dir inside tarball)
setup_sdk() {
    if [ -d "$EXTRA_DIR/miyoo355_sdk_release/host/bin" ]; then
        echo "[skip] miyoo355_sdk_release already present"
        return
    fi
    echo "[1/N] SDK toolchain (miyoo355_sdk_release) ~285 MB"
    fetch "miyoo355_sdk_release.20241121.tgz" || return 1
    echo "  extracting..."
    tar xzf "$CACHE_DIR/miyoo355_sdk_release.20241121.tgz" -C "$EXTRA_DIR/"
    echo "  done: $EXTRA_DIR/miyoo355_sdk_release/"
}

# ── 2. U-Boot + rkbin + bare-metal (miyoo-flip-main) ─────────────────────
#    Used by: build-uboot.sh, build-boot-img.sh, rebuild-dtb-for-uboot.sh
#    Archive: miyoo-flip-main/ (top-level dir inside zip)
setup_uboot() {
    if [ -d "$EXTRA_DIR/miyoo-flip-main/u-boot" ]; then
        echo "[skip] miyoo-flip-main already present"
        return
    fi
    echo "[2/N] U-Boot + rkbin (miyoo-flip-main) ~52 MB"
    fetch "miyoo-flip_PoC_bare-metal.zip" || return 1
    echo "  extracting..."
    unzip -qo "$CACHE_DIR/miyoo-flip_PoC_bare-metal.zip" -d "$EXTRA_DIR/"
    echo "  done: $EXTRA_DIR/miyoo-flip-main/"
}

# ── 3. Stock DTS reference ───────────────────────────────────────────────
#    Used for: DTS porting reference (Extra/rockchip/)
#    Archive: rockchip/ (top-level dir inside zip)
setup_stock_dts() {
    if [ -d "$EXTRA_DIR/rockchip" ] && [ -f "$EXTRA_DIR/rockchip/rk3566-miyoo-355-v10-linux.dts" ]; then
        echo "[skip] Stock DTS reference already present"
        return
    fi
    echo "[3/N] Stock DTS reference (rockchip/) ~166 KB"
    fetch "dts_ref_rockchip.zip" || return 1
    echo "  extracting..."
    unzip -qo "$CACHE_DIR/dts_ref_rockchip.zip" -d "$EXTRA_DIR/"
    # Also grab the standalone main DTS for easy reference
    fetch "rk3566-miyoo-355-v10-linux.dts" || true
    [ -f "$CACHE_DIR/rk3566-miyoo-355-v10-linux.dts" ] && \
        cp "$CACHE_DIR/rk3566-miyoo-355-v10-linux.dts" "$EXTRA_DIR/"
    echo "  done: $EXTRA_DIR/rockchip/"
}

# ── 4. Stock kernel config ───────────────────────────────────────────────
#    Used for: Reference when comparing BSP vs mainline kernel options
setup_kernel_config() {
    if [ -f "$EXTRA_DIR/kernel_config" ]; then
        echo "[skip] Stock kernel config already present"
        return
    fi
    echo "[4/N] Stock kernel config ~190 KB"
    fetch "kernel_config" || return 1
    cp "$CACHE_DIR/kernel_config" "$EXTRA_DIR/kernel_config"
    echo "  done: $EXTRA_DIR/kernel_config"
}

# ── 5. WiFi/BT firmware from stock rootfs ────────────────────────────────
#    Used by: build-rtl8733bu.sh (needs rtl8733bu_fw and rtl8733bu_config)
#    Downloads the stock rootfs squashfs and extracts only firmware files.
setup_firmware() {
    local fw_dir="$EXTRA_DIR/flip-sysroot/usr/lib/firmware"
    if [ -f "$fw_dir/rtl8733bu_fw" ] && [ -f "$fw_dir/rtl8733bu_config" ]; then
        echo "[skip] WiFi/BT firmware already present"
        return
    fi
    echo "[5/N] WiFi/BT firmware (from stock rootfs) ~45 MB download"
    fetch "spi_20241119160817_rootfs.img" || {
        echo "  WARNING: Could not download stock rootfs."
        echo "  WiFi/BT firmware must be extracted manually from your device."
        echo "  Place rtl8733bu_fw and rtl8733bu_config in:"
        echo "    $fw_dir/"
        return 1
    }

    if ! command -v unsquashfs >/dev/null 2>&1; then
        echo "  WARNING: unsquashfs not found (install squashfs-tools)."
        echo "  Extract firmware manually: unsquashfs -f -d /tmp/rootfs spi_20241119160817_rootfs.img"
        echo "  Then copy rtl8733bu_fw and rtl8733bu_config from /tmp/rootfs/usr/lib/firmware/ to:"
        echo "    $fw_dir/"
        return 1
    fi

    echo "  extracting firmware from stock rootfs..."
    local tmpdir
    tmpdir=$(mktemp -d)
    if unsquashfs -f -d "$tmpdir" "$CACHE_DIR/spi_20241119160817_rootfs.img" \
        usr/lib/firmware/rtl8733bu_fw usr/lib/firmware/rtl8733bu_config 2>/dev/null; then
        mkdir -p "$fw_dir"
        [ -f "$tmpdir/usr/lib/firmware/rtl8733bu_fw" ] && \
            cp "$tmpdir/usr/lib/firmware/rtl8733bu_fw" "$fw_dir/"
        [ -f "$tmpdir/usr/lib/firmware/rtl8733bu_config" ] && \
            cp "$tmpdir/usr/lib/firmware/rtl8733bu_config" "$fw_dir/"
        echo "  done: $fw_dir/"
    else
        echo "  WARNING: unsquashfs failed (image may need NAND-aware extraction)."
        echo "  Extract firmware manually from your device and place in:"
        echo "    $fw_dir/"
    fi
    rm -rf "$tmpdir"
}

# ── 6. Stock firmware dump (for backup/restore) ──────────────────────────
#    Full SPI NAND dump -- useful for unbricking or restoring stock OS.
setup_stock_firmware() {
    if [ -f "$EXTRA_DIR/spi_20241119160817.img" ]; then
        echo "[skip] Stock firmware already present"
        return
    fi
    echo "[6/N] Stock firmware dump ~134 MB"
    fetch "spi_20241119160817.img" || return 1
    cp "$CACHE_DIR/spi_20241119160817.img" "$EXTRA_DIR/spi_20241119160817.img"

    # Also grab partition images if available in cache
    for part in boot uboot rootfs userdata; do
        local pfile="spi_20241119160817_${part}.img"
        [ -f "$CACHE_DIR/$pfile" ] && cp "$CACHE_DIR/$pfile" "$EXTRA_DIR/$pfile"
    done
    echo "  done: $EXTRA_DIR/spi_20241119160817.img"
}

# ── 7. Stock kernel source (for BSP comparison) ──────────────────────────
#    The full Rockchip BSP kernel 5.10 with Miyoo patches.
setup_stock_kernel() {
    if [ -d "$EXTRA_DIR/linux-5.10.y-3b916183b455b56c966bc7c19c3f772d258dc583" ]; then
        echo "[skip] Stock kernel source already present"
        return
    fi
    echo "[7/N] Stock kernel source ~250 MB (for BSP comparison only)"
    fetch "linux-5.10.y-3b916183b455b56c966bc7c19c3f772d258dc583.zip" || return 1
    echo "  extracting (this may take a while)..."
    unzip -qo "$CACHE_DIR/linux-5.10.y-3b916183b455b56c966bc7c19c3f772d258dc583.zip" -d "$EXTRA_DIR/"
    echo "  done"
}

# ── 8. Input daemon source (reference) ───────────────────────────────────
setup_inputd() {
    if [ -f "$EXTRA_DIR/miyoo_inputd.c" ]; then
        echo "[skip] miyoo_inputd.c already present"
        return
    fi
    echo "[8/N] Input daemon source ~21 KB"
    fetch "miyoo_inputd.c" || return 1
    cp "$CACHE_DIR/miyoo_inputd.c" "$EXTRA_DIR/miyoo_inputd.c"
    echo "  done: $EXTRA_DIR/miyoo_inputd.c"
}

# ── 9. System.map (stock kernel symbols) ─────────────────────────────────
setup_sysmap() {
    if [ -f "$EXTRA_DIR/System.map-5.10" ]; then
        echo "[skip] System.map already present"
        return
    fi
    echo "[9/N] Stock kernel System.map ~7 MB"
    fetch "System.map-5.10" || return 1
    cp "$CACHE_DIR/System.map-5.10" "$EXTRA_DIR/System.map-5.10"
    echo "  done: $EXTRA_DIR/System.map-5.10"
}

# ═══════════════════════════════════════════════════════════════════════════

echo "============================================"
echo "Miyoo Flip (RK3566) — Asset Setup"
echo "============================================"
echo "Source:  $RELEASE_URL"
echo "Cache:   $CACHE_DIR"
echo "Target:  $EXTRA_DIR"
echo ""

case "$MODE" in
    --essential)
        echo "Mode: essential (build dependencies only)"
        echo ""
        setup_sdk
        setup_uboot
        setup_firmware
        ;;
    --all)
        echo "Mode: all (build deps + reference + stock firmware)"
        echo ""
        setup_sdk
        setup_uboot
        setup_stock_dts
        setup_kernel_config
        setup_firmware
        setup_stock_firmware
        setup_stock_kernel
        setup_inputd
        setup_sysmap
        ;;
    *)
        echo "Mode: default (build deps + reference material)"
        echo ""
        setup_sdk
        setup_uboot
        setup_stock_dts
        setup_kernel_config
        setup_firmware
        setup_inputd
        setup_sysmap
        ;;
esac

echo ""
echo "============================================"
echo "Setup complete."
echo "============================================"
echo ""
echo "Next steps:"
echo "  make download-kernel download-wifi download-mali"
echo "  make build"
echo ""
echo "See docs/building.md for the full build guide."
