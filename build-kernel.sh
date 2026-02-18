#!/bin/bash
# Build mainline Linux kernel for Miyoo Flip (RK3566) with display (DSI) and sound (RK817).
# Automatically configures kernel: DSI + DPHY for display, Rockchip I2S + RK817 codec for sound.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${KERNEL_DIR:-$SCRIPT_DIR/kernel}"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/output}"
EXTRA_DIR="${EXTRA_DIR:-$SCRIPT_DIR/Extra}"
# Log file for debugging (in output/ so it persists on host when built in Docker)
KERNEL_LOG="${KERNEL_LOG:-$OUTPUT_DIR/kernel-build.log}"
NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)

export ARCH=arm64

mkdir -p "$OUTPUT_DIR"
cd "$KERNEL_DIR"

if [ ! -f Makefile ]; then
    echo "Error: No kernel source at $KERNEL_DIR. Run: make download-kernel  (or remove kernel/ and run it to re-download)."
    exit 1
fi

# ---- Ensure cross-toolchain nm is on PATH and works ----
# The kernel's check-local-export script runs $(CROSS_COMPILE)nm; if it's not found or fails, the build dies with "nm failed".
# Resolve toolchain bin and verify nm so we fail fast with a clear message instead of mid-build.
if [ -n "$CROSS_COMPILE" ]; then
    NM_NAME="${CROSS_COMPILE}nm"
    if ! command -v "$NM_NAME" >/dev/null 2>&1; then
        TOOLCHAIN_BIN=""
        for d in "$EXTRA_DIR/miyoo355_sdk_release/host/bin" "$EXTRA_DIR/flip" /usr/bin; do
            [ -d "$d" ] || continue
            if [ -x "${d}/${NM_NAME}" ]; then
                TOOLCHAIN_BIN="$d"
                break
            fi
        done
        if [ -n "$TOOLCHAIN_BIN" ]; then
            export PATH="${TOOLCHAIN_BIN}:$PATH"
        fi
    fi
    if ! command -v "$NM_NAME" >/dev/null 2>&1; then
        echo "Error: ${NM_NAME} not found. Add the cross-toolchain bin directory to PATH." >&2
        echo '  Example: export PATH=/path/to/Extra/miyoo355_sdk_release/host/bin:$PATH' >&2
        exit 1
    fi
    if ! "$NM_NAME" --version >/dev/null 2>&1; then
        echo "Error: ${NM_NAME} fails to run (wrong arch or missing libs). Use a working cross-toolchain." >&2
        echo "  In Docker: ensure Extra/ is bind-mounted with the SDK (e.g. miyoo355_sdk_release)." >&2
        exit 1
    fi
fi

# Save .config before any modifications so we can detect real changes.
# If the config content doesn't change, we restore the original file to preserve
# its mtime — this prevents make from re-running syncconfig and doing a full rebuild.
if [ -s "$KERNEL_DIR/.config" ]; then
    cp -a "$KERNEL_DIR/.config" "$KERNEL_DIR/.config.prebuild"
fi

# Copy project DTS into kernel tree and force DTB rebuild (so incremental build always uses latest DTS)
DTS_PROJECT="${SCRIPT_DIR}/rk3566-miyoo-flip.dts"
DTS_KERNEL="$KERNEL_DIR/arch/arm64/boot/dts/rockchip/rk3566-miyoo-flip.dts"
DTB_KERNEL="$KERNEL_DIR/arch/arm64/boot/dts/rockchip/rk3566-miyoo-flip.dtb"
if [ -f "$DTS_PROJECT" ] && [ -d "$(dirname "$DTS_KERNEL")" ]; then
    cp -f "$DTS_PROJECT" "$DTS_KERNEL"
    rm -f "$DTB_KERNEL"
    if ! grep -q "rk3566-miyoo-flip" "$KERNEL_DIR/arch/arm64/boot/dts/rockchip/Makefile" 2>/dev/null; then
        echo 'dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3566-miyoo-flip.dtb' >> "$KERNEL_DIR/arch/arm64/boot/dts/rockchip/Makefile"
    fi
fi
# Force panel-simple (DSI) rebuild so edits to panel-simple.c are always included without make clean-kernel
rm -f "$KERNEL_DIR/drivers/gpu/drm/panel/panel-simple.o"
# Force btrtl rebuild so edits to btrtl.c are always included (RTL8733BU BT support)
rm -f "$KERNEL_DIR/drivers/bluetooth/btrtl.o"

# ---- Kernel config ----
# If project root has kernel.config, use it as-is (no defconfig, no enable/disable list). Otherwise start from defconfig and apply options.
PROJECT_CONFIG="${SCRIPT_DIR}/kernel.config"
CONFIG_SCRIPT="$KERNEL_DIR/scripts/config"
if [ -s "$PROJECT_CONFIG" ]; then
    echo "Using kernel config from project root: $PROJECT_CONFIG"
    cp -f "$PROJECT_CONFIG" "$KERNEL_DIR/.config"
    [ -s .config ] && echo "=== kernel build $(date -Iseconds 2>/dev/null || date) ===" > "$KERNEL_LOG"
    make olddefconfig 2>&1 | tee -a "$KERNEL_LOG"
    if [ -x "$CONFIG_SCRIPT" ]; then
        disable_opt() { "$CONFIG_SCRIPT" --file "$KERNEL_DIR/.config" --disable "$1" 2>/dev/null || true; }
        disable_opt CONFIG_COMPILE_TEST
        disable_opt CONFIG_CROS_EC
        disable_opt CONFIG_FRAMEBUFFER_CONSOLE
    fi
    sed -i -e 's/^CONFIG_COMPILE_TEST=y$/# CONFIG_COMPILE_TEST is not set/' \
           -e 's/^CONFIG_CROS_EC=.*/# CONFIG_CROS_EC is not set/' \
           "$KERNEL_DIR/.config" 2>/dev/null || true
else
    if [ ! -s .config ]; then
        echo "No .config found; starting from arm64 defconfig..."
        { echo "=== kernel defconfig $(date -Iseconds 2>/dev/null || date) ==="; make defconfig; } 2>&1 | tee "$KERNEL_LOG"
    fi

    CONFIG_SCRIPT="$KERNEL_DIR/scripts/config"
    if [ ! -x "$CONFIG_SCRIPT" ]; then
        echo "Error: scripts/config not found. Need a full kernel tree."
        exit 1
    fi

    enable_opt() { "$CONFIG_SCRIPT" --file "$KERNEL_DIR/.config" --enable "$1" 2>/dev/null || true; }
    disable_opt() { "$CONFIG_SCRIPT" --file "$KERNEL_DIR/.config" --disable "$1" 2>/dev/null || true; }

    echo "Applying kernel options for RK3566 display and sound..."

    # Disable unwanted options FIRST, before olddefconfig resolves dependencies.
    # Previously these ran after olddefconfig, causing an oscillation where
    # olddefconfig re-enabled them (as dependencies), then disable_opt turned
    # them off again — .config content changed on every consecutive run.
    disable_opt CONFIG_COMPILE_TEST
    disable_opt CONFIG_CROS_EC
    disable_opt CONFIG_I2C_BCM_IPROC
    disable_opt CONFIG_I2C_BRCMSTB
    disable_opt CONFIG_I2C_RCAR
    disable_opt CONFIG_I2C_UNIPHIER
    disable_opt CONFIG_I2C_UNIPHIER_F
    disable_opt CONFIG_SERIAL_MSM
    disable_opt CONFIG_PTP_1588_CLOCK
    disable_opt CONFIG_POWER_RESET_SYSCON_POWEROFF
    disable_opt CONFIG_POWER_RESET_SYSCON
    disable_opt CONFIG_SYSCON_REBOOT_MODE

    enable_opt CONFIG_ROCKCHIP_IOMMU
    enable_opt CONFIG_DRM
    enable_opt CONFIG_DRM_KMS_HELPER
    enable_opt CONFIG_DRM_FBDEV_EMULATION
    enable_opt CONFIG_DRM_PANEL
    enable_opt CONFIG_DRM_ROCKCHIP
    enable_opt CONFIG_ROCKCHIP_VOP2
    enable_opt CONFIG_ROCKCHIP_DW_HDMI
    enable_opt CONFIG_ROCKCHIP_DW_MIPI_DSI
    enable_opt CONFIG_GENERIC_PHY
    enable_opt CONFIG_GENERIC_PHY_MIPI_DPHY
    enable_opt CONFIG_PHY_ROCKCHIP_INNO_DSIDPHY
    # BACKLIGHT_CLASS_DEVICE must be =y so DRM_PANEL_SIMPLE can be =y (Kconfig constraint)
    enable_opt CONFIG_BACKLIGHT_CLASS_DEVICE
    # PWM backlight driver + Rockchip PWM controller: required for LCD backlight (pwm4)
    enable_opt CONFIG_BACKLIGHT_PWM
    enable_opt CONFIG_PWM
    enable_opt CONFIG_PWM_ROCKCHIP
    enable_opt CONFIG_DRM_PANEL_SIMPLE
    enable_opt CONFIG_SOUND
    enable_opt CONFIG_SND
    enable_opt CONFIG_SND_SOC
    enable_opt CONFIG_SND_SOC_ROCKCHIP
    enable_opt CONFIG_SND_SOC_ROCKCHIP_I2S
    enable_opt CONFIG_SND_SOC_ROCKCHIP_I2S_TDM
    enable_opt CONFIG_SND_SOC_RK817
    # RK8XX MFD: modern kernels split into MFD_RK8XX (core) + MFD_RK8XX_I2C (bus);
    # CONFIG_MFD_RK808 no longer exists. MFD_RK8XX_I2C auto-selects MFD_RK8XX.
    enable_opt CONFIG_MFD_RK8XX_I2C
    enable_opt CONFIG_REGULATOR_RK808
    # HDMI I2S audio: the dw-hdmi-i2s-audio bridge driver that registers hdmi-audio-codec
    enable_opt CONFIG_DRM_DW_HDMI_I2S_AUDIO
    enable_opt CONFIG_SND_SOC_HDMI_CODEC
    enable_opt CONFIG_SND_SIMPLE_CARD
    enable_opt CONFIG_SND_SIMPLE_CARD_UTILS
    # Speaker amplifier driver (simple-audio-amplifier DTS compatible)
    enable_opt CONFIG_SND_SOC_SIMPLE_AMPLIFIER

    # WiFi/Bluetooth support (RTL8733BU combo chip via USB)
    enable_opt CONFIG_WIRELESS
    enable_opt CONFIG_CFG80211
    enable_opt CONFIG_MAC80211
    enable_opt CONFIG_BT
    enable_opt CONFIG_BT_HCIBTUSB
    enable_opt CONFIG_BT_HCIBTUSB_RTL
    enable_opt CONFIG_BT_RTL
    enable_opt CONFIG_RFKILL
    enable_opt CONFIG_USB_ANNOUNCE_NEW_DEVICES

    # Suspend / sleep — critical for handheld battery life.
    # PSCI is provided by TF-A (detected at boot), cpuidle governs C-states.
    enable_opt CONFIG_SUSPEND
    enable_opt CONFIG_PM_SLEEP
    enable_opt CONFIG_PM
    enable_opt CONFIG_CPU_IDLE
    enable_opt CONFIG_ARM_PSCI_CPUIDLE

    # Video / media: VPU (Hantro decoder), VEPU (H.264 encoder), RGA (2D blitter).
    # Without these drivers, the DTS nodes become orphaned power-domain consumers
    # that keep PD_VPU/PD_RGA/PD_RKVENC permanently ON — wasting battery.
    # The Hantro driver matches "rockchip,rk3568-vpu" and "rockchip,rk3568-vepu".
    # RGA driver matches "rockchip,rk3288-rga" (fallback compat for rk3568-rga).
    enable_opt CONFIG_MEDIA_SUPPORT
    enable_opt CONFIG_VIDEO_DEV
    enable_opt CONFIG_V4L_MEM2MEM_DRIVERS
    enable_opt CONFIG_VIDEO_HANTRO
    enable_opt CONFIG_VIDEO_HANTRO_ROCKCHIP
    enable_opt CONFIG_VIDEO_ROCKCHIP_RGA

    # GPU devfreq / frequency scaling (mali_kbase + IPA)
    # ROCKCHIP_THERMAL must be =y (built-in, NOT module) so the gpu-thermal zone
    # exists before mali_kbase loads via S00mali; otherwise IPA fails and devfreq is disabled.
    enable_opt CONFIG_ROCKCHIP_THERMAL
    enable_opt CONFIG_PM_DEVFREQ
    enable_opt CONFIG_DEVFREQ_GOV_SIMPLE_ONDEMAND
    enable_opt CONFIG_DEVFREQ_GOV_PERFORMANCE
    enable_opt CONFIG_DEVFREQ_GOV_POWERSAVE
    enable_opt CONFIG_DEVFREQ_GOV_USERSPACE
    enable_opt CONFIG_DEVFREQ_THERMAL
    enable_opt CONFIG_PM_OPP
    enable_opt CONFIG_THERMAL
    enable_opt CONFIG_THERMAL_OF
    # Power allocator governor: required for mali_kbase IPA (Intelligent Power Allocation)
    enable_opt CONFIG_THERMAL_GOV_POWER_ALLOCATOR

    # DDR bandwidth monitoring (DFI) — required by the rk3568_dmc out-of-tree module.
    # The DFI driver is already in mainline and provides devfreq-event data for
    # DDR utilization, enabling the DMC module to scale DDR frequency.
    enable_opt CONFIG_PM_DEVFREQ_EVENT
    enable_opt CONFIG_DEVFREQ_EVENT_ROCKCHIP_DFI

    enable_opt CONFIG_SPI_ROCKCHIP_SFC
    enable_opt CONFIG_MTD_SPI_NAND
    enable_opt CONFIG_MTD_CMDLINE_PARTS
    #disable_opt CONFIG_FRAMEBUFFER_CONSOLE
    #disable_opt CONFIG_I2C_TEGRA
    #disable_opt CONFIG_I2C_TEGRA_BPMP

    echo "Running olddefconfig..."
    [ -s .config ] && echo "=== kernel build $(date -Iseconds 2>/dev/null || date) ===" > "$KERNEL_LOG"
    # olddefconfig is the FINAL config step — no modifications after this.
    # It resolves Kconfig dependencies and writes a stable .config.
    make olddefconfig 2>&1 | tee -a "$KERNEL_LOG"
fi

# If .config content is unchanged from pre-build snapshot, restore the original
# file to preserve its mtime.  This avoids make re-running syncconfig (which
# regenerates include/generated/autoconf.h and triggers a near-full rebuild).
if [ -f "$KERNEL_DIR/.config.prebuild" ]; then
    if cmp -s "$KERNEL_DIR/.config" "$KERNEL_DIR/.config.prebuild"; then
        mv "$KERNEL_DIR/.config.prebuild" "$KERNEL_DIR/.config"
        echo "Config unchanged — preserved timestamps (fast incremental build)."
    else
        rm -f "$KERNEL_DIR/.config.prebuild"
        echo "Config changed — full rebuild may be required."
    fi
else
    echo "First build (no .config snapshot) — full build expected."
fi

echo "Building kernel (-j$NPROC)... (log: $KERNEL_LOG)"
make -j"$NPROC" Image 2>&1 | tee -a "$KERNEL_LOG"
make -j"$NPROC" dtbs 2>&1 | tee -a "$KERNEL_LOG"

cp -f arch/arm64/boot/Image "$OUTPUT_DIR/"
cp -f arch/arm64/boot/dts/rockchip/rk3566-miyoo-flip.dtb "$OUTPUT_DIR/" 2>/dev/null || true
echo "Done. Image and DTB in $OUTPUT_DIR"
if [ -f "$OUTPUT_DIR/Image" ] && [ -f "$OUTPUT_DIR/rk3566-miyoo-flip.dtb" ]; then
    echo "  Image: $(stat -c %y "$OUTPUT_DIR/Image" 2>/dev/null || stat -f '%Sm' "$OUTPUT_DIR/Image" 2>/dev/null)"
    echo "  DTB:   $(stat -c %y "$OUTPUT_DIR/rk3566-miyoo-flip.dtb" 2>/dev/null || stat -f '%Sm' "$OUTPUT_DIR/rk3566-miyoo-flip.dtb" 2>/dev/null)"
fi
