# Documentation index

Reference boot logs (mainline, stock) are in the repo root.

---

## Steward-fu project

| Page | Content |
|------|---------|
| [Obtain and flash](obtain-and-flash.md) | How to obtain/test images and flash with xrock. Legacy local build scripts are in branch `buildroot`. |

---

## Device wiki (distro-agnostic)

Hardware and software reference for the Miyoo Flip. No dependency on this repo’s scripts.

### Serial, flashing, boot from SD

| Page | Content |
|------|---------|
| [Serial](serial.md) | How to obtain serial: wiring, adapter, baud (1.5M), getty, login, SD slot mapping |
| [Flashing](flashing.md) | MTD layout, xrock, MASKROM, backup, flash, restore |
| [Boot from SD](boot-from-sd.md) | Brief xrock procedure; full details in Flashing |

### Hardware and drivers

| Page | Content |
|------|---------|
| [Hardware](hardware.md) | Device specs table |
| [Firmware dumps](firmware-dumps.md) | Stock unpacks: 2025 vs 2024 SPI (`miyoo355_fw_*`, `spi_*`) |
| [Board DTS / PMIC / DDR updates](board-dts-pmic-ddr-updates.md) | RK817, suspend, DMC, battery OCV, SD — vs [flip commits](https://github.com/Zetarancio/distribution/commits/flip/) |
| [Display](display.md) | DSI panel bring-up: init sequence, backlight, timing, pipeline |
| [Drivers](drivers.md) | RTL8733BU WiFi/BT and Mali-G52 GPU; full poweroff note |
| [DTS porting](dts-porting.md) | BSP-to-mainline device tree translation |
| [Troubleshooting](troubleshooting.md) | Boot hangs, kernel notes, debug bootargs |

### Boot chain, suspend, DMC, power, reference

| Page | Content |
|------|---------|
| [Boot chain](boot-chain.md) | FIT layout, OP-TEE requirement |
| [SPI image and boot chain (detailed)](spi-and-boot-chain.md) | SPI layout, FIT, BL31/OP-TEE, DDR scaling, V2 SIP |
| [Suspend and vdd_logic](suspend-and-vdd-logic.md) | rk3568-suspend, deep sleep, vdd_logic off-in-suspend |
| [BSP and DDR findings](bsp-and-ddr-findings.md) | BSP sources, DMC driver location, mainline status |
| [TRM part 1 (registers, DPLL)](trm-part1-registers-dpll.md) | TRM: DDR registers, DPLL, CRU |
| [TRM part 2 (DMC, HWFFC, DCF)](trm-part2-dmc-hwffc-dcf.md) | TRM: DMC, hardware FSP, DCF |
| [RK3566 datasheet specs](rk3566-datasheet-specs.md) | DDR timing, electrical, voltage domains |
| [WiFi/BT power-off](wifi-bt-power-off.md) | Full poweroff of RTL8733BU via GPIO driver |
| [Unused pins and battery saving](unused-pins-power-saving.md) | Pins to tie for power saving; pins to exclude |
