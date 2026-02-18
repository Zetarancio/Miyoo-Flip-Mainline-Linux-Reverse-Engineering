# Building

The build system uses Docker to provide a consistent cross-compilation
environment. All build artifacts go to `output/`.

## Prerequisites

- Docker
- ~2 GB free disk for the Docker image
- ~1 GB for `Extra/` assets (downloaded by `setup-extra.sh`)
- ~2 GB for kernel source (cloned by `download-kernel.sh`)

## Setup

```bash
# 1. Download steward-fu assets (SDK toolchain, U-Boot sources, firmware)
./setup-extra.sh

# 2. Download mainline kernel, WiFi driver, Mali GPU driver
make download-kernel      # clones mainline Linux + applies patches
make download-wifi        # clones RTL8733BU driver + applies compat patch
make download-mali        # clones mali_kbase + libmali (sparse checkout)
```

## Build Order

```bash
make build-kernel         # Kernel Image + DTB
make build-rootfs         # Buildroot rootfs (first run ~30-60 min for toolchain)
make build-wifi           # RTL8733BU WiFi module + BT firmware
make build-mali           # mali_kbase.ko + libmali userspace
make boot-img             # Pack boot.img (kernel + DTB, Android format)
make rootfs-img           # Pack rootfs.squashfs (with modules + firmware)
```

Or build everything at once:

```bash
make build                # Runs all steps in sequence
```

## Build Outputs

| File | Description |
|------|-------------|
| `output/Image` | Uncompressed kernel |
| `output/Image.lz4` | LZ4-compressed kernel (fits 38 MB boot partition) |
| `output/rk3566-miyoo-flip.dtb` | Device tree blob |
| `output/boot.img` | Android boot image (kernel + DTB) |
| `output/rootfs.squashfs` | Root filesystem |
| `output/uboot.img` | U-Boot FIT image |
| `output/modules/` | Out-of-tree kernel modules |
| `output/firmware/` | WiFi/BT firmware |

## Make Targets

| Target | Description |
|--------|-------------|
| `make build` | Build everything (kernel + rootfs + drivers + images) |
| `make build-kernel` | Kernel only (uses host DTS if available) |
| `make build-rootfs` | Buildroot rootfs only |
| `make build-uboot` | U-Boot only |
| `make build-wifi` | RTL8733BU WiFi/BT module |
| `make build-mali` | Mali GPU driver (kernel module + userspace) |
| `make build-dmc` | DDR devfreq module (requires BSP headers) |
| `make boot-img` | Pack boot.img from Image + DTB |
| `make rootfs-img` | Pack rootfs.squashfs from Buildroot target |
| `make shell` | Interactive Docker shell |
| `make clean` | Clean output files |
| `make clean-kernel` | Clean kernel tree (forces full rebuild) |
| `make clean-rootfs` | Remove Buildroot target/images (keeps toolchain) |
| `make download-kernel` | Clone mainline kernel + apply patches |
| `make download-wifi` | Clone RTL8733BU + apply compat patch |
| `make download-mali` | Clone mali_kbase + libmali |
| `make help` | Show all targets |

## Kernel Configuration

`build-kernel.sh` starts from `defconfig` and enables options for the
Miyoo Flip hardware. Key categories:

### Display

- `CONFIG_DRM_ROCKCHIP`, `CONFIG_ROCKCHIP_VOP2`, `CONFIG_ROCKCHIP_DW_MIPI_DSI`
- `CONFIG_DRM_PANEL_SIMPLE` (includes `miyoo,flip-panel` definition)
- `CONFIG_BACKLIGHT_PWM`, `CONFIG_PWM_ROCKCHIP`
- `CONFIG_PHY_ROCKCHIP_INNO_DSIDPHY`

### Sound

- `CONFIG_SND_SOC_ROCKCHIP_I2S_TDM`, `CONFIG_SND_SOC_RK817`
- `CONFIG_SND_SIMPLE_CARD`, `CONFIG_SND_SOC_SIMPLE_AMPLIFIER`

### Storage

- `CONFIG_SPI_ROCKCHIP_SFC`, `CONFIG_MTD_SPI_NAND`, `CONFIG_MTD_CMDLINE_PARTS`

### WiFi / Bluetooth

- `CONFIG_CFG80211`, `CONFIG_MAC80211`, `CONFIG_WIRELESS`
- `CONFIG_BT`, `CONFIG_BT_HCIBTUSB`, `CONFIG_BT_HCIBTUSB_RTL`, `CONFIG_BT_RTL`

### GPU (thermal + devfreq)

- `CONFIG_ROCKCHIP_THERMAL=y` -- **must be built-in**, not module
- `CONFIG_PM_DEVFREQ`, `CONFIG_DEVFREQ_GOV_SIMPLE_ONDEMAND`
- `CONFIG_DEVFREQ_THERMAL`, `CONFIG_PM_OPP`
- `CONFIG_DRM_PANFROST=m` -- must be module or disabled (conflicts with mali_kbase)

### Critical Notes

| Config | Must Be | Why |
|--------|---------|-----|
| `ROCKCHIP_THERMAL` | `=y` | gpu-thermal zone must exist before mali_kbase loads |
| `DRM_PANFROST` | `=m` or `=n` | Conflicts with mali_kbase; blacklisted at runtime |

## DTS Workflow

The mainline DTS (`rk3566-miyoo-flip.dts`) lives at the project root.
`build-kernel.sh` copies it into the kernel tree at build time, so you
can edit the DTS without touching the kernel source:

```bash
# Edit DTS
vim rk3566-miyoo-flip.dts

# Rebuild (no clean-kernel needed for DTS-only changes)
make build-kernel && make boot-img
```

## Patches

Applied automatically by the download scripts:

| Patch | Applied By | Purpose |
|-------|-----------|---------|
| `0001-miyoo-flip-display-and-drm-support.patch` | `download-kernel.sh` | DSI panel driver in panel-simple.c |
| `0008-arm64-dts-rockchip-add-support-for-mali-bifrost-driv.patch` | `download-kernel.sh` | Mali IPA/devfreq DTS support |
| `0002-rtl8733bu-linux-6.19-compat.patch` | `download-wifi-driver.sh` | WiFi driver kernel 6.19+ fixes |

## Kernel Branch

Default: `linux-6.6.y` (LTS). Change with:

```bash
KERNEL_BRANCH=linux-6.12.y make download-kernel
KERNEL_BRANCH=latest make download-kernel      # newest stable
```

## Rebuilding

```bash
# DTS change only (fast)
make build-kernel && make boot-img

# Full kernel rebuild
make clean-kernel && make build-kernel && make boot-img

# Rootfs rebuild (serial overlay applied fresh)
make clean-rootfs && make build-rootfs && make build-wifi && make build-mali && make rootfs-img

# From scratch
rm -rf kernel/ RTL8733BU/ mali-bifrost/ libmali/
make download-kernel download-wifi download-mali
make build-kernel && make build-rootfs && make build-wifi && make build-mali
make boot-img && make rootfs-img
```

## Docker Details

The Dockerfile installs cross-compilation tools on Ubuntu 22.04. Large
directories (`Extra/`, `kernel/`, `buildroot/`, `output/`) are
bind-mounted at runtime, not copied into the image.

The entrypoint (`docker-entrypoint.sh`) auto-detects the cross-compiler:
1. SDK Buildroot toolchain (`Extra/miyoo355_sdk_release/host/bin/`)
2. Flip toolchain (`Extra/flip/`) as fallback
3. System `aarch64-linux-gnu-` as last resort
