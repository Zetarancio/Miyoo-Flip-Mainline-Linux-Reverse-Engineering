# Drivers: WiFi/Bluetooth & GPU

Device reference for the RTL8733BU WiFi/BT combo and Mali-G52 GPU. **Hardware and driver behaviour** are distro-agnostic. Build/test flows are distribution-specific; for current images use [Zetarancio/distribution](https://github.com/Zetarancio/distribution) branch `flip`.

## RTL8733BU WiFi/Bluetooth

### Overview

The Miyoo Flip uses a Realtek RTL8733BU USB combo module for WiFi
(802.11ac) and Bluetooth. **WiFi works** with the out-of-tree 8733bu driver from
[Awesome-Embedded-Learning-Studio/rtl8733bu-linux-driver](https://github.com/Awesome-Embedded-Learning-Studio/rtl8733bu-linux-driver)
(wirenboard base, in-tree Kbuild port). `flip` pins
[`c46aa25e`](https://github.com/Awesome-Embedded-Learning-Studio/rtl8733bu-linux-driver/commit/c46aa25e237cb43f33390cf58eee5c69d9b32883)
— the last commit that still builds against Linux **7.0.2**. The branch tip
rewires `cfg80211_ops` for 7.1 MLO and will not compile until RK3566 moves
kernel. That tree already carries Kbuild, USB/CFG80211, and WPA3/SAE
(`IEEE80211W`). The 7.1-port switch ([3c149fbb](https://github.com/Zetarancio/distribution/commit/3c149fbbf9)) dropped eight old patches; four **local** ones are back on `flip` because the upstream tree still lacks them:

| Patch | Why it exists |
|-------|----------------|
| **001** [39d9bb5](https://github.com/Zetarancio/distribution/commit/39d9bb5fe3) | `usb_register_driver()` overwrites `driver.shutdown`; hook `usb_driver.shutdown` so `rtw_dev_shutdown()` actually runs. |
| **002** same commit | Bound the `bips_processing` wait at 500 ms; dedicated `reset_resume`. |
| **003** [6126f46](https://github.com/Zetarancio/distribution/commit/6126f46bdf) | Shutdown path must not indicate disconnect after cfg80211 already released the BSS (`cfg80211_put_bss` UAF → panic → **warm reboot** instead of power-off). |
| **004** [71db6a9](https://github.com/Zetarancio/distribution/commit/71db6a938b) | Same double-release on a userspace disconnect (`nmcli device disconnect wlan1`). |

Do not re-apply the dropped compat/WPA3/LPS/autosuspend set — those live in the 7.1-port tree. The module handles USB and WiFi; Bluetooth is in-tree `btusb` + `btrtl`; rfkill is software on/off.

Runtime tunables live in `modprobe.d/8733bu.conf` (`rtw_ips_mode=0
rtw_power_mgnt=1 rtw_lps_level=1 rtw_enusbss=0`). WOWLAN is compiled in
on this tree — watch it during suspend testing.

### Optional: GPIO-level power-off

The 8733bu driver does not control the power-enable GPIO. When WiFi and BT are off in settings, the chip stays powered and draws standby current. If you want to **shut down the combo at the GPIO level** (full hardware power-off when both radios are off, for maximum battery savings), you can use an **optional separate driver** that owns the enable GPIO and ties it to rfkill. See [WiFi/BT power-off](wifi-bt-power-off.md) for the rationale and typical implementation.

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

Clone [Awesome-Embedded-Learning-Studio/rtl8733bu-linux-driver](https://github.com/Awesome-Embedded-Learning-Studio/rtl8733bu-linux-driver) at the pin above and build as an in-tree module (`CONFIG_RTL8733BU=m`). Apply only the four `flip` patches above (001–004). Legacy build scripts are on branch `buildroot`.

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

WiFi/BT firmware comes from the stock sysroot, under
`usr/lib/firmware/` (extract it from a stock rootfs, e.g. the
[firmware dumps](../stock-firmware-and-findings.md) in this repo):
- `rtl8733bu_fw` -- unified WiFi+BT firmware
- `rtl8733bu_config` -- configuration blob

Install these to your rootfs firmware directory (e.g. `/usr/lib/firmware/`).

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

### Components

**mali_kbase (r54p2)** -- kernel module from
[ROCKNIX/mali_kbase](https://github.com/ROCKNIX/mali_kbase) (branch
`bifrost_port`). Loaded at boot via `/etc/init.d/S00mali`. Creates
`/dev/mali0`.

**libmali (g29p1 on RK3566 `flip`)** -- Rockchip userspace blob.
Blob: `libmali-bifrost-g52-g29p1-gbm.so` ([9f571902](https://github.com/Zetarancio/distribution/commit/9f57190200)). Older wiki text and captures may still say g24p0.

**DTS Patch** -- `0008-arm64-dts-rockchip-add-support-for-mali-bifrost-driv.patch`
adds `resets`, `power_policy`, and `power_model` to the GPU DTS node.
Required for IPA (thermal) and devfreq.

### Building

Clone [ROCKNIX/mali_kbase](https://github.com/ROCKNIX/mali_kbase) (branch `bifrost_port`) and build against your kernel tree. Userspace on current `flip` is **g29p1**, not g24p0. Legacy build scripts are on branch `buildroot`.

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
To avoid conflicts:
- Blacklist panfrost via `/etc/modprobe.d/mali.conf`
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
