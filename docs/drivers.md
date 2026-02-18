# Drivers: WiFi/Bluetooth & GPU

## RTL8733BU WiFi/Bluetooth

### Overview

The Miyoo Flip uses a Realtek RTL8733BU USB combo module for WiFi
(802.11ac) and Bluetooth. The driver is built out-of-tree from
[ROCKNIX/RTL8733BU](https://github.com/ROCKNIX/RTL8733BU) (branch
`v5.15.12-126-wb`).

### Architecture

```
WiFi:  rtl8733bu.ko ──> cfg80211/mac80211 ──> wlan0
BT:    btusb + btrtl (in-tree) ──> hci0
Firmware: unified file shared by WiFi and BT subsystems
```

The WiFi driver uploads unified firmware (WiFi + BT coexistence). An
init script handles load ordering:

1. `insmod rtl8733bu.ko` -- chip receives firmware
2. Unbind/rebind btusb -- btrtl re-probes with firmware on chip
3. `hciconfig hci0 up` -- Bluetooth operational

### Building

```bash
make download-wifi        # Clone driver + apply kernel 6.19 patch
make build-wifi           # Build module, install firmware
```

The build script (`build-rtl8733bu.sh`) handles:
- Makefile reconfiguration for cross-compilation
- `EXTRA_CFLAGS` -> `ccflags-y` conversion (kernel 6.19+)
- Absolute include paths (kbuild `$(src)` unreliable in 6.19)
- `halmac` symlink fix
- Firmware installation from stock sysroot

### Kernel Configuration

```
CONFIG_WIRELESS=y
CONFIG_CFG80211=y
CONFIG_MAC80211=y
CONFIG_BT=y
CONFIG_BT_HCIBTUSB=y
CONFIG_BT_HCIBTUSB_RTL=y
CONFIG_BT_RTL=y
CONFIG_RFKILL=y
```

### Kernel 6.19 Compat Patch

`patches/0002-rtl8733bu-linux-6.19-compat.patch` fixes:

| File | Fix |
|------|-----|
| `sha256*.c/h` | `hmac_sha256` -> `rtw_hmac_sha256` (symbol conflict) |
| `osdep_service_linux.h` | Timer API: `del_timer_sync()` -> `timer_delete_sync()` |
| `halmac_type.h` | Missing enum values |
| `hal8733b_fw.c/h` | Firmware stub arrays for file-based loading |
| `ioctl_cfg80211.c` | `radio_idx`/`link_id` params for kernel 6.11+ |

### Testing

```bash
lsmod | grep rtl              # Module loaded
ip link show                   # Look for wlan0
iwlist wlan0 scan              # Scan networks
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf
dhcpcd wlan0

# Bluetooth
hciconfig hci0 up
hcitool scan
```

### Firmware Files

WiFi/BT firmware comes from the stock sysroot
(`Extra/flip-sysroot/usr/lib/firmware/`):
- `rtl8733bu_fw` -- unified WiFi+BT firmware
- `rtl8733bu_config` -- configuration blob

The build script copies these to the Buildroot rootfs target.

---

## Mali-G52 GPU

### Overview

The RK3566 has a **Mali-G52 2EE** (Bifrost architecture) GPU.

| | mali_kbase + libmali | Mesa Panfrost |
|---|---|---|
| OpenGL ES | 3.2 | 3.1 |
| Vulkan | No (Linux) | 1.1+ (panvk) |
| Performance | Higher | ~70-80% |
| Kernel driver | `mali_kbase.ko` (out-of-tree) | `panfrost` (mainline) |
| License | Proprietary (ARM) | MIT/GPL |

This project uses **mali_kbase + libmali** for best GLES performance.

### Components

**mali_kbase (r54p2)** -- kernel module from
[ROCKNIX/mali_kbase](https://github.com/ROCKNIX/mali_kbase) (branch
`bifrost_port`). Loaded at boot via `/etc/init.d/S00mali`. Creates
`/dev/mali0`.

**libmali (g24p0)** -- Rockchip userspace blob from
[JeffyCN/mirrors](https://github.com/JeffyCN/mirrors) (branch
`libmali`). Single "mega-library" providing EGL, GLES, GBM, OpenCL.
Blob: `libmali-bifrost-g52-g24p0-gbm.so`.

**DTS Patch** -- `0008-arm64-dts-rockchip-add-support-for-mali-bifrost-driv.patch`
adds `resets`, `power_policy`, and `power_model` to the GPU DTS node.
Required for IPA (thermal) and devfreq.

### Building

```bash
make download-mali        # Clone mali_kbase + libmali (sparse)
make build-mali           # Build module, install library + headers
make rootfs-img           # Repack rootfs with GPU driver
```

### GPU OPP Table

| Frequency | Voltage |
|-----------|---------|
| 200 MHz | 850 mV |
| 300 MHz | 850 mV |
| 400 MHz | 850 mV |
| 600 MHz | 900 mV |
| 700 MHz | 950 mV |
| 800 MHz | 1000 mV |

### Panfrost Conflict

Both `panfrost` and `mali_kbase` match `compatible = "arm,mali-bifrost"`.
The build script:
- Blacklists panfrost via `/etc/modprobe.d/mali.conf`
- `CONFIG_DRM_PANFROST` must be `=m` or `=n`, never `=y`

### Verification

```bash
lsmod | grep mali                                          # mali_kbase loaded
ls -la /dev/mali0                                          # Device node
cat /sys/class/devfreq/fde60000.gpu/cur_freq               # Current freq
cat /sys/class/devfreq/fde60000.gpu/available_frequencies   # All OPPs
cat /sys/class/devfreq/fde60000.gpu/governor                # simple_ondemand
```

### Known Harmless Warnings

- `error -ENXIO: IRQ JOB/MMU/GPU not found` -- uppercase vs lowercase
  interrupt names; falls back to positional lookup
- `Couldn't update frequency transition information` -- one-time devfreq
  stats init; DVFS works normally
