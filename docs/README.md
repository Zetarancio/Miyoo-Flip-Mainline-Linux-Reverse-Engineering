# Documentation index

Reference boot logs (mainline, stock) are in the repo root. **`boot_log_ROCKNIX.txt`** is a **historical capture** (proof of e.g. DMC/resume/power-down) and may **not** match the latest kernel/DTS.

---

## Device wiki (distro-agnostic)

| Page | Content |
|------|---------|
| [Boot and flash](boot-and-flash.md) | Hardware specs, where to get images, boot chain, flashing overview, SD boot overview |
| [→ Flashing (full guide)](boot-and-flash/flashing.md) | MTD layout, xrock, MASKROM, backup, flash, restore, boot.img format, mtdparts |
| [→ Boot from SD](boot-and-flash/boot-from-sd.md) | Brief xrock procedure to boot from SD |
| [RK3566 reference](rk3566-reference.md) | SoC overview: DDR specs, voltage domains, PLLs |
| [→ Datasheet specs](rk3566-reference/datasheet-specs.md) | DDR types/frequencies, voltage rails, IO leakage, OPP validation |
| [→ TRM Part 1](rk3566-reference/trm-part1-registers-dpll.md) | DDR registers, DPLL, CRU, DDR_GRF, PMU |
| [→ TRM Part 2](rk3566-reference/trm-part2-dmc-hwffc-dcf.md) | DMC, HWFFC, DCF, FSP, DFI monitor |
| [→ Unused pins](rk3566-reference/unused-pins-power-saving.md) | GPIO pins to tie for power saving (Miyoo Flip model, adapt to your board) |
| [Stock firmware and findings](stock-firmware-and-findings.md) | Stock dumps, BSP analysis overview |
| [→ BSP and DDR findings](stock-firmware-and-findings/bsp-and-ddr-findings.md) | BSP sources, DMC driver, BL31/ATF, kernel config |
| [→ SPI and boot chain](stock-firmware-and-findings/spi-and-boot-chain.md) | SPI layout, FIT, BL31 strings, DDR scaling, V2 SIP |
| [Drivers and DTS](drivers-and-dts.md) | Board DTS evolution, drivers, display, suspend overview |
| [→ Board DTS / PMIC / DDR](drivers-and-dts/board-dts-pmic-ddr-updates.md) | Required DTS nodes for patches, RK817, I2C0 TCS4525/RK8600, DMC, SD, joypad, final state |
| [→ Drivers (WiFi/BT, GPU)](drivers-and-dts/drivers.md) | RTL8733BU and Mali-G52 GPU drivers |
| [→ DTS porting](drivers-and-dts/dts-porting.md) | BSP-to-mainline device tree translation |
| [→ Display](drivers-and-dts/display.md) | DSI panel bring-up, init sequence, pipeline |
| [→ WiFi/BT power-off](drivers-and-dts/wifi-bt-power-off.md) | Optional GPIO-level power-off for RTL8733BU |
| [→ Suspend and vdd_logic](drivers-and-dts/suspend-and-vdd-logic.md) | rk3568-suspend, deep sleep, vdd_logic off-in-suspend |
| [Troubleshooting](troubleshooting.md) | Boot hangs, kernel notes, debug bootargs |
| [Serial](serial.md) | How to obtain serial: wiring, adapter, baud (1.5M), getty, login, SD slot mapping |
