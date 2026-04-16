# Miyoo Flip — Device Wiki & Reference

This repository is the **maintained wiki and reference** for the **Miyoo Flip** handheld (Rockchip RK3566) on mainline Linux. The documentation is kept up to date as the canonical device reference.

**ROCKNIX images:** **[Zetarancio/distribution](https://github.com/Zetarancio/distribution)** — GitHub Actions publishes **generic** and **device-specific** builds on branch **`flip`** (use the **device-specific** artifact for Miyoo Flip). Day-to-day DTS and kernel integration for this wiki tracks branch **`next`** ahead of those freezes.

The distribution repo holds the build system and device sources; **this `main` branch** is documentation, reference material, and small helper assets. Legacy local build scripts live on branch **`buildroot`**.

**Wiki updated to:** [`a482d5c`](https://github.com/Zetarancio/distribution/commit/a482d5cfc4) on the `flip` branch (2026-04). Recent highlights: **RK817 off-state drain fix** [560a99c](https://github.com/Zetarancio/distribution/commit/560a99cbe1d6b2a3760639ca0e8e730f101e9abb) (patch **0007**, SYS_CAN_SD), removal of inactive **0029** PMIC pinctrl patch [f9a59b0](https://github.com/Zetarancio/distribution/commit/f9a59b020de4e0109569e8f05d2760702b701e46), Miyoo Flip DTS cleanup and **upstream `pmic_pins`** [a482d5c](https://github.com/Zetarancio/distribution/commit/a482d5cfc4).

---

## Stock ↔ ROCKNIX without opening the device

| Step | What to do |
|------|------------|
| **1. Stock → ROCKNIX** | Install the **Preloader Eraser** app on your SD (from [`preloader-stock-rocknix/App/`](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/tree/main/preloader-stock-rocknix/App)), run it on **stock**, reboot with a **ROCKNIX** SD. |
| **2. ROCKNIX → stock** | On **ROCKNIX**, run **`write-preloader-mtd.sh`** with **`preloader.img`** (bundled under [`preloader-stock-rocknix/preloader-restore/`](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/tree/main/preloader-stock-rocknix/preloader-restore)), reboot → **internal stock** again. |

**Article:** [Try ROCKNIX without opening the device](docs/boot-and-flash/stock-rocknix-without-disassembly.md)

**Safety:** This path **does not brick** the SoC. If anything misbehaves, you can still **open the device**, enter **MASKROM**, and **flash** with **`xrock`** like any other recovery — see the guide’s callout and [Flashing](docs/boot-and-flash/flashing.md).

---

## Hardware

| Component | Detail                                                |
| --------- | ----------------------------------------------------- |
| SoC       | Rockchip RK3566 (quad Cortex-A55 @ 1.8 GHz)           |
| GPU       | Mali-G52 2EE (Bifrost)                                |
| RAM       | LPDDR4                                                |
| Storage   | SPI NAND 128 MB + 2x MicroSD                          |
| Display   | **LMY35120-20p** (marking **2503x**). Confirmed: 640×480 MIPI DSI, 2-lane, RGB888 video mode (stock DTS). Presumed: FT8006M COG — [details](docs/drivers-and-dts/display.md#module-name-vs-what-is-proven) |
| WiFi/BT   | RTL8733BU (USB)                                       |
| Audio     | RK817 codec + speaker amplifier                        |
| PMIC      | RK817 (main) + VDD_CPU (**TCS4525 @ 0x1c** and/or **RK8600 @ 0x40** — see note below) |
| Battery   | Miyoo **755060**, **3.7 V** nominal, **3000 mAh**, **11.1 Wh** (typical pack marking) |
| UART      | ttyS2 @ 1,500,000 baud (3.3V)                         |

**VDD_CPU / I2C0:** 2025 stock DTS and the current flip DTS enable **both** CPU-regulator nodes (`status = "okay"`), matching stock behavior ([b7525be](https://github.com/Zetarancio/distribution/commit/b7525bed1d9d262d621d66f1108c859399db7777), [6882112](https://github.com/Zetarancio/distribution/commit/68821122aa0476ed453cdc1b073922b0805d0214)). **Two board revisions** (one populated at 0x1c *or* 0x40) are suggested by firmware but **not proven** on hardware. The kernel probes both; the **absent** chip returns **probe failure** and is ignored—the **present** rail works and the system **boots normally**.

---

## Documentation

**[Full index → docs/README.md](docs/README.md)**

| Topic | Front page | Subpages |
| ----- | ---------- | -------- |
| **Boot and flash** | [boot-and-flash.md](docs/boot-and-flash.md) — specs, images, boot chain | [Flashing](docs/boot-and-flash/flashing.md), [Boot from SD](docs/boot-and-flash/boot-from-sd.md), [**Stock ↔ ROCKNIX (no disassembly)**](docs/boot-and-flash/stock-rocknix-without-disassembly.md) |
| **RK3566 reference** | [rk3566-reference.md](docs/rk3566-reference.md) — SoC overview | [Datasheet](docs/rk3566-reference/datasheet-specs.md), [TRM 1](docs/rk3566-reference/trm-part1-registers-dpll.md), [TRM 2](docs/rk3566-reference/trm-part2-dmc-hwffc-dcf.md), [Unused pins](docs/rk3566-reference/unused-pins-power-saving.md) |
| **Stock firmware** | [stock-firmware-and-findings.md](docs/stock-firmware-and-findings.md) — dumps, overview | [BSP/DDR findings](docs/stock-firmware-and-findings/bsp-and-ddr-findings.md), [SPI/boot chain](docs/stock-firmware-and-findings/spi-and-boot-chain.md) |
| **Drivers and DTS** | [drivers-and-dts.md](docs/drivers-and-dts.md) — DTS evolution, drivers | [Board DTS](docs/drivers-and-dts/board-dts-pmic-ddr-updates.md), [Drivers](docs/drivers-and-dts/drivers.md), [DTS porting](docs/drivers-and-dts/dts-porting.md), [Display](docs/drivers-and-dts/display.md), [WiFi power-off](docs/drivers-and-dts/wifi-bt-power-off.md), [Suspend](docs/drivers-and-dts/suspend-and-vdd-logic.md) |
| **Power-off / RK817 drain** | [miyoo-flip-power-off-investigation.md](docs/miyoo-flip-power-off-investigation.md) | Long-form investigation; kernel **patch 0007** (SYS_CAN_SD) |
| **Troubleshooting** | [troubleshooting.md](docs/troubleshooting.md) | — |
| **Serial** | [serial.md](docs/serial.md) | — |

Reference boot logs in this repo: `boot_log_ROCKNIX.txt` (mainline; DMC after resume, power-down reaches `reboot: Power down`); `boot_log_STOCK_INCLUDE_SLEEP_POWEROFF_AND_DEBUG.txt` (stock with DDR/sleep debug); `boot_log_STOCK_INCLUDE_SLEEP_POWEROFF.txt` (stock, sleep/poweroff).

**Note:** `boot_log_ROCKNIX.txt` may not match the **latest** kernel/DTS iteration at all times; it is kept as **historical proof** of a working mainline capture (e.g. DMC after resume, power-down), not as a live regression log.

---

## Status

| Subsystem                | Status                | Notes |
| ------------------------ | --------------------- | ----- |
| Boot (U-Boot + kernel)   | Working               | Mainline 6.18+, SPI NAND or SD |
| Display (DSI panel)      | Working               | 640x480, panel driver |
| Backlight                | Working               | PWM4 |
| Audio (RK817)            | Working               | simple-audio-card, speaker amp |
| WiFi (RTL8733BU)         | Working               | Out-of-tree 8733bu, 6.18+. Optionally a separate driver can shut down the combo at GPIO level when both radios are off; see [WiFi/BT power-off](docs/drivers-and-dts/wifi-bt-power-off.md). |
| Bluetooth                | Working               | Unified firmware, btusb re-probe |
| GPU (Mali-G52)           | Working               | mali_kbase + libmali, 200–800 MHz |
| Storage                  | Working               | SPI NAND MTD, both SD slots |
| HDMI                     | Working               | Video and audio (when enabled in DTS) |
| HDMI audio               | Working               | With HDMI output |
| DMC (DDR devfreq)        | Working (out-of-tree) | Scaling + resume confirmed; see [BSP and DDR findings](docs/stock-firmware-and-findings/bsp-and-ddr-findings.md), [SPI and boot chain](docs/stock-firmware-and-findings/spi-and-boot-chain.md) |
| VPU / RGA                | Working               | hantro-vpu, rockchip-rga |
| IEP                      | Not working           | BSP-only (MPP) |
| Suspend                  | Working               | **Standard** suspend-to-RAM works on [Zetarancio/distribution](https://github.com/Zetarancio/distribution) branch **`next`**. **Deep suspend** (rk3568-suspend + **`vdd_logic` off-in-suspend**) is implemented but **disabled** pending an **EmulationStation** upstream fix; improves estimated standby (~40–50 h → ~100–120 h) but not shipped yet — [Suspend and vdd_logic](docs/drivers-and-dts/suspend-and-vdd-logic.md) |
| Input (buttons + rumble) | Working               | 17 GPIO buttons, joypad, rumble (PWM5) |

---

## Key Discoveries

Findings that made mainline work on this device (details in the wiki).

- **VSEL register hang:** The BSP DTS uses `rockchip,suspend-voltage-selector` but mainline `fan53555` reads `fcs,suspend-voltage-selector`. Wrong name causes VDD_CPU to drop and the board to hang immediately after "FAN53555 Detected!" on kernels 6.4+.

- **DSI panel init in command mode:** The stock driver sends init commands via a DT property. On mainline, commands must be sent during `prepare()` (command mode), not `enable()` (video mode), or they collide with the video stream on the shared FIFO.

- **PMIC dependency cycles:** `vcc9-supply = <&dcdc_boost>` and some sleep pinctrl arrangements create circular dependencies that `fw_devlink` cannot resolve. Fixed by using `<&vccsys>` and careful RK817 pinctrl. Deep sleep still uses **patched rk8xx** / suspend ordering from [Zetarancio/distribution](https://github.com/Zetarancio/distribution) where applicable.

- **DDR on mainline:** The BSP DMC uses Rockchip V2 SIP (shared memory + MCU/IRQ). An out-of-tree DMC devfreq driver implements this for mainline 6.18+ and is confirmed working; see [BSP and DDR findings](docs/stock-firmware-and-findings/bsp-and-ddr-findings.md) and [SPI and boot chain](docs/stock-firmware-and-findings/spi-and-boot-chain.md).

- **Suspend:** **Standard** suspend works on **`next`**. **Deep sleep** uses **rk3568-suspend** + **`vdd_logic` off-in-suspend**; that stack is **implemented but disabled** until **EmulationStation** catches up upstream (~40–50 h vs ~**100–120 h** estimated standby). See [Suspend and vdd_logic](docs/drivers-and-dts/suspend-and-vdd-logic.md).

- **WiFi/BT full poweroff:** The 8733bu driver only does software rfkill; it does not control the power-enable GPIO. Full hardware poweroff of the combo requires a **separate driver** that controls the enable GPIO and integrates with rfkill. See [WiFi/BT power-off](docs/drivers-and-dts/wifi-bt-power-off.md).

- **Boot chain:** Any U-Boot for this board must include OP-TEE (BL31) in the FIT image; the boot chain expects ATF + OP-TEE + U-Boot. Bootrom/SPL behaviour for SD boot is documented in [Boot and flash](docs/boot-and-flash.md) and [SPI and boot chain](docs/stock-firmware-and-findings/spi-and-boot-chain.md).

- **Full power-off / off-state drain:** The **~8 mA** battery drain while “off” was traced to RK817 **SYS_CAN_SD** (charger block stays active). **Kernel patch 0007** clears that bit in `rk817_battery_init()` (BSP parity). See [Power-off investigation](docs/miyoo-flip-power-off-investigation.md), [Troubleshooting](docs/troubleshooting.md), and [560a99c](https://github.com/Zetarancio/distribution/commit/560a99cbe1d6b2a3760639ca0e8e730f101e9abb). Earlier guidance to omit `system-power-controller` to “fix drain” is **obsolete** once 0007 is applied; DTS follows the current `flip` tree (e.g. upstream-style `pmic_pins`, [a482d5c](https://github.com/Zetarancio/distribution/commit/a482d5cfc4)).

- **2025 stock alignment:** PMIC suspend/resume, battery OCV (descending table), shared SD `vqmmc`, DMC devfreq tuning, and DSI/panel init have been refined against newer stock; see [Stock firmware and findings](docs/stock-firmware-and-findings.md) and [Board DTS / PMIC / DDR](docs/drivers-and-dts/board-dts-pmic-ddr-updates.md). Commit history: [distribution `flip`](https://github.com/Zetarancio/distribution/commits/flip/).

- **VDD_CPU / I2C0:** Same story as the **Hardware** table note; full write-up: [Board DTS — I2C0 CPU regulator](docs/drivers-and-dts/board-dts-pmic-ddr-updates.md#i2c0-cpu-regulator-tcs4525-and-rk8600) ([b7525be](https://github.com/Zetarancio/distribution/commit/b7525bed1d9d262d621d66f1108c859399db7777), [6882112](https://github.com/Zetarancio/distribution/commit/68821122aa0476ed453cdc1b073922b0805d0214)).

---

## Project structure

```
docs/                          Documentation wiki (maintained)
miyoo355_fw_20250527/          Official May 2025 card-flash unpack (DTS, rootfs; raw `miyoo355_fw.img` not kept in git — see docs/stock-firmware-and-findings.md)
spi_20241119160817/            Unpacked 2024 SPI dump (DTS, rootfs, joystick study used to improve the rocknix driver) — see docs/stock-firmware-and-findings.md
bl31_v1.44_stock_disasm/       BL31 v1.44 disassembly + ELF (stock rkbin snapshot) — see docs/stock-firmware-and-findings.md
bl31_v1.45_rocknix_disasm/     BL31 v1.45 disassembly + ELF (ROCKNIX rk3566)
bl31_v1.44_vs_v1.45_diff.patch Diff of disassembly exports (v1.44 vs v1.45)
Stock-dump.txt                 Stock BSP debugfs / PMIC capture (power investigation)
Rocknix-dump-Before-ChargerFIX.txt  ROCKNIX PMIC dump before kernel patch 0007 (SYS_CAN_SD)
preloader-stock-rocknix/       Stock app + scripts: erase/restore SPI preloader to SD-boot ROCKNIX without opening — see docs/boot-and-flash/stock-rocknix-without-disassembly.md
boot_log_ROCKNIX.txt           Mainline boot log (historical proof; may not match latest build—see note below)
boot_log_STOCK_INCLUDE_SLEEP_POWEROFF_AND_DEBUG.txt   Stock with DDR/sleep debug
boot_log_STOCK_INCLUDE_SLEEP_POWEROFF.txt             Stock, sleep/poweroff capture
```

**Wiki:** The `docs/` tree is the device wiki and is maintained.

**Boot logs:** In repo root — `boot_log_ROCKNIX.txt` (mainline capture; **not guaranteed current** with the latest DTS/kernel—kept as proof); `boot_log_STOCK_INCLUDE_SLEEP_POWEROFF_AND_DEBUG.txt` (stock + debug); `boot_log_STOCK_INCLUDE_SLEEP_POWEROFF.txt` (stock).

**Build system:** For current builds and images use [Zetarancio/distribution](https://github.com/Zetarancio/distribution). This `main` branch is documentation-focused; legacy local build scripts live on branch `buildroot`. Flashing steps are in [docs/boot-and-flash/flashing.md](docs/boot-and-flash/flashing.md).

---

## Quick start

For a **current image and build**, use the [Zetarancio/distribution](https://github.com/Zetarancio/distribution) (ROCKNIX, branch `flip`) repo.

For legacy local build scripts, see branch **`buildroot`**.

For flashing and SD boot on this wiki, see [Boot and flash](docs/boot-and-flash.md).

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
