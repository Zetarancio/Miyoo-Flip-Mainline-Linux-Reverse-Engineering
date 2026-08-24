# Miyoo Flip — Device Wiki & Reference

This repository is the **maintained wiki and reference** for the **Miyoo Flip** handheld (Rockchip RK3566) on mainline Linux. The documentation is kept up to date as the canonical device reference.

**ROCKNIX images:** **[Zetarancio/distribution](https://github.com/Zetarancio/distribution)** — GitHub Actions publishes **generic** and **device-specific** builds on branch **`flip`** (use the **device-specific** artifact for Miyoo Flip). Day-to-day DTS and kernel integration for this wiki tracks branch **`next`** ahead of those freezes.

The distribution repo holds the build system and device sources; **this `main` branch** is documentation, reference material, and small helper assets. Legacy local build scripts live on branch **`buildroot`**.

**Wiki `flip` stamp:** [`1becfbd`](https://github.com/Zetarancio/distribution/commit/1becfbd094) — *Merge upstream/next into flip* (2026-07-08). **RK3566 kernel:** **Linux 7.0.2** (`7.0` patch dir; SM* platforms on 7.1.2 only). **Recent Miyoo / RK3566 commits on `flip`:** [RK3566: raise PipeWire idle timeout to 60s](https://github.com/Zetarancio/distribution/commit/32fa5f3308) · [Miyoo Flip: low-battery feedback via existing led_flash](https://github.com/Zetarancio/distribution/commit/f559f5e5aa) · [RK3566 linux: disable CONFIG_RK3568_SUSPEND_MODE while 1013 patches are .testing-disabled](https://github.com/Zetarancio/distribution/commit/ca7bb4a903) · [RK3566 patches: renumber dfi pm 1011 → 1010](https://github.com/Zetarancio/distribution/commit/3fe4002ecf) · earlier: [DTS cleanup](https://github.com/Zetarancio/distribution/commit/1f129e89df), [audio prime](https://github.com/Zetarancio/distribution/commit/79453c8d9b). [board DTS](docs/drivers-and-dts/board-dts-pmic-ddr-updates.md) · [commits/flip](https://github.com/Zetarancio/distribution/commits/flip/).

---

## Stock + SD distro at once, without opening the device

**Multiboot** is the recommended setup. It **repairs** the SPI preloader instead of erasing it, so the device simply decides at power-on:

| Card in the right-hand slot | Boots |
|------|-------|
| none | **stock**, from internal SPI NAND |
| a card the stock SPL can load a U-Boot from | **that OS**, from SD |

Nothing is erased and official Miyoo firmware updates survive it. Method by **[apommel](https://github.com/apommel/baseos-my355)** — see [Thanks](#thanks).

### If ROCKNIX already boots from a card

The patch can only be **written** from ROCKNIX, so this is the whole procedure.

1. Copy the folder **[`preloader-stock-rocknix/App/apommel-multiboot/`](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/tree/main/preloader-stock-rocknix/App/apommel-multiboot)** onto a card, keeping the folder intact. In ROCKNIX's file manager the cards appear under **`games-external`**.
2. Run **`check-preloader.sh`** (**Execute** in the file manager). It writes nothing and tells you whether this unit is recognised and whether its DRAM blob matches the bundled image.
3. If that looks clean, run **`install-multiboot.sh`** the same way.
4. **Reboot.**

Prefer the device UI? Copy the three scripts in **`rocknix-ports/`** to `/storage/roms/ports/` and they appear in the **Ports** menu as `Multiboot 1 Check`, `2 Install`, `3 Restore`.

### If only stock boots

The preloader cannot be written from stock, so it takes two steps and two reboots. In between, the device is exactly where the eraser has always left it: SD-boot only, MASKROM reachable without disassembly. Stopping after step 1 breaks nothing new.

| # | Boot into | Copy | Run |
|---|-----------|------|-----|
| 1 | **stock** | **[`App/PreloaderEraser/`](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/tree/main/preloader-stock-rocknix/App/PreloaderEraser)** → `SDCARD/App/PreloaderEraser/` | the **“Miyoo Flip MASKROM Access (Preloader Eraser)”** launcher entry, then reboot with a ROCKNIX card inserted |
| 2 | **ROCKNIX** (from that card) | **`App/apommel-multiboot/`** → any card, visible as `games-external` | **`check-preloader.sh`**, then **`install-multiboot.sh`**, then reboot |

### To undo it

Run **`restore-preloader.sh`** on ROCKNIX and reboot: a stock preloader goes back and the device boots internal stock again, ignoring cards.

### Where this has been tested

| System | Multiboot |
|--------|-----------|
| **stock** (internal NAND) | works — tested |
| **ROCKNIX** | works — tested |
| **[apommel's MinUI base](https://github.com/apommel/baseos-my355)** | works — the method's own target |
| **Knulli** | **does not work** — ships an rk3568-evb U-Boot for its own SPL |
| **GammaOS** | **not expected to work** — same model, expects GammaLoader in NAND |

Because U-Boot now comes from the **card**, each distro has to ship one built for this board. Knulli and GammaOS would only need to change what their images write to the card — nothing in NAND. Until they do, those two still need the erase method, at the cost of internal stock boot: [why, in detail](docs/boot-and-flash/sd-multiboot-apommel.md#distro-compatibility).

**Articles:** [SD multiboot via a repaired preloader](docs/boot-and-flash/sd-multiboot-apommel.md) · [MASKROM and SD boot by erasing the preloader](docs/boot-and-flash/stock-rocknix-without-disassembly.md)

**Safety:** This path **does not brick** the SoC. The bootrom and USB MASKROM are not stored in SPI, so worst case you **open the device**, enter **MASKROM**, and **flash** with **`xrock`** like any other recovery — [Flashing](docs/boot-and-flash/flashing.md).

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
| PMIC      | RK817 (main) + VDD_CPU (**RK8600 @ 0x40**; see I2C0 note below) |
| Battery   | Miyoo **755060**, **3.7 V** nominal, **3000 mAh**, **11.1 Wh** (typical pack marking) |
| UART      | ttyS2 @ 1,500,000 baud (3.3V)                         |

**VDD_CPU / I2C0:** Current **`flip`** DTS has **RK8600 @ 0x40** only. **TCS4525 @ 0x1c** was removed ([1f129e89df](https://github.com/Zetarancio/distribution/commit/1f129e89df) — *Miyoo Flip DTS: cleanup and fixes*) after **Miyoo officially confirmed** to this project that there is **no second CPU-regulator hardware variant** (only RK8600 is populated). **2025 stock DTS** still lists both addresses for BSP comparison only—not evidence of two production SKUs.

---

## Documentation

**[Full index → docs/README.md](docs/README.md)**

| Topic | Front page | Subpages |
| ----- | ---------- | -------- |
| **Boot and flash** | [boot-and-flash.md](docs/boot-and-flash.md) — specs, images, boot chain | [**SD multiboot (recommended)**](docs/boot-and-flash/sd-multiboot-apommel.md), [Flashing](docs/boot-and-flash/flashing.md), [Erase the preloader (MASKROM)](docs/boot-and-flash/stock-rocknix-without-disassembly.md) |
| **RK3566 reference** | [rk3566-reference.md](docs/rk3566-reference.md) — SoC overview | [Datasheet](docs/rk3566-reference/datasheet-specs.md), [TRM 1](docs/rk3566-reference/trm-part1-registers-dpll.md), [TRM 2](docs/rk3566-reference/trm-part2-dmc-hwffc-dcf.md), [Unused pins](docs/rk3566-reference/unused-pins-power-saving.md) |
| **Stock firmware** | [stock-firmware-and-findings.md](docs/stock-firmware-and-findings.md) — dumps, overview | [BSP/DDR findings](docs/stock-firmware-and-findings/bsp-and-ddr-findings.md), [SPI/boot chain](docs/stock-firmware-and-findings/spi-and-boot-chain.md) |
| **Drivers and DTS** | [drivers-and-dts.md](docs/drivers-and-dts.md) — DTS evolution, drivers | [Board DTS](docs/drivers-and-dts/board-dts-pmic-ddr-updates.md), [Drivers](docs/drivers-and-dts/drivers.md), [DTS porting](docs/drivers-and-dts/dts-porting.md), [Display](docs/drivers-and-dts/display.md), [WiFi power-off](docs/drivers-and-dts/wifi-bt-power-off.md), [Suspend](docs/drivers-and-dts/suspend-and-vdd-logic.md) |
| **Power-off / RK817 drain** | [miyoo-flip-power-off-investigation.md](docs/miyoo-flip-power-off-investigation.md) | Long-form investigation; kernel **patch 0007** (SYS_CAN_SD) |
| **Troubleshooting** | [troubleshooting.md](docs/troubleshooting.md) | — |
| **Serial** | [serial.md](docs/serial.md) | — |

Reference boot logs in `logs/`: `logs/boot_log_ROCKNIX.txt` (mainline; DMC after resume, power-down reaches `reboot: Power down`); `logs/boot_log_STOCK_INCLUDE_SLEEP_POWEROFF_AND_DEBUG.txt` (stock with DDR/sleep debug); `logs/boot_log_STOCK_INCLUDE_SLEEP_POWEROFF.txt` (stock, sleep/poweroff).

**Note:** `logs/boot_log_ROCKNIX.txt` may not match the **latest** kernel/DTS iteration at all times; it is kept as **historical proof** of a working mainline capture (e.g. DMC after resume, power-down), not as a live regression log.

---

## Status

| Subsystem                | Status                | Notes |
| ------------------------ | --------------------- | ----- |
| Boot (U-Boot + kernel)   | Working               | Mainline **7.0+** on current `flip` (was 6.18+); SPI NAND or SD |
| Display (DSI panel)      | Working               | 640x480, panel driver |
| Backlight                | Working               | PWM4 |
| Audio (RK817)            | Working               | PipeWire + rk817 UCM; `099-audio_prime` + **idle.timeout=60s** ([79453c8](https://github.com/Zetarancio/distribution/commit/79453c8d9b), [32fa5f3](https://github.com/Zetarancio/distribution/commit/32fa5f3308)) |
| WiFi (RTL8733BU)         | Working               | Out-of-tree 8733bu on kernel 7.0+. Optional GPIO power-off driver; see [WiFi/BT power-off](docs/drivers-and-dts/wifi-bt-power-off.md). |
| Bluetooth                | Working               | Unified firmware, btusb re-probe |
| GPU (Mali-G52)           | Working               | mali_kbase + libmali, 200–800 MHz |
| Storage                  | Working               | SPI NAND MTD, both SD slots |
| HDMI                     | Working               | Video and audio (when enabled in DTS) |
| HDMI audio               | Working               | With HDMI output |
| DMC (DDR devfreq)        | Working (out-of-tree) | Scaling + resume confirmed; see [BSP and DDR findings](docs/stock-firmware-and-findings/bsp-and-ddr-findings.md), [SPI and boot chain](docs/stock-firmware-and-findings/spi-and-boot-chain.md) |
| VPU / RGA                | Working               | hantro-vpu, rockchip-rga |
| IEP                      | Not working           | BSP-only (MPP) |
| Suspend                  | Working               | **Standard** suspend on **`flip`**. **Deep suspend** (1013 + `vdd_logic` off) **deferred** — patches `.testing-disabled`, `CONFIG_RK3568_SUSPEND_MODE` off ([ca7bb4a9](https://github.com/Zetarancio/distribution/commit/ca7bb4a903)); ES upstream blocker — [Suspend](docs/drivers-and-dts/suspend-and-vdd-logic.md) |
| Input (buttons + rumble) | Working               | 17 GPIO buttons, joypad, rumble (PWM5) |

---

## Key Discoveries

Findings that made mainline work on this device (details in the wiki).

- **VSEL register hang:** The BSP DTS uses `rockchip,suspend-voltage-selector` but mainline `fan53555` reads `fcs,suspend-voltage-selector`. Wrong name causes VDD_CPU to drop and the board to hang immediately after "FAN53555 Detected!" on kernels 6.4+.

- **DSI panel init in command mode:** The stock driver sends init commands via a DT property. On mainline, commands must be sent during `prepare()` (command mode), not `enable()` (video mode), or they collide with the video stream on the shared FIFO.

- **PMIC dependency cycles:** `vcc9-supply = <&dcdc_boost>` and some sleep pinctrl arrangements create circular dependencies that `fw_devlink` cannot resolve. Fixed by using `<&vccsys>` and careful RK817 pinctrl. Deep sleep still uses **patched rk8xx** / suspend ordering from [Zetarancio/distribution](https://github.com/Zetarancio/distribution) where applicable.

- **DDR on mainline:** The BSP DMC uses Rockchip V2 SIP (shared memory + MCU/IRQ). An out-of-tree DMC devfreq driver implements this for mainline **7.0+** (current `flip`; older captures used 6.18+); see [BSP and DDR findings](docs/stock-firmware-and-findings/bsp-and-ddr-findings.md) and [SPI and boot chain](docs/stock-firmware-and-findings/spi-and-boot-chain.md).

- **Suspend:** **Standard** suspend works on **`flip`**. **Deep sleep** (**1013** + `vdd_logic` off) stays **deferred** (`.testing-disabled`, `CONFIG_RK3568_SUSPEND_MODE` off) until **EmulationStation** upstream fix. See [Suspend and vdd_logic](docs/drivers-and-dts/suspend-and-vdd-logic.md).

- **WiFi/BT full poweroff:** The 8733bu driver only does software rfkill; it does not control the power-enable GPIO. Full hardware poweroff of the combo requires a **separate driver** that controls the enable GPIO and integrates with rfkill. See [WiFi/BT power-off](docs/drivers-and-dts/wifi-bt-power-off.md).

- **Boot chain:** Any U-Boot for this board must include OP-TEE (BL31) in the FIT image; the boot chain expects ATF + OP-TEE + U-Boot. Bootrom/SPL behaviour for SD boot is documented in [Boot and flash](docs/boot-and-flash.md) and [SPI and boot chain](docs/stock-firmware-and-findings/spi-and-boot-chain.md).

- **Full power-off / off-state drain:** The **~8 mA** battery drain while “off” was traced to RK817 **SYS_CAN_SD** (charger block stays active). **Kernel patch 0007** clears that bit in `rk817_battery_init()` (BSP parity). See [Power-off investigation](docs/miyoo-flip-power-off-investigation.md), [Troubleshooting](docs/troubleshooting.md), and [560a99c](https://github.com/Zetarancio/distribution/commit/560a99cbe1d6b2a3760639ca0e8e730f101e9abb). Earlier guidance to omit `system-power-controller` to “fix drain” is **obsolete** once 0007 is applied; DTS follows the current `flip` tree (e.g. upstream-style `pmic_pins`, [a482d5c](https://github.com/Zetarancio/distribution/commit/a482d5cfc4)).

- **2025 stock alignment:** PMIC suspend/resume, battery OCV (descending table), shared SD `vqmmc`, DMC devfreq tuning, and DSI/panel init have been refined against newer stock; see [Stock firmware and findings](docs/stock-firmware-and-findings.md) and [Board DTS / PMIC / DDR](docs/drivers-and-dts/board-dts-pmic-ddr-updates.md). Commit history: [distribution `flip`](https://github.com/Zetarancio/distribution/commits/flip/).

- **VDD_CPU / I2C0:** **`flip`** DTS uses **RK8600 only**; **TCS4525** dropped after **Miyoo’s official confirmation** there is no alternate CPU-regulator SKU ([1f129e89df](https://github.com/Zetarancio/distribution/commit/1f129e89df)). [Board DTS — I2C0](docs/drivers-and-dts/board-dts-pmic-ddr-updates.md#i2c0-cpu-regulator).

---

## Project structure

```
docs/                          Documentation wiki (maintained)
miyoo355_fw_20250527/          Official May 2025 card-flash unpack (DTS, rootfs; raw `miyoo355_fw.img` not kept in git — see docs/stock-firmware-and-findings.md)
spi_20241119160817/            Unpacked 2024 SPI dump (DTS, rootfs, joystick study used to improve the rocknix driver) — see docs/stock-firmware-and-findings.md
bl31_v1.44_stock_disasm/       BL31 v1.44 disassembly + ELF (stock rkbin snapshot) — see docs/stock-firmware-and-findings.md
bl31_v1.45_rocknix_disasm/     BL31 v1.45 disassembly + ELF (ROCKNIX rk3566)
bl31_v1.44_vs_v1.45_diff.patch Diff of disassembly exports (v1.44 vs v1.45)
logs/                          Boot logs + PMIC/debugfs dumps (reference)
test-scripts/                  `miyoo-flip-power-dump.sh` — optional on-device capture
preloader-stock-rocknix/       Two SD-card apps: apommel-multiboot (repair the preloader → multiboot, and restore it) and PreloaderEraser (erase it → MASKROM) — see docs/boot-and-flash/sd-multiboot-apommel.md
```

**Wiki:** The `docs/` tree is the device wiki and is maintained.

**Boot logs:** Under `logs/` — same filenames as before (mainline/stock captures; not guaranteed current).

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

Thanks to **[apommel](https://github.com/apommel)** for [baseos-my355](https://github.com/apommel/baseos-my355) — the discovery that Miyoo's `fdtgrep` run left `/pinctrl` empty in the SPL device tree, the nine properties that repair it, and a write-up clear enough to reproduce and verify independently. SD multiboot on this device exists because of that work, and it keeps stock intact precisely because it repairs the vendor's own preloader instead of replacing it.

Thanks to [steward-fu](https://github.com/steward-fu) for the Miyoo Flip resource site and assets; [beebono](https://github.com/beebono), [sydarn](https://github.com/sydarn), and the community behind [SpruceOS](https://spruceui.github.io/) for their work and support. This project wouldn’t be where it is without them.
