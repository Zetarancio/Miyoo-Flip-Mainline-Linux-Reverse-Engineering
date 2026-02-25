# Miyoo Flip — Device Wiki & Reference

This repository is the **maintained wiki and reference** for the **Miyoo Flip** handheld (Rockchip RK3566) on mainline Linux. The documentation is kept up to date as the canonical device reference.

**For a working image and current code** (DTS, drivers, ROCKNIX build system), use **[Zetarancio/distribution](https://github.com/Zetarancio/distribution)** (branch `flip`). This repo focuses on **docs**; build scripts here are outdated and retained for reference only.

---

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

---

## Documentation

**[Full index → docs/README.md](docs/README.md)**

**Part I — Build & flash (reference)**  
[Hardware & UART](docs/hardware.md) · [Building](docs/building.md) · [Flashing](docs/flashing.md) · [ROCKNIX](docs/rocknix.md)

**Part II — Device wiki (hardware & drivers)**  
[DTS porting](docs/dts-porting.md) · [Display](docs/display.md) · [Drivers](docs/drivers.md) · [Troubleshooting](docs/troubleshooting.md) · [DDR exploration](docs/ddr/README.md) · [Boot chain](docs/boot-chain.md)

Reference boot logs in this repo: `boot_log_ROCKNIX.txt` (current mainline), `boot_log_STOCK_INCLUDE_SLEEP_POWEROFF.txt` (stock).

---

## Status

| Subsystem | Status | Notes |
|-----------|--------|-------|
| Boot (U-Boot + kernel) | Working | Mainline 6.18+, SPI NAND or SD |
| Display (DSI panel) | Working | 640x480, panel driver |
| Backlight | Working | PWM4 |
| Audio (RK817) | Working | simple-audio-card, speaker amp |
| WiFi (RTL8733BU) | Working | Out-of-tree, 6.18+ |
| Bluetooth | Working | Unified firmware, btusb re-probe |
| GPU (Mali-G52) | Working | mali_kbase + libmali, 200–800 MHz |
| Storage | Working | SPI NAND MTD, both SD slots |
| HDMI | Untested | Disabled in DTS to save power |
| DMC (DDR devfreq) | Working (out-of-tree) | [docs/ddr/](docs/ddr/) |
| VPU / RGA | Working | hantro-vpu, rockchip-rga |
| IEP | Not working | BSP-only (MPP) |
| Suspend | Working | rk356x-suspend, BL31 deep sleep |
| Input (buttons + rumble) | Working | 17 GPIO buttons, joypad, rumble (PWM5) |

---

## Key Discoveries

Findings that made mainline work on this device (details in the wiki):

- **VSEL:** Mainline `fan53555` expects `fcs,suspend-voltage-selector` (not `rockchip,suspend-voltage-selector`) — wrong value hangs after "FAN53555 Detected!".
- **DSI panel:** Init commands must run in command mode (`prepare()`), not during video stream.
- **PMIC:** `vcc9-supply = <&vccsys>` to avoid fw_devlink cycles; no sleep pinctrl on RK817.
- **DDR:** Out-of-tree DMC devfreq driver for mainline 6.18+ ([docs/ddr/](docs/ddr/)).
- **Suspend:** Out-of-tree `rk356x-suspend` configures BL31 deep sleep ([docs/ddr/06-suspend-driver-and-vdd-logic.md](docs/ddr/06-suspend-driver-and-vdd-logic.md)).
- **Boot chain:** U-Boot FIT must include OP-TEE (BL32); bootrom/SPL behaviour for SD boot — see [docs/boot-chain.md](docs/boot-chain.md), [docs/ddr/](docs/ddr/).

---

## Project structure

- **Wiki:** The `docs/` tree is the device wiki and is maintained.
- **Boot logs:** `boot_log_ROCKNIX.txt`, `boot_log_STOCK_INCLUDE_SLEEP_POWEROFF.txt` (in repo root).
- **Build system:** Scripts and layout in this repo are **outdated**; for current builds and images, use [Zetarancio/distribution](https://github.com/Zetarancio/distribution). Historical build/flash steps are in [docs/building.md](docs/building.md) and [docs/flashing.md](docs/flashing.md).

---

## Quick start

For a **current image and build**, use the [Zetarancio/distribution](https://github.com/Zetarancio/distribution) (ROCKNIX, branch `flip`) repo.

For **historical** build and flash steps (this repo’s Makefile/Docker), see [docs/building.md](docs/building.md) and [docs/flashing.md](docs/flashing.md).

---

## External references

**Datasheets & TRM (Rockchip):**

- [RK3566 Datasheet V1.2](https://wiki.friendlyelec.com/wiki/images/8/89/Rockchip_RK3566_Datasheet_V1.2-20220930.pdf) (FriendlyElec wiki)
- [RK3568 TRM Part 1](https://dl.radxa.com/rock3/docs/hw/datasheet/Rockchip%20RK3568%20TRM%20Part1%20V1.1-20210301.pdf) (Radxa)
- [RK3568 TRM Part 2](https://dl.radxa.com/rock3/docs/hw/datasheet/Rockchip%20RK3568%20TRM%20Part2%20V1.1-20210301.pdf) (Radxa)

**steward-fu’s Miyoo Flip pages:** [UART](https://steward-fu.github.io/website/handheld/miyoo_flip_uart.htm) · [Specs](https://steward-fu.github.io/website/handheld/miyoo_flip_spec.htm) · [Pin mapping](https://steward-fu.github.io/website/handheld/miyoo_flip_pin.htm) · [MTD](https://steward-fu.github.io/website/handheld/miyoo_flip_mtd.htm) · [Assets](https://github.com/steward-fu/website/releases/tag/miyoo-flip)

**Related projects:** [Zetarancio/distribution](https://github.com/Zetarancio/distribution) (current ROCKNIX Miyoo Flip) · [ROCKNIX](https://rocknix.org/) · [GammaOS Core](https://github.com/TheGammaSqueeze/GammaOSCore)

---

## License

Documentation and scripts: [GNU GPL v2](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html). DTS/patches follow kernel GPL v2. Third-party components have their own licenses.

---

## Thanks

Thanks to [steward-fu](https://github.com/steward-fu) for the Miyoo Flip resource site and assets; [beebono](https://github.com/beebono), [sydarn](https://github.com/sydarn), and the community behind [SpruceOS](https://spruceui.github.io/) for their work and support. This project wouldn’t be where it is without them.
