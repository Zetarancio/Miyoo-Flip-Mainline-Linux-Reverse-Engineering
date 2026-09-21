# Drivers: WiFi/Bluetooth & GPU

Device reference for the RTL8733BU WiFi/BT combo and Mali-G52 GPU. **Hardware and driver behaviour** are distro-agnostic. The patch list below is what the **archived** Miyoo Flip ROCKNIX fork shipped on branch `flip` (Linux 7.0.2, stamp `d249b09bd9`). It is evidence, not the active OS. Active implementation: [Zlyme](../implementations/zlyme.md).

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
(`IEEE80211W`). The 7.1-port switch on that fork ([3c149fbb](https://github.com/Zetarancio/distribution/commit/3c149fbbf9)) dropped eight old patches. Six **local** ones were on `flip` because the upstream tree still lacked the defects they fix, or because that fork did not want a concurrent-mode build:

| Patch | Why it exists |
|-------|----------------|
| **001** [39d9bb5](https://github.com/Zetarancio/distribution/commit/39d9bb5fe3) | `usb_register_driver()` overwrites `driver.shutdown`; hook `usb_driver.shutdown` so `rtw_dev_shutdown()` actually runs. |
| **002** same commit | Bound the `bips_processing` wait at 500 ms; dedicated `reset_resume`. |
| **003** [6126f46](https://github.com/Zetarancio/distribution/commit/6126f46bdf) | Shutdown path must not indicate disconnect after cfg80211 already released the BSS (`cfg80211_put_bss` UAF → panic → **warm reboot** instead of power-off). |
| **004** [ecccdef](https://github.com/Zetarancio/distribution/commit/ecccdef4b9) (rewrote [71db6a9](https://github.com/Zetarancio/distribution/commit/71db6a938b)) | Indicate a disconnect **once**. The driver reports it from several paths; `__cfg80211_disconnected()` releases BSSes on each. Testing `wdev->connected` makes later calls no-ops. An earlier version suppressed the cfg80211 path and left `wdev->connected` set after `nmcli device disconnect`, so iwd's randomized scans returned `-EOPNOTSUPP` and NetworkManager reported “Secrets were required, but not provided”. |
| **005** [6a7ac83](https://github.com/Zetarancio/distribution/commit/6a7ac83e87) | Drop `CONFIG_CONCURRENT_MODE`. The fork registered **wlan0** and **wlan1** for one radio; `wifictl` always picks the first `wlan*`, NetworkManager often associated on wlan1, and `wifictl pin` before suspend pinned nothing. |
| **006** [69d1b17](https://github.com/Zetarancio/distribution/commit/69d1b1714b) | Restore SAE/WPA3 fixes dropped with the 7.1-port switch. PMF compiled in is not SAE. Symptom: connect against a WPA2/WPA3 AP never finishes the association (same NM “Secrets were required” string). |

Do not re-apply the dropped compat/LPS/autosuspend set — those live in the 7.1-port tree. The module handles USB and WiFi; Bluetooth is in-tree `btusb` + `btrtl`; rfkill is software on/off.

Runtime tunables live in `modprobe.d/8733bu.conf` (`rtw_ips_mode=0
rtw_power_mgnt=1 rtw_lps_level=1 rtw_enusbss=0`). WOWLAN is compiled in
on this tree — watch it during suspend testing.

### Optional: GPIO-level power-off

The 8733bu driver does not control the power-enable GPIO. When WiFi and BT are off in settings, the chip stays powered and draws standby current. On the archived ROCKNIX fork, **RTL8733BU-POWER** owned that GPIO, tied it to two rfkill devices, and cut power in **`.suspend_late`** / **`.resume`** ([e728b28](https://github.com/Zetarancio/distribution/commit/e728b28834)), so that tree’s Miyoo Flip `sleep.d` pre/post rfkill quirks were removed ([47fb725](https://github.com/Zetarancio/distribution/commit/47fb7252bc)). See [WiFi/BT power-off](wifi-bt-power-off.md). Zlyme’s equivalent is not recorded here.

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

### Reproducing the archived ROCKNIX driver

This is how the archived [Zetarancio/distribution](https://github.com/Zetarancio/distribution) `flip` tree built the module. It is not a Zlyme instruction, and this wiki does not record what Zlyme builds.

Clone [Awesome-Embedded-Learning-Studio/rtl8733bu-linux-driver](https://github.com/Awesome-Embedded-Learning-Studio/rtl8733bu-linux-driver) at the pin above and build as an in-tree module (`CONFIG_RTL8733BU=m`). Apply that fork’s six local patches **001–006** listed above. Legacy build scripts on branch `buildroot` are older local helpers, not the active OS.

### Checks used on the archived fork

These commands describe that tree’s module once it is loaded. They are not Zlyme setup steps.

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
`bifrost_port`). The archived fork loaded it at boot via `/etc/init.d/S00mali`. It creates
`/dev/mali0`.

**libmali (g29p1 on the archived RK3566 `flip` tree)** -- Rockchip userspace blob.
Blob: `libmali-bifrost-g52-g29p1-gbm.so` ([9f571902](https://github.com/Zetarancio/distribution/commit/9f57190200)). Older wiki text and captures may still say g24p0.

**DTS Patch** -- `0008-arm64-dts-rockchip-add-support-for-mali-bifrost-driv.patch`
adds `resets`, `power_policy`, and `power_model` to the GPU DTS node.
Required for IPA (thermal) and devfreq.

### Reproducing the archived ROCKNIX GPU build

The archived fork used [ROCKNIX/mali_kbase](https://github.com/ROCKNIX/mali_kbase) (branch `bifrost_port`), which is official upstream ROCKNIX’s GPU driver tree, built against that fork’s kernel. Userspace on the archived `flip` tree is **g29p1**, not g24p0. This wiki does not record Zlyme’s GPU userspace. Legacy build scripts on branch `buildroot` are older local helpers.

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
