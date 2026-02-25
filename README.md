# Miyoo Flip — Mainline Linux & Reverse Engineering

Reverse engineering notes, mainline kernel port, and build system for the
**Miyoo Flip** handheld gaming device (Rockchip RK3566 SoC).

> **Project status:** The **build system and scripts in this repo are outdated**.
> Active development (DTS, drivers, suspend, joypad, VPU/RGA, DMC, etc.) happens in
> **[Zetarancio/distribution](https://github.com/Zetarancio/distribution)** (branch `flip`) — ROCKNIX.
> This repo is kept for **documentation and wiki**; the wiki will be updated as the
> reference for the device. For a working image and current code, use the ROCKNIX
> distribution.

This repository documents the process of bringing **mainline Linux** to
the Miyoo Flip, replacing the stock Rockchip BSP 5.10 kernel.

## Hardware

| Component | Detail |
|-----------|--------|
| SoC | Rockchip RK3566 (quad Cortex-A55 @ 1.8 GHz) |
| GPU | Mali-G52 2EE (Bifrost) |
| RAM | LPDDR4 |
| Storage | SPI NAND 128 MB + 2x MicroSD |
| Display | 640x480 MIPI DSI (FT8006M controller, 2-lane, RGB888) |
| WiFi/BT | RTL8733BU (USB) |
| Audio | RK817 codec + speaker amplifier |
| PMIC | RK817 + RK8600 (VDD_CPU) |
| UART | ttyS2 @ 1,500,000 baud (3.3V) |

## Key Discoveries

These are the main reverse engineering findings that made mainline Linux work:

- **VSEL register hang**: The BSP DTS uses `rockchip,suspend-voltage-selector`
  but mainline `fan53555` reads `fcs,suspend-voltage-selector`. Wrong name causes
  VDD_CPU to drop, hard-hanging the board immediately after `FAN53555 Detected!`
  on kernels 6.4+.

- **DSI panel init in command mode**: The stock `simple-panel-dsi` driver sends
  init commands via a DT property. On mainline, commands must be sent during
  `prepare()` (command mode), not `enable()` (video mode), or they collide with
  the video stream on the shared FIFO.

- **PMIC dependency cycles**: `vcc9-supply = <&dcdc_boost>` and sleep pinctrl
  states create circular dependencies that `fw_devlink` cannot resolve. Fixed
  by using `<&vccsys>` and removing sleep pinctrl.

- **MTD partition layout**: 5 partitions on SPI NAND (vnvm, uboot, boot, rootfs,
  userdata). Boot partition holds an Android-format `boot.img`. Root is squashfs
  at `/dev/mtdblock3`.

- **GammaOS SPL MMC timeout**: The GammaOS SPL gives SD cards only ~9 ms for
  voltage negotiation (most need 50-250 ms). Zeroing the SPI NAND preloader
  forces the bootrom to fall through to SD card boot.

- **DDR on mainline**: The BSP DMC uses Rockchip V2 SIP (shared memory + MCU/IRQ).
  An out-of-tree DMC devfreq driver implements this for mainline 6.18+ and is
  confirmed working (see [docs/ddr/](docs/ddr/)).

- **U-Boot and OP-TEE**: Any U-Boot for this board must include OP-TEE (BL32) in
  the FIT image; the boot chain expects ATF + OP-TEE + U-Boot.

## Project Structure

```
rk3566-miyoo-flip.dts          Mainline device tree (core deliverable)
patches/                       Kernel patches (display panel, Mali DTS, WiFi compat)
build-*.sh                     Build scripts (kernel, U-Boot, rootfs, drivers)
download-*.sh                  Source download scripts (kernel, WiFi, Mali)
setup-extra.sh                 Download steward-fu assets into Extra/
Makefile                       Docker-based build orchestration
Dockerfile                     Build environment container
rootfs-overlay-serial/         Buildroot overlay (serial getty, WiFi/BT init)
modules/rk3568_dmc/            DDR devfreq module (requires BSP headers)
boot_log_STOCK_INCLUDE_SLEEP_POWEROFF.txt   Stock OS serial UART capture (sleep/poweroff; in this repo)
boot_log_ROCKNIX.txt                        Current mainline/ROCKNIX boot log (in this repo)
STEWARD-FU-NOT STOCK.txt                    **Outdated** — past project state; lacks ROCKNIX drivers (see notice below)
docs/                          Documentation wiki (maintained)
Extra/                         Downloaded assets (populated by setup-extra.sh)
```

**Boot logs:** Stock (BSP) capture with sleep/poweroff: `boot_log_STOCK_INCLUDE_SLEEP_POWEROFF.txt`. Current mainline/ROCKNIX: `boot_log_ROCKNIX.txt` (both in this repo).

**Outdated project files:** `STEWARD-FU-NOT STOCK.txt` is a historical boot log / project snapshot. It does **not** reflect current status and does **not** include the drivers and work done in ROCKNIX (DMC devfreq, rk356x-suspend, joypad/rumble, VPU/RGA, DTS, etc.). For current behaviour and builds, use [Zetarancio/distribution](https://github.com/Zetarancio/distribution).

## Quick Start

```bash
# 1. Download steward-fu assets (SDK toolchain, U-Boot, firmware)
./setup-extra.sh

# 2. Download mainline kernel, WiFi driver, and Mali GPU driver
make download-kernel download-wifi download-mali

# 3. Build everything in Docker
make build

# 4. Flash to device via xrock (MASKROM mode)
xrock download output/rk356x_spl_loader_v1.23.114.bin
sleep 1 && xrock flash && sleep 1
xrock flash write 6144  output/uboot.img
xrock flash write 14336 output/boot.img
xrock flash write 92160 output/rootfs.squashfs
```

See [docs/building.md](docs/building.md) for the full build guide and
[docs/flashing.md](docs/flashing.md) for flashing details.

## Documentation

**Part I — This project:** build, flash, structure.

| Guide | Contents |
|-------|----------|
| [Hardware & UART](docs/hardware.md) | Specs, serial console wiring, pinout, baud rate |
| [Building](docs/building.md) | Full build guide, kernel config, Docker workflow |
| [Flashing](docs/flashing.md) | xrock flashing, MASKROM mode, partition layout |
| [ROCKNIX](docs/rocknix.md) | SD card boot via GammaOS loader, ROCKNIX integration |

**Part II — Device wiki:** distro-agnostic hardware and driver notes.

| Guide | Contents |
|-------|----------|
| [DTS Porting](docs/dts-porting.md) | BSP-to-mainline device tree translation table |
| [Display](docs/display.md) | DSI panel bring-up, backlight, init sequence |
| [Drivers](docs/drivers.md) | RTL8733BU WiFi/BT and Mali-G52 GPU |
| [Troubleshooting](docs/troubleshooting.md) | Boot log issues, kernel version notes, debugging |
| [DDR exploration](docs/ddr/README.md) | DDR init, DMC, boot chain, out-of-tree mainline driver |
| [Boot chain](docs/boot-chain.md) | FIT layout, OP-TEE requirement (optional read) |

## External References

### steward-fu's Miyoo Flip Pages

| Topic | URL |
|-------|-----|
| UART serial | https://steward-fu.github.io/website/handheld/miyoo_flip_uart.htm |
| Extract kernel | https://steward-fu.github.io/website/handheld/miyoo_flip_extract_kernel.htm |
| FIT image | https://steward-fu.github.io/website/handheld/miyoo_flip_fit.htm |
| Device info | https://steward-fu.github.io/website/handheld/miyoo_flip_dev.htm |
| dmesg | https://steward-fu.github.io/website/handheld/miyoo_flip_dmesg.htm |
| Specs | https://steward-fu.github.io/website/handheld/miyoo_flip_spec.htm |
| Pin mapping | https://steward-fu.github.io/website/handheld/miyoo_flip_pin.htm |
| Memory info | https://steward-fu.github.io/website/handheld/miyoo_flip_meminfo.htm |
| kallsyms | https://steward-fu.github.io/website/handheld/miyoo_flip_kallsyms.htm |
| OverlayFS | https://steward-fu.github.io/website/handheld/miyoo_flip_overlayfs.htm |
| MTD layout | https://steward-fu.github.io/website/handheld/miyoo_flip_mtd.htm |
| Assets | https://github.com/steward-fu/website/releases/tag/miyoo-flip |

### Related Projects

- **Current ongoing project:** [Zetarancio/distribution](https://github.com/Zetarancio/distribution) — ROCKNIX-style distribution with Miyoo Flip support (branch `flip`).
- [ROCKNIX](https://rocknix.org/) — immutable Linux for handheld gaming
- [GammaOS Core](https://github.com/TheGammaSqueeze/GammaOSCore) — alternative OS with bootloader installer

## Status

| Subsystem | Status | Notes |
|-----------|--------|-------|
| Boot (U-Boot + kernel) | Working | Mainline 6.18+, boots from SPI NAND or SD |
| Display (DSI panel) | Working | 640x480, init sequence in panel driver |
| Backlight (PWM) | Working | PWM4, CONFIG_BACKLIGHT_PWM=y |
| Audio (RK817 codec) | Working | simple-audio-card, speaker amplifier |
| WiFi (RTL8733BU) | Working | Out-of-tree driver, kernel 6.18+ compat |
| Bluetooth | Working | Unified firmware, btusb re-probe |
| GPU (Mali-G52) | Working | mali_kbase + libmali, DVFS 200-800 MHz |
| Storage (SPI NAND) | Working | MTD partitions, squashfs root |
| SD cards | Working | Both slots |
| HDMI | Untested | Should work; disabled in DTS to save power (no connector on device) |
| DMC (DDR devfreq) | Working (out-of-tree) | Mainline 6.18+; see [docs/ddr/](docs/ddr/) |
| VPU / RGA | Working | Mainline hantro-vpu (dec/enc), rockchip-rga |
| IEP | Not working | BSP-only (MPP), no mainline driver |
| Suspend | Working | rk356x-suspend (BL31 deep sleep), regulator-state-mem |
| Input (buttons + rumble) | Working | All 17 GPIO buttons, volume, lid; joypad + rumble (PWM5) |

## License

Build scripts and documentation are provided under the terms of the
[GNU GPL v2](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html).
The mainline DTS and kernel patches follow the kernel's GPL v2 license.
Third-party components (libmali, stock firmware) are under their
respective licenses.

## Thanks 
Steward-fu and the amazing site he created.

