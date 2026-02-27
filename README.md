# Miyoo Flip — Device Wiki & Reference

This repository is the **maintained wiki and reference** for the **Miyoo Flip** handheld (Rockchip RK3566) on mainline Linux. The documentation is kept up to date as the canonical device reference.

**For a working image and current code** (DTS, drivers, ROCKNIX build system), use **[Zetarancio/distribution](https://github.com/Zetarancio/distribution)** (branch `flip`). This repo focuses on **docs**; build scripts here are outdated and retained for reference only.

---

## Hardware

| Component | Detail                                                |
| --------- | ----------------------------------------------------- |
| SoC       | Rockchip RK3566 (quad Cortex-A55 @ 1.8 GHz)           |
| GPU       | Mali-G52 2EE (Bifrost)                                |
| RAM       | LPDDR4                                                |
| Storage   | SPI NAND 128 MB + 2x MicroSD                          |
| Display   | 640x480 MIPI DSI (FT8006M controller, 2-lane, RGB888) |
| WiFi/BT   | RTL8733BU (USB)                                       |
| Audio     | RK817 codec + speaker amplifier                        |
| PMIC      | RK817 + RK8600 (VDD_CPU)                              |
| UART      | ttyS2 @ 1,500,000 baud (3.3V)                         |

---

## Documentation

**[Full index → docs/README.md](docs/README.md)**

**Part I — This project:** build and flash using this repo’s Makefile/Docker (outdated; instructions kept as reference).

| Guide | Contents |
| ----- | -------- |
| [Hardware & UART](docs/hardware.md) | Specs, serial console wiring, baud rate, SD slots |
| [Building](docs/building.md) | This repo’s Docker build: kernel, rootfs, Make targets |
| [Flashing](docs/flashing.md) | xrock, MASKROM, partition layout; this repo’s output paths |
| [ROCKNIX](docs/rocknix.md) | SD boot procedure, GammaOS loader |

**Part II — Device wiki:** distro-agnostic hardware and driver reference (no dependency on this repo).

| Guide | Contents |
| ----- | -------- |
| [DTS porting](docs/dts-porting.md) | BSP-to-mainline device tree translation |
| [Display](docs/display.md) | DSI panel bring-up, backlight, init sequence |
| [Drivers](docs/drivers.md) | RTL8733BU WiFi/BT and Mali-G52 GPU |
| [Troubleshooting](docs/troubleshooting.md) | Boot hangs, kernel notes, debug bootargs |
| [DDR exploration](docs/ddr/README.md) | DDR init, DMC, boot chain, deep sleep, WiFi power-off |
| [Boot chain](docs/boot-chain.md) | FIT layout, OP-TEE requirement |

Reference boot logs in this repo: `boot_log_ROCKNIX.txt` (mainline; includes DMC after deep-sleep resume); `boot_log_STOCK_INCLUDE_SLEEP_POWEROFF_AND_DEBUG.txt` (stock with DDR/sleep debug); `boot_log_STOCK_INCLUDE_SLEEP_POWEROFF.txt` (stock, sleep/poweroff).

---

## Status

| Subsystem                | Status                | Notes |
| ------------------------ | --------------------- | ----- |
| Boot (U-Boot + kernel)   | Working               | Mainline 6.18+, SPI NAND or SD |
| Display (DSI panel)      | Working               | 640x480, panel driver |
| Backlight                | Working               | PWM4 |
| Audio (RK817)            | Working               | simple-audio-card, speaker amp |
| WiFi (RTL8733BU)         | Working               | Out-of-tree, 6.18+ |
| Bluetooth                | Working               | Unified firmware, btusb re-probe |
| GPU (Mali-G52)           | Working               | mali_kbase + libmali, 200–800 MHz |
| Storage                  | Working               | SPI NAND MTD, both SD slots |
| HDMI                     | Untested              | Disabled in DTS to save power |
| DMC (DDR devfreq)        | Working (out-of-tree) | Scaling + resume confirmed; [docs/ddr/](docs/ddr/) |
| VPU / RGA                | Working               | hantro-vpu, rockchip-rga |
| IEP                      | Not working           | BSP-only (MPP) |
| Suspend                  | Working (out-of-tree) | Requires **rk3568-suspend** for BL31 deep sleep; see [docs/ddr/06](docs/ddr/06-suspend-driver-and-vdd-logic.md) |
| Input (buttons + rumble) | Working               | 17 GPIO buttons, joypad, rumble (PWM5) |

---

## Key Discoveries

Findings that made mainline work on this device (details in the wiki).

- **VSEL register hang:** The BSP DTS uses `rockchip,suspend-voltage-selector` but mainline `fan53555` reads `fcs,suspend-voltage-selector`. Wrong name causes VDD_CPU to drop and the board to hang immediately after "FAN53555 Detected!" on kernels 6.4+.

- **DSI panel init in command mode:** The stock driver sends init commands via a DT property. On mainline, commands must be sent during `prepare()` (command mode), not `enable()` (video mode), or they collide with the video stream on the shared FIFO.

- **PMIC dependency cycles:** `vcc9-supply = <&dcdc_boost>` and sleep pinctrl states create circular dependencies that `fw_devlink` cannot resolve. Fixed by using `<&vccsys>` and removing sleep pinctrl on RK817.

- **DDR on mainline:** The BSP DMC uses Rockchip V2 SIP (shared memory + MCU/IRQ). An out-of-tree DMC devfreq driver implements this for mainline 6.18+ and is confirmed working; see [docs/ddr/](docs/ddr/).

- **Suspend:** Out-of-tree **rk3568-suspend** (not rk356x) configures BL31 **deep sleep**; required for `vdd_logic` off-in-suspend. See [docs/ddr/06-suspend-driver-and-vdd-logic.md](docs/ddr/06-suspend-driver-and-vdd-logic.md).

- **WiFi/BT full poweroff:** The 8733bu driver only does software rfkill; it does not control the power-enable GPIO. Full hardware poweroff of the combo requires a **separate driver** that controls the enable GPIO and integrates with rfkill. See [docs/ddr/07-wifi-bt-combo-power.md](docs/ddr/07-wifi-bt-combo-power.md).

- **Boot chain:** Any U-Boot for this board must include OP-TEE (BL32) in the FIT image; the boot chain expects ATF + OP-TEE + U-Boot. Bootrom/SPL behaviour for SD boot is documented in [docs/boot-chain.md](docs/boot-chain.md) and [docs/ddr/](docs/ddr/).

---

## Project structure

```
docs/                          Documentation wiki (maintained)
boot_log_ROCKNIX.txt           Mainline boot log (DMC after resume confirmed)
boot_log_STOCK_INCLUDE_SLEEP_POWEROFF_AND_DEBUG.txt   Stock with DDR/sleep debug
boot_log_STOCK_INCLUDE_SLEEP_POWEROFF.txt             Stock, sleep/poweroff capture
patches/                       Kernel patches (reference; current in distribution)
build-*.sh                      Build scripts (outdated)
Makefile, Dockerfile            Docker-based build (outdated)
rk3566-miyoo-flip.dts          Mainline DTS (reference; current in distribution)
```

**Wiki:** The `docs/` tree is the device wiki and is maintained.

**Boot logs:** In repo root — `boot_log_ROCKNIX.txt` (mainline, DMC after resume); `boot_log_STOCK_INCLUDE_SLEEP_POWEROFF_AND_DEBUG.txt` (stock + debug); `boot_log_STOCK_INCLUDE_SLEEP_POWEROFF.txt` (stock).

**Build system:** Scripts and layout in this repo are **outdated**. For current builds and images use [Zetarancio/distribution](https://github.com/Zetarancio/distribution). Historical build and flash steps are in [docs/building.md](docs/building.md) and [docs/flashing.md](docs/flashing.md).

---

## Quick start

For a **current image and build**, use the [Zetarancio/distribution](https://github.com/Zetarancio/distribution) (ROCKNIX, branch `flip`) repo.

For **historical** build and flash (this repo’s Makefile/Docker):

```bash
# 1. Download steward-fu assets (SDK toolchain, U-Boot, firmware)
./setup-extra.sh

# 2. Download mainline kernel, WiFi driver, and Mali GPU driver
make download-kernel download-wifi download-mali

# 3. Build everything in Docker
make build

# 4. Flash to device via xrock (MASKROM mode)
# xrock download ... ; xrock flash write ...
```

See [docs/building.md](docs/building.md) for the full build guide and [docs/flashing.md](docs/flashing.md) for flashing details.

---

## External references

**Datasheets & TRM (Rockchip)**

| Document | URL |
| -------- | --- |
| RK3566 Datasheet V1.2 | [FriendlyElec wiki](https://wiki.friendlyelec.com/wiki/images/8/89/Rockchip_RK3566_Datasheet_V1.2-20220930.pdf) |
| RK3568 TRM Part 1 | [Radxa](https://dl.radxa.com/rock3/docs/hw/datasheet/Rockchip%20RK3568%20TRM%20Part1%20V1.1-20210301.pdf) |
| RK3568 TRM Part 2 | [Radxa](https://dl.radxa.com/rock3/docs/hw/datasheet/Rockchip%20RK3568%20TRM%20Part2%20V1.1-20210301.pdf) |

**steward-fu’s Miyoo Flip pages**

| Topic     | URL |
| --------- | --- |
| UART      | [miyoo_flip_uart.htm](https://steward-fu.github.io/website/handheld/miyoo_flip_uart.htm) |
| Specs     | [miyoo_flip_spec.htm](https://steward-fu.github.io/website/handheld/miyoo_flip_spec.htm) |
| Pin mapping | [miyoo_flip_pin.htm](https://steward-fu.github.io/website/handheld/miyoo_flip_pin.htm) |
| MTD       | [miyoo_flip_mtd.htm](https://steward-fu.github.io/website/handheld/miyoo_flip_mtd.htm) |
| Assets    | [GitHub release (miyoo-flip)](https://github.com/steward-fu/website/releases/tag/miyoo-flip) |

**Related projects**

- **[Zetarancio/distribution](https://github.com/Zetarancio/distribution)** — Current ROCKNIX Miyoo Flip (branch `flip`)
- [ROCKNIX](https://rocknix.org/)
- [GammaOS Core](https://github.com/TheGammaSqueeze/GammaOSCore)

**Other reference**

- [Rosa1337/rk3568_linux](https://github.com/Rosa1337/rk3568_linux)

---

## License

Documentation and scripts: [GNU GPL v2](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html). DTS/patches follow kernel GPL v2. Third-party components have their own licenses.

---

## Thanks

Thanks to [steward-fu](https://github.com/steward-fu) for the Miyoo Flip resource site and assets; [beebono](https://github.com/beebono), [sydarn](https://github.com/sydarn), and the community behind [SpruceOS](https://spruceui.github.io/) for their work and support. This project wouldn’t be where it is without them.
