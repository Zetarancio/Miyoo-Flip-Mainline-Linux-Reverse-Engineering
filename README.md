# Miyoo Flip — Device Wiki & Reference

This repository is the **maintained wiki and reference** for the **Miyoo Flip** handheld (Rockchip RK3566) on mainline Linux. The documentation is kept up to date as the canonical device reference.

**ROCKNIX images:** **[Zetarancio/distribution](https://github.com/Zetarancio/distribution)** — GitHub Actions publishes **generic** and **device-specific** builds on branch **`flip`** (use the **device-specific** artifact for Miyoo Flip). Day-to-day DTS and kernel integration for this wiki tracks branch **`next`** ahead of those freezes.

The distribution repo holds the build system and device sources; **this `main` branch** is documentation, reference material, and small helper assets. Legacy local build scripts live on branch **`buildroot`**.

**Wiki `flip` stamp:** [`d249b09bd9`](https://github.com/Zetarancio/distribution/commit/d249b09bd9) — *Merge commit '1ebff24f36' into flip* (2026-09-02). **RK3566 kernel:** **Linux 7.0.2**. **Recent Miyoo / RK3566 commits on `flip`:** [OHCI companion with PHY clock](https://github.com/Zetarancio/distribution/commit/54d8b02425) · [Merge commit 1ebff24f36](https://github.com/Zetarancio/distribution/commit/d249b09bd9) · [drop post-sleep rfkill quirk](https://github.com/Zetarancio/distribution/commit/47fb7252bc) · [RTL8733BU indicate a disconnect once](https://github.com/Zetarancio/distribution/commit/ecccdef4b9) · [restore WPA3/SAE](https://github.com/Zetarancio/distribution/commit/69d1b1714b) · [POWER cut chip power for suspend](https://github.com/Zetarancio/distribution/commit/e728b28834) · [drop concurrent mode](https://github.com/Zetarancio/distribution/commit/6a7ac83e87) · [Bluetooth agent event loop](https://github.com/Zetarancio/distribution/commit/86de6632e5) · [7.1-port tree](https://github.com/Zetarancio/distribution/commit/3c149fbbf9) · [upper USB-C host](https://github.com/Zetarancio/distribution/commit/06fd5cd044). [board DTS](docs/drivers-and-dts/board-dts-pmic-ddr-updates.md) · [commits/flip](https://github.com/Zetarancio/distribution/commits/flip/).

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
| WiFi (RTL8733BU)         | Working               | 7.1-port tree + local patches **001–006** (shutdown hook, suspend bound, two BSS double-release fixes, one wlan interface, SAE/WPA3). Optional GPIO cut-off: [WiFi/BT power-off](docs/drivers-and-dts/wifi-bt-power-off.md). |
| Bluetooth                | Working               | Unified firmware, btusb re-probe. Agent event loop after the dbussy bump ([86de663](https://github.com/Zetarancio/distribution/commit/86de6632e5)). After sleep the chip is powered from **RTL8733BU-POWER** `.resume` before `bluetooth.service`; the post-sleep rfkill quirk is gone ([47fb725](https://github.com/Zetarancio/distribution/commit/47fb7252bc)). |
| USB (upper USB-C)        | Working               | **Top** connector. USB 2.0 **host** (`usb_host0_ehci` + **`usb_host0_ohci`**, `usb2phy1_otg`, VBUS `vcc5v0_host`). The OHCI companion is required, and it needs the PHY’s **480 MHz** as a fourth clock ([54d8b02](https://github.com/Zetarancio/distribution/commit/54d8b02425)); without the companion, full-speed hubs power but never enumerate. A high-inrush hub already inserted at power-on can brown out the board on battery. |
| USB (lower USB-C)        | Working               | **Bottom** connector. Charge + gadget (`usb_host0_xhci`, `dr_mode = "otg"`). Cannot host a bus-powered device: no VBUS on that PHY. |
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

- **Full power-off / off-state drain:** The **~8 mA** battery drain while “off” was traced to RK817 **SYS_CAN_SD** (charger block stays active). **Kernel patch 0007** clears that bit in `rk817_battery_init()` (BSP parity). The bit is **battery-backed**: a true POR leaves it set (`0xe6 = 0xc5`); neither stock SPL nor ROCKNIX U-Boot clears it, so a warm reboot still shows `0x40` from the previous kernel. See [Power-off investigation](docs/miyoo-flip-power-off-investigation.md), [Troubleshooting](docs/troubleshooting.md), and [560a99c](https://github.com/Zetarancio/distribution/commit/560a99cbe1d6b2a3760639ca0e8e730f101e9abb). Earlier guidance to omit `system-power-controller` to “fix drain” is **obsolete** once 0007 is applied; DTS follows the current `flip` tree (e.g. upstream-style `pmic_pins`, [a482d5c](https://github.com/Zetarancio/distribution/commit/a482d5cfc4)).

- **Fuel-gauge internal resistance:** Mainline `rk817_charger.c` never reads `factory-internal-resistance-micro-ohms`.

- **2025 stock alignment:** PMIC suspend/resume, battery OCV (descending table), shared SD `vqmmc`, DMC devfreq tuning, and DSI/panel init have been refined against newer stock; see [Stock firmware and findings](docs/stock-firmware-and-findings.md) and [Board DTS / PMIC / DDR](docs/drivers-and-dts/board-dts-pmic-ddr-updates.md). Commit history: [distribution `flip`](https://github.com/Zetarancio/distribution/commits/flip/).

- **USB ports:** Two USB-C, named **upper** (top) and **lower** (bottom). Upper is **host** (`usb_host0_ehci` + `usb_host0_ohci`, `usb2phy1_otg`, VBUS `vcc5v0_host`). Disabling `usb2phy1_otg` as unused is what first broke host. The OHCI companion is required for full-speed devices, and `rk356x-base.dtsi` omits the PHY clock it needs (**480 MHz** / stock `"utmi"`); enabling the controller without that clock hung suspend in firmware. Current node: [54d8b02](https://github.com/Zetarancio/distribution/commit/54d8b02425). Lower is charge/gadget on `usb_host0_xhci` and cannot raise VBUS. [Board DTS — USB](docs/drivers-and-dts/board-dts-pmic-ddr-updates.md#usb).

- **Power-off vs Wi-Fi panic:** A board that “comes back on” after `poweroff` with **`ON_SOURCE = 0x02`** was a **warm reboot** (8733bu cfg80211 BSS double-free), not a charger event. **`ON_SOURCE = 0x80`** is a genuine power-off. Patches **003/004** stop the panic. The restored multiboot preloader does not change off-state drain. [Power-off investigation — 2026-08-27](docs/miyoo-flip-power-off-investigation.md#re-verification-2026-08-27).

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
