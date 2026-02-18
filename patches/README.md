# Miyoo Flip (RK3566) Mainline Kernel Patches

These patches are applied automatically by the build/download scripts.

## Kernel Patches (applied by `download-kernel.sh`)

### 0001-miyoo-flip-display-and-drm-support.patch

**Applies to**: Linux kernel (tested on 6.19)
**Base**: `git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git`

Adds display support for the Miyoo Flip's 640x480 MIPI DSI panel.

| File | Change |
|------|--------|
| `drivers/gpu/drm/panel/panel-simple.c` | Add Miyoo Flip DSI panel driver (FT8006M-based, 640x480, 2-lane DSI, RGB888 burst mode). Includes vendor init sequence. |
| `drivers/gpu/drm/rockchip/rockchip_drm_drv.c` | Use `dev_err_probe()` in `rockchip_drm_bind()` for better deferred-probe debug. |

Note: The DTS file (`rk3566-miyoo-flip.dts`) is maintained separately in the project
root and copied into the kernel tree at build time by `build-kernel.sh`.

### 0008-arm64-dts-rockchip-add-support-for-mali-bifrost-driv.patch

**Applies to**: Linux kernel (tested on 6.19)
**Source**: [ROCKNIX](https://github.com/ROCKNIX/distribution/blob/next/projects/ROCKNIX/devices/RK3566/patches/linux/0008-arm64-dts-rockchip-add-support-for-mali-bifrost-driv.patch)

Adds mali_kbase support to the rk356x GPU device tree node.

| File | Change |
|------|--------|
| `arch/arm64/boot/dts/rockchip/rk356x-base.dtsi` | Add `resets`, `power_policy`, `power_model@0` (mali-simple-power-model with gpu-thermal link), `power_model@1` (mali-g52-power-model) to the GPU node. |

Required for mali_kbase IPA (Intelligent Power Allocation) and devfreq. Without this
patch, mali_kbase cannot register with the thermal framework and disables frequency scaling.

---

## WiFi Driver Patch (applied by `download-wifi-driver.sh`)

### 0002-rtl8733bu-linux-6.19-compat.patch

**Applies to**: ROCKNIX RTL8733BU driver
**Base**: `https://github.com/ROCKNIX/RTL8733BU.git` branch `v5.15.12-126-wb`

Fixes compilation and runtime issues when building against Linux kernel 6.19+.

| File | Change |
|------|--------|
| `core/crypto/sha256*.c/h` | Rename `hmac_sha256` → `rtw_hmac_sha256` (symbol conflict with kernel 6.19) |
| `include/osdep_service_linux.h` | Fix `from_timer()` for kernel ≥6.19; `del_timer_sync()` → `timer_delete_sync()` |
| `hal/phydm/phydm_interface.c` | Same timer API rename |
| `hal/halmac-rs/halmac_type.h` | Add missing enum values |
| `hal/rtl8733b/hal8733b_fw.c/h` | Add firmware stub arrays for file-based loading |
| `include/autoconf.h` | Enable `CONFIG_FILE_FWIMG` |
| `core/rtw_mlme.c` | Fix `vmalloc(0)` on kernel 6.19 |
| `os_dep/linux/ioctl_cfg80211.c` | Add `radio_idx`/`link_id` params for kernel ≥6.11 |

The build script (`build-rtl8733bu.sh`) also handles Makefile changes at build time
(ccflags-y conversion, absolute include paths, halmac symlink).

---

## Bluetooth

Bluetooth works without kernel patches. The WiFi driver uploads unified firmware
(WiFi + BT coexistence). An init script handles load ordering:

1. Load WiFi module → chip receives firmware
2. Unbind/rebind btusb → btrtl re-probes with firmware on chip
3. `hciconfig hci0 up` → BT operational

---

## Reproducing from Scratch

```bash
rm -rf kernel/ RTL8733BU/ mali-bifrost/ libmali/
make download-kernel download-wifi download-mali
make build-kernel && make build-rootfs && make build-wifi && make build-mali
make boot-img && make rootfs-img
```

All patches are applied automatically by the download scripts.
