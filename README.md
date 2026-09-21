# Miyoo Flip — Device Wiki & Reference

This repository is the hardware, firmware, and reverse-engineering wiki for the **Miyoo Flip** (`my355`, Rockchip **RK3566**). It is not the manual for one Linux distribution. A different operating system should still be able to use the hardware facts.

How statements are classified: [Documentation model](docs/DOCUMENTATION_MODEL.md).

## Project status

| Role | Where |
|------|--------|
| **Active implementation** | [Zlyme](https://github.com/Zetarancio/zlyme) — [status page](docs/implementations/zlyme.md) |
| **Historical implementation** | Miyoo Flip ROCKNIX fork — [Zetarancio/distribution](https://github.com/Zetarancio/distribution), **archived** — [status page](docs/implementations/rocknix.md) |
| **External upstream reference** | [ROCKNIX/distribution](https://github.com/ROCKNIX/distribution) |

Archiving the fork does not retire its measurements. The last wiki stamp of that `flip` branch is [`d249b09bd9`](https://github.com/Zetarancio/distribution/commit/d249b09bd9) (2026-09-02), RK3566 kernel **Linux 7.0.2**. Provenance for the upper-port OHCI clock, RTL8733BU patches, and related fixes stays on [the historical page](docs/implementations/rocknix.md).

**This `main` branch** is the wiki, reference dumps, and small helper tools. Legacy local build scripts live on branch **`buildroot`**.

---

## Stock + SD distro at once, without opening the device

**Multiboot** (recommended) repairs the SPI preloader instead of erasing it. At power-on: **no card** → stock from internal NAND; **bootable card in the right-hand slot** → that OS. Tested bootable: **stock**, ROCKNIX, SpruceOS, apommel's MinUI base. Official firmware updates survive the patch. Method by **[apommel](https://github.com/apommel/baseos-my355)**.

Install, restore, MASKROM, and which distros work: [SD multiboot](docs/boot-and-flash/sd-multiboot-apommel.md). Recovery: [Flashing](docs/boot-and-flash/flashing.md).

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
| USB       | Two USB-C: **upper** (top) = host; **lower** (bottom) = charge + gadget. [Board DTS — USB](docs/drivers-and-dts/board-dts-pmic-ddr-updates.md#usb) |

**VDD_CPU / I2C0:** Retail units populate **RK8600 @ 0x40** only. **TCS4525 @ 0x1c** was removed from the board DTS ([1f129e89df](https://github.com/Zetarancio/distribution/commit/1f129e89df) on the archived ROCKNIX fork) after **Miyoo officially confirmed** there is **no second CPU-regulator hardware variant**. **2025 stock DTS** still lists both addresses for BSP comparison — not evidence of two production SKUs.

---

## Documentation

**[Full index → docs/README.md](docs/README.md)**

| Topic | Front page | Subpages |
| ----- | ---------- | -------- |
| **Implementations** | [implementations/](docs/implementations/README.md) — Zlyme, archived ROCKNIX, stock | [Zlyme](docs/implementations/zlyme.md), [ROCKNIX fork](docs/implementations/rocknix.md), [Stock](docs/implementations/stock.md) |
| **Input** | [hardware/input.md](docs/hardware/input.md) — UART stick, GPIO, hall, rumble | — |
| **Boot and flash** | [boot-and-flash.md](docs/boot-and-flash.md) — specs, boot chain | [**SD multiboot**](docs/boot-and-flash/sd-multiboot-apommel.md), [Flashing](docs/boot-and-flash/flashing.md), [Erase the preloader (MASKROM)](docs/boot-and-flash/stock-rocknix-without-disassembly.md) |
| **RK3566 reference** | [rk3566-reference.md](docs/rk3566-reference.md) — SoC overview | [Datasheet](docs/rk3566-reference/datasheet-specs.md), [TRM 1](docs/rk3566-reference/trm-part1-registers-dpll.md), [TRM 2](docs/rk3566-reference/trm-part2-dmc-hwffc-dcf.md), [Unused pins](docs/rk3566-reference/unused-pins-power-saving.md) |
| **Stock firmware** | [stock-firmware-and-findings.md](docs/stock-firmware-and-findings.md) — dumps, overview | [BSP/DDR findings](docs/stock-firmware-and-findings/bsp-and-ddr-findings.md), [SPI/boot chain](docs/stock-firmware-and-findings/spi-and-boot-chain.md) |
| **Drivers and DTS** | [drivers-and-dts.md](docs/drivers-and-dts.md) — DTS evolution, drivers | [Board DTS](docs/drivers-and-dts/board-dts-pmic-ddr-updates.md), [Drivers](docs/drivers-and-dts/drivers.md), [DTS porting](docs/drivers-and-dts/dts-porting.md), [Display](docs/drivers-and-dts/display.md), [WiFi power-off](docs/drivers-and-dts/wifi-bt-power-off.md), [Suspend](docs/drivers-and-dts/suspend-and-vdd-logic.md) |
| **Power-off / RK817 drain** | [miyoo-flip-power-off-investigation.md](docs/miyoo-flip-power-off-investigation.md) | Long-form investigation; kernel **patch 0007** (SYS_CAN_SD) |
| **Troubleshooting** | [troubleshooting.md](docs/troubleshooting.md) | — |
| **Serial** | [serial.md](docs/serial.md) | — |

Reference boot logs in `logs/`: `logs/boot_log_ROCKNIX.txt` (mainline; DMC after resume, power-down reaches `reboot: Power down`); `logs/boot_log_STOCK_INCLUDE_SLEEP_POWEROFF_AND_DEBUG.txt` (stock with DDR/sleep debug); `logs/boot_log_STOCK_INCLUDE_SLEEP_POWEROFF.txt` (stock, sleep/poweroff).

**Note:** `logs/boot_log_ROCKNIX.txt` is a **historical capture** from the archived ROCKNIX fork. It is proof of a working mainline boot (DMC after resume, power-down), not a live log of Zlyme.

---

## Device capability

What the hardware does on mainline, and where it was demonstrated. “Demonstrated” means observed on the **archived ROCKNIX fork** unless the note says stock or a hardware fact. It does **not** mean Zlyme ships that configuration. Zlyme status: [implementations/zlyme.md](docs/implementations/zlyme.md).

| Subsystem | On mainline | Notes |
| --------- | ----------- | ----- |
| Boot (U-Boot + kernel) | Demonstrated | SPI NAND or SD. Archived fork: mainline **7.0.2** at stamp `d249b09bd9` (older captures used 6.18+). |
| Display (DSI panel) | Demonstrated | 640×480. Panel controller identity is **presumed** — [Display](docs/drivers-and-dts/display.md#module-name-vs-what-is-proven). |
| Backlight | Demonstrated | PWM4 |
| Audio (RK817) | Demonstrated | Codec works. PipeWire idle **60s** and `099-audio_prime` were **archived ROCKNIX** policy ([79453c8](https://github.com/Zetarancio/distribution/commit/79453c8d9b), [32fa5f3](https://github.com/Zetarancio/distribution/commit/32fa5f3308)). |
| WiFi (RTL8733BU) | Demonstrated | USB combo. Enable GPIO is separate from the radio driver — [WiFi/BT power-off](docs/drivers-and-dts/wifi-bt-power-off.md). Driver patches **001–006** are the archived fork’s tree. |
| Bluetooth | Demonstrated | Same combo chip. Agent loop and sleep power sequencing below are archived-fork userspace/driver history ([86de663](https://github.com/Zetarancio/distribution/commit/86de6632e5), [47fb725](https://github.com/Zetarancio/distribution/commit/47fb7252bc)). |
| USB (upper / top) | Hardware fact | Host: `usb_host0_ehci` + `usb_host0_ohci`, PHY `usb2phy1_otg`, VBUS `vcc5v0_host`. OHCI needs the PHY **480 MHz** clock or suspend hangs. Proven on the archived fork ([54d8b02](https://github.com/Zetarancio/distribution/commit/54d8b02425)). |
| USB (lower / bottom) | Hardware fact | Charge + gadget (`usb_host0_xhci`, `dr_mode = "otg"`). No VBUS for a bus-powered device. |
| GPU (Mali-G52) | Demonstrated | mali_kbase + libmali, 200–800 MHz, on the archived fork |
| Storage | Demonstrated | SPI NAND MTD, both SD slots. Slots share `vqmmc`. |
| HDMI | Demonstrated when the DTS node is enabled | Video and audio |
| DMC (DDR devfreq) | Demonstrated out of tree | V2 SIP mechanism. The archived fork carried it as **patch 1012**. [BSP and DDR](docs/stock-firmware-and-findings/bsp-and-ddr-findings.md) |
| VPU / RGA | Demonstrated | hantro-vpu, rockchip-rga |
| IEP | Not on mainline | BSP-only (MPP) |
| Suspend | Standard suspend demonstrated | Deep suspend is a **separate** BL31 mode and was **left off** on the archived fork. Not claimed for Zlyme. [Suspend](docs/drivers-and-dts/suspend-and-vdd-logic.md) |
| Input | Hardware fact | GPIO buttons, UART1 stick, PWM5 rumble, hall on GPIO0_PC6. [Input](docs/hardware/input.md) |

---

## Key Discoveries

Findings that made mainline work on this device (details in the wiki).

- **VSEL register hang:** The BSP DTS uses `rockchip,suspend-voltage-selector` but mainline `fan53555` reads `fcs,suspend-voltage-selector`. Wrong name causes VDD_CPU to drop and the board to hang immediately after "FAN53555 Detected!" on kernels 6.4+.

- **DSI panel init in command mode:** The stock driver sends init commands via a DT property. On mainline, commands must be sent during `prepare()` (command mode), not `enable()` (video mode), or they collide with the video stream on the shared FIFO.

- **PMIC dependency cycles:** `vcc9-supply = <&dcdc_boost>` and some sleep pinctrl arrangements create circular dependencies that `fw_devlink` cannot resolve. The working arrangement uses `<&vccsys>` and a simpler RK817 pinctrl. Deep sleep still depends on a BL31 `ARMOFF_LOGOFF` configuration; the archived ROCKNIX fork carried that as an rk8xx/suspend patch set and then left it disabled.

- **DDR on mainline:** The BSP DMC uses Rockchip V2 SIP (shared memory + MCU/IRQ). An out-of-tree DMC devfreq driver implements that protocol. The archived ROCKNIX fork carried it as **patch 1012** on Linux **7.0.2** (older captures used 6.18+). See [BSP and DDR findings](docs/stock-firmware-and-findings/bsp-and-ddr-findings.md) and [SPI and boot chain](docs/stock-firmware-and-findings/spi-and-boot-chain.md).

- **Suspend:** **Standard** suspend was demonstrated on the archived ROCKNIX fork. **Deep sleep** (rk3568-suspend + `vdd_logic` off) stayed **deferred** there (`.testing-disabled`, `CONFIG_RK3568_SUSPEND_MODE` off) pending an **EmulationStation** fix. Zlyme has not been recorded here as enabling it. See [Suspend and vdd_logic](docs/drivers-and-dts/suspend-and-vdd-logic.md).

- **WiFi/BT full poweroff:** The 8733bu driver only does software rfkill; it does not control the power-enable GPIO. Full hardware poweroff of the combo requires a **separate driver** that controls the enable GPIO and integrates with rfkill. See [WiFi/BT power-off](docs/drivers-and-dts/wifi-bt-power-off.md).

- **Boot chain:** TF-A runtime firmware is **BL31**. **OP-TEE is BL32**, not BL31. The stock SPI FIT at `0x300000` contains BL31 (`atf-1` through `atf-6`), an OP-TEE segment labeled BL32, U-Boot, and an FDT. This repository does not record a boot that failed because OP-TEE was omitted, so that layout is the proven configuration rather than a demonstrated requirement that every U-Boot FIT include a separate OP-TEE image. Working SD boots described here also carried ATF and OP-TEE. See [Boot and flash](docs/boot-and-flash.md) and [SPI and boot chain](docs/stock-firmware-and-findings/spi-and-boot-chain.md).

- **Full power-off / off-state drain:** The **~8 mA** battery drain while “off” was traced to RK817 **SYS_CAN_SD** (charger block stays active). The archived ROCKNIX fork cleared that bit in `rk817_battery_init()` as kernel **patch 0007** (BSP parity). The bit is **battery-backed**: a true POR leaves it set (`0xe6 = 0xc5`); neither stock SPL nor that fork’s U-Boot clears it, so a warm reboot still shows `0x40` from the previous kernel. See [Power-off investigation](docs/miyoo-flip-power-off-investigation.md), [Troubleshooting](docs/troubleshooting.md), and [560a99c](https://github.com/Zetarancio/distribution/commit/560a99cbe1d6b2a3760639ca0e8e730f101e9abb). Earlier guidance to omit `system-power-controller` to “fix drain” is **obsolete** once 0007 is applied. DTS pinctrl on that fork followed upstream-style `pmic_pins` ([a482d5c](https://github.com/Zetarancio/distribution/commit/a482d5cfc4)).

- **Fuel-gauge internal resistance:** Mainline `rk817_charger.c` never reads `factory-internal-resistance-micro-ohms`.

- **2025 stock alignment:** PMIC suspend/resume, battery OCV (descending table), shared SD `vqmmc`, DMC devfreq tuning, and DSI/panel init were refined against newer stock on the archived fork. See [Stock firmware and findings](docs/stock-firmware-and-findings.md) and [Board DTS / PMIC / DDR](docs/drivers-and-dts/board-dts-pmic-ddr-updates.md). Commit history: [archived `flip`](https://github.com/Zetarancio/distribution/commits/flip/).

- **USB ports:** Two USB-C, named **upper** (top) and **lower** (bottom). Upper is **host** (`usb_host0_ehci` + `usb_host0_ohci`, `usb2phy1_otg`, VBUS `vcc5v0_host`). Disabling `usb2phy1_otg` as unused is what first broke host. The OHCI companion is required for full-speed devices, and `rk356x-base.dtsi` omits the PHY clock it needs (**480 MHz** / stock `"utmi"`); enabling the controller without that clock hung suspend in firmware. The archived fork’s node that includes the clock is [54d8b02](https://github.com/Zetarancio/distribution/commit/54d8b02425). Lower is charge/gadget on `usb_host0_xhci` and cannot raise VBUS. [Board DTS — USB](docs/drivers-and-dts/board-dts-pmic-ddr-updates.md#usb).

- **Power-off vs Wi-Fi panic:** A board that “comes back on” after `poweroff` with **`ON_SOURCE = 0x02`** was a **warm reboot** (8733bu cfg80211 BSS double-free), not a charger event. **`ON_SOURCE = 0x80`** is a genuine power-off. Patches **003/004** stop the panic. The restored multiboot preloader does not change off-state drain. [Power-off investigation — 2026-08-27](docs/miyoo-flip-power-off-investigation.md#re-verification-2026-08-27).

- **VDD_CPU / I2C0:** Retail hardware is **RK8600 only**. **TCS4525** was dropped from the board DTS after **Miyoo’s official confirmation** there is no alternate CPU-regulator SKU ([1f129e89df](https://github.com/Zetarancio/distribution/commit/1f129e89df) on the archived fork). [Board DTS — I2C0](docs/drivers-and-dts/board-dts-pmic-ddr-updates.md#i2c0-cpu-regulator).

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

**Boot logs:** Under `logs/` — historical mainline and stock captures. They are not a Zlyme runtime log.

**Active OS:** [Zlyme](https://github.com/Zetarancio/zlyme). The archived ROCKNIX fork remains at [Zetarancio/distribution](https://github.com/Zetarancio/distribution) as evidence. Legacy local build scripts live on branch `buildroot`. Flashing steps are in [docs/boot-and-flash/flashing.md](docs/boot-and-flash/flashing.md).

---

## Quick start

For the maintained Miyoo Flip OS, use [Zlyme](https://github.com/Zetarancio/zlyme). This wiki does not yet document Zlyme image filenames.

Historical ROCKNIX card images from the archived fork are described in [Where to get images](docs/boot-and-flash.md#where-to-get-images). Those Actions artifacts are not a maintained download channel.

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

- **[Zetarancio/zlyme](https://github.com/Zetarancio/zlyme)** — active Miyoo Flip OS for this project
- **[Zetarancio/distribution](https://github.com/Zetarancio/distribution)** — archived Miyoo Flip ROCKNIX fork (historical evidence)
- [ROCKNIX](https://rocknix.org/) — official upstream, external reference
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
