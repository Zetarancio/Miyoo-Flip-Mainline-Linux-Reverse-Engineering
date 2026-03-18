# Miyoo Flip — Device Wiki & Reference

This repository is the **maintained wiki and reference** for the **Miyoo Flip** handheld (Rockchip RK3566) on mainline Linux. The documentation is kept up to date as the canonical device reference.

**For a working image and current code** (DTS, drivers, ROCKNIX build system), use **[Zetarancio/distribution](https://github.com/Zetarancio/distribution)** (branch `flip`). GitHub Actions produces two images (specific and generic); **use the specific one** for testing. This `main` branch is wiki-first. Legacy build scripts are kept in branch **`buildroot`**.

**Wiki updated to:** [`18ad3c198c`](https://github.com/Zetarancio/distribution/commit/18ad3c198c) on the `flip` branch (2026-03-18).

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

**Obtain and flash:** one page for obtain and flash. **Device wiki:** serial, flashing, boot from SD, hardware, drivers, reference.

| Guide | Contents |
| ----- | -------- |
| [Obtain and flash](docs/obtain-and-flash.md) | Obtain/test images and flash with xrock; legacy scripts are on branch `buildroot` |
| [Serial](docs/serial.md) | How to obtain serial: wiring, baud, getty, SD slots |
| [Flashing](docs/flashing.md) | MTD layout, xrock, MASKROM, backup, flash, restore |
| [Boot from SD](docs/boot-from-sd.md) | Brief xrock procedure to boot from SD; details in Flashing |
| [Hardware](docs/hardware.md) | Device specs |
| [Display](docs/display.md) | DSI panel bring-up, backlight, init sequence |
| [Drivers](docs/drivers.md) | RTL8733BU WiFi/BT and Mali-G52 GPU |
| [DTS porting](docs/dts-porting.md) | BSP-to-mainline device tree translation |
| [Troubleshooting](docs/troubleshooting.md) | Boot hangs, kernel notes, debug bootargs |
| [Boot chain](docs/boot-chain.md) | FIT layout, OP-TEE requirement |
| [Suspend and vdd_logic](docs/suspend-and-vdd-logic.md) | Deep sleep, vdd_logic off-in-suspend |
| [WiFi/BT power-off](docs/wifi-bt-power-off.md) | Full poweroff of RTL8733BU via GPIO |
| [Unused pins](docs/unused-pins-power-saving.md) | Pins to tie for power saving |
| [BSP and DDR findings](docs/bsp-and-ddr-findings.md) | BSP sources, DMC location, mainline status |
| [SPI and boot chain](docs/spi-and-boot-chain.md) | SPI layout, FIT, BL31, DDR scaling |
| [TRM part 1](docs/trm-part1-registers-dpll.md), [TRM part 2](docs/trm-part2-dmc-hwffc-dcf.md), [RK3566 datasheet](docs/rk3566-datasheet-specs.md) | Registers, DMC, voltage/DDR specs |
| [Firmware dumps](docs/firmware-dumps.md), [Board DTS / PMIC / DDR](docs/board-dts-pmic-ddr-updates.md) | Stock unpacks; RK817, suspend, DMC, battery, SD vs [flip commits](https://github.com/Zetarancio/distribution/commits/flip/) |

Reference boot logs in this repo: `boot_log_ROCKNIX.txt` (mainline; DMC after resume, power-down reaches `reboot: Power down`); `boot_log_STOCK_INCLUDE_SLEEP_POWEROFF_AND_DEBUG.txt` (stock with DDR/sleep debug); `boot_log_STOCK_INCLUDE_SLEEP_POWEROFF.txt` (stock, sleep/poweroff).

---

## Status

| Subsystem                | Status                | Notes |
| ------------------------ | --------------------- | ----- |
| Boot (U-Boot + kernel)   | Working               | Mainline 6.18+, SPI NAND or SD |
| Display (DSI panel)      | Working               | 640x480, panel driver |
| Backlight                | Working               | PWM4 |
| Audio (RK817)            | Working               | simple-audio-card, speaker amp |
| WiFi (RTL8733BU)         | Working               | Out-of-tree 8733bu, 6.18+. Optionally a separate driver can shut down the combo at GPIO level when both radios are off; see [WiFi/BT power-off](docs/wifi-bt-power-off.md). |
| Bluetooth                | Working               | Unified firmware, btusb re-probe |
| GPU (Mali-G52)           | Working               | mali_kbase + libmali, 200–800 MHz |
| Storage                  | Working               | SPI NAND MTD, both SD slots |
| HDMI                     | Working               | Video and audio (when enabled in DTS) |
| HDMI audio               | Working               | With HDMI output |
| DMC (DDR devfreq)        | Working (out-of-tree) | Scaling + resume confirmed; see [BSP and DDR findings](docs/bsp-and-ddr-findings.md), [SPI and boot chain](docs/spi-and-boot-chain.md) |
| VPU / RGA                | Working               | hantro-vpu, rockchip-rga |
| IEP                      | Not working           | BSP-only (MPP) |
| Suspend                  | Working (out-of-tree) | Requires **rk3568-suspend** and **patched rk817 core** available at [Zetarancio/distribution](https://github.com/Zetarancio/distribution) for BL31 deep sleep; see [Suspend and vdd_logic](docs/suspend-and-vdd-logic.md) |
| Input (buttons + rumble) | Working               | 17 GPIO buttons, joypad, rumble (PWM5) |

---

## Key Discoveries

Findings that made mainline work on this device (details in the wiki).

- **VSEL register hang:** The BSP DTS uses `rockchip,suspend-voltage-selector` but mainline `fan53555` reads `fcs,suspend-voltage-selector`. Wrong name causes VDD_CPU to drop and the board to hang immediately after "FAN53555 Detected!" on kernels 6.4+.

- **DSI panel init in command mode:** The stock driver sends init commands via a DT property. On mainline, commands must be sent during `prepare()` (command mode), not `enable()` (video mode), or they collide with the video stream on the shared FIFO.

- **PMIC dependency cycles:** `vcc9-supply = <&dcdc_boost>` and sleep pinctrl states create circular dependencies that `fw_devlink` cannot resolve. Fixed by using `<&vccsys>` and removing sleep pinctrl on RK817. You can then reuse sleep pinctrl + **patched rk817 core** available at [Zetarancio/distribution](https://github.com/Zetarancio/distribution).

- **DDR on mainline:** The BSP DMC uses Rockchip V2 SIP (shared memory + MCU/IRQ). An out-of-tree DMC devfreq driver implements this for mainline 6.18+ and is confirmed working; see [BSP and DDR findings](docs/bsp-and-ddr-findings.md) and [SPI and boot chain](docs/spi-and-boot-chain.md).

- **Suspend:** Out-of-tree **rk3568-suspend** (not rk356x) configures BL31 **deep sleep**; required for `vdd_logic` off-in-suspend. See [Suspend and vdd_logic](docs/suspend-and-vdd-logic.md).

- **WiFi/BT full poweroff:** The 8733bu driver only does software rfkill; it does not control the power-enable GPIO. Full hardware poweroff of the combo requires a **separate driver** that controls the enable GPIO and integrates with rfkill. See [WiFi/BT power-off](docs/wifi-bt-power-off.md).

- **Boot chain:** Any U-Boot for this board must include OP-TEE (BL31) in the FIT image; the boot chain expects ATF + OP-TEE + U-Boot. Bootrom/SPL behaviour for SD boot is documented in [Boot chain](docs/boot-chain.md) and [SPI and boot chain](docs/spi-and-boot-chain.md).

- **Full power-off:** Do **not** set `system-power-controller` for now on the RK817 PMIC. It races with PSCI SYSTEM_OFF and leaves the PMIC partially on (battery drain). Without it, rk8xx_shutdown() sets SLPPIN_DN_FUN and BL31 powers down cleanly. See [troubleshooting](docs/troubleshooting.md) and [Zetarancio/distribution@0a2f831](https://github.com/Zetarancio/distribution/commit/0a2f831f60a4fb0d1a94dc46242c9349624f955c). Old stock software was not setting `system-power-controller`, newest reintroduced it, may work in conjunction with **patched rk817 core**.

- **2025 stock alignment:** PMIC suspend/resume, battery OCV (descending table), shared SD `vqmmc`, DMC devfreq tuning, and DSI/panel init have been refined against newer stock; see [firmware dumps](docs/firmware-dumps.md) and [board DTS / PMIC / DDR updates](docs/board-dts-pmic-ddr-updates.md). Commit history: [distribution `flip`](https://github.com/Zetarancio/distribution/commits/flip/).

---

## Project structure

```
docs/                          Documentation wiki (maintained)
miyoo355_fw_20250509213001/    Unpacked 2025 stock card image (DTS, rootfs) — see docs/firmware-dumps.md
spi_20241119160817/            Unpacked 2024 SPI dump (DTS, rootfs, joystick study used to improve the rocknix driver) — see docs/firmware-dumps.md
boot_log_ROCKNIX.txt           Mainline boot log (DMC after resume confirmed)
boot_log_STOCK_INCLUDE_SLEEP_POWEROFF_AND_DEBUG.txt   Stock with DDR/sleep debug
boot_log_STOCK_INCLUDE_SLEEP_POWEROFF.txt             Stock, sleep/poweroff capture
```

**Wiki:** The `docs/` tree is the device wiki and is maintained.

**Boot logs:** In repo root — `boot_log_ROCKNIX.txt` (mainline, DMC after resume); `boot_log_STOCK_INCLUDE_SLEEP_POWEROFF_AND_DEBUG.txt` (stock + debug); `boot_log_STOCK_INCLUDE_SLEEP_POWEROFF.txt` (stock).

**Build system:** For current builds and images use [Zetarancio/distribution](https://github.com/Zetarancio/distribution). This `main` branch is documentation-focused; legacy local build scripts live on branch `buildroot`. Flashing steps are in [docs/flashing.md](docs/flashing.md).

---

## Quick start

For a **current image and build**, use the [Zetarancio/distribution](https://github.com/Zetarancio/distribution) (ROCKNIX, branch `flip`) repo.

For legacy local build scripts, see branch **`buildroot`**.

For flashing and SD boot on this wiki, see [Obtain and flash](docs/obtain-and-flash.md) and [docs/flashing.md](docs/flashing.md).

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
- **Release (many useful files):** [steward-fu/website — miyoo-flip](https://github.com/steward-fu/website/releases/tag/miyoo-flip) — toolchain, U-Boot, xrock, SPI dumps, firmware, etc.

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
