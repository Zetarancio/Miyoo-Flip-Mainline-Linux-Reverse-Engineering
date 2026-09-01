# Documentation index

Reference boot logs (mainline, stock) are in **`logs/`**. **`logs/boot_log_ROCKNIX.txt`** is a **historical capture** and may **not** match the latest kernel/DTS.

**`flip` images:** [commits/flip](https://github.com/Zetarancio/distribution/commits/flip/) — wiki README: tip **`9c5dee6d29`** (*Merge upstream/next into flip*, 2026-09-02), RK3566 kernel **7.0.2**.

---

## Device wiki (distro-agnostic)

| Page | Content |
|------|---------|
| [Boot and flash](boot-and-flash.md) | Hardware specs, where to get images, boot chain, flashing overview, SD boot overview |
| [→ Flashing (full guide)](boot-and-flash/flashing.md) | MTD layout, xrock, MASKROM, backup, flash, restore, boot.img format, mtdparts, and the xrock procedure for [booting from SD](boot-and-flash/flashing.md#booting-from-sd) |
| [→ SD multiboot via a repaired preloader](boot-and-flash/sd-multiboot-apommel.md) | **Stock + SD distro at once** (method by [apommel](https://github.com/apommel/baseos-my355)): stock / ROCKNIX / SpruceOS / MinUI base work; Knulli/GammaOS cards do not |
| [→ MASKROM and SD boot by erasing the preloader](boot-and-flash/stock-rocknix-without-disassembly.md) | Preloader eraser as **MASKROM access**, restoring internal stock boot, recovery when nothing boots |
| [RK3566 reference](rk3566-reference.md) | SoC overview: DDR specs, voltage domains, PLLs |
| [→ Datasheet specs](rk3566-reference/datasheet-specs.md) | DDR types/frequencies, voltage rails, IO leakage, OPP validation |
| [→ TRM Part 1](rk3566-reference/trm-part1-registers-dpll.md) | DDR registers, DPLL, CRU, DDR_GRF, PMU |
| [→ TRM Part 2](rk3566-reference/trm-part2-dmc-hwffc-dcf.md) | DMC, HWFFC, DCF, FSP, DFI monitor |
| [→ Unused pins](rk3566-reference/unused-pins-power-saving.md) | GPIO pins to tie for power saving (Miyoo Flip model, adapt to your board) |
| [Stock firmware and findings](stock-firmware-and-findings.md) | Stock dumps, BSP analysis overview |
| [→ BSP and DDR findings](stock-firmware-and-findings/bsp-and-ddr-findings.md) | BSP sources, DMC driver, BL31/ATF, kernel config |
| [→ SPI and boot chain](stock-firmware-and-findings/spi-and-boot-chain.md) | SPI layout, FIT, BL31 strings, DDR scaling, V2 SIP |
| [→ OTA update mechanism](stock-firmware-and-findings/ota-update-mechanism.md) | `miyoo355_fw.img` format and update script, why it spares the preloader, version gating, root-code hook on stock |
| [Drivers and DTS](drivers-and-dts.md) | Board DTS evolution, drivers, display, suspend overview |
| [→ Board DTS / PMIC / DDR](drivers-and-dts/board-dts-pmic-ddr-updates.md) | Required DTS nodes for patches, RK817, I2C0 RK8600, DMC, SD, joypad, **USB port map**, final state |
| [→ Patch portability](drivers-and-dts/patch-portability.md) | Detailed analysis: what each patch reads from DTS, BSP vs ROCKNIX, portability to other RK3566/RK3568 boards |
| [→ Drivers (WiFi/BT, GPU)](drivers-and-dts/drivers.md) | RTL8733BU and Mali-G52 GPU drivers |
| [→ DTS porting](drivers-and-dts/dts-porting.md) | BSP-to-mainline device tree translation |
| [→ Display](drivers-and-dts/display.md) | DSI panel bring-up, init sequence, pipeline |
| [→ WiFi/BT power-off](drivers-and-dts/wifi-bt-power-off.md) | Optional GPIO-level power-off for RTL8733BU |
| [→ Suspend and vdd_logic](drivers-and-dts/suspend-and-vdd-logic.md) | Standard vs deep suspend; **`next`** branch status; rk3568-suspend disabled pending ES upstream; standby estimates |
| [Power-off / RK817 drain (full investigation)](miyoo-flip-power-off-investigation.md) | ~8 mA off-state drain: **SYS_CAN_SD** (reg 0xe6), patch 0007; 2026-08-27: preloader irrelevant, Wi-Fi panic was the false “self-wake” |
| [Troubleshooting](troubleshooting.md) | Boot hangs, kernel notes, debug bootargs, power-off summary |
| [Serial](serial.md) | How to obtain serial: wiring, adapter, baud (1.5M), getty, login |
