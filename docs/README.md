# Documentation index

How to read this wiki: [Documentation model](DOCUMENTATION_MODEL.md).

Reference boot logs are in **`logs/`**. **`logs/boot_log_ROCKNIX.txt`** is a **historical capture** from the archived ROCKNIX fork. It is not a Zlyme log.

---

## Hardware and SoC

| Page | Content |
|------|---------|
| [RK3566 reference](rk3566-reference.md) | SoC overview: DDR specs, voltage domains, PLLs |
| [→ Datasheet specs](rk3566-reference/datasheet-specs.md) | DDR types/frequencies, voltage rails, IO leakage, OPP validation |
| [→ TRM Part 1](rk3566-reference/trm-part1-registers-dpll.md) | DDR registers, DPLL, CRU, DDR_GRF, PMU |
| [→ TRM Part 2](rk3566-reference/trm-part2-dmc-hwffc-dcf.md) | DMC, HWFFC, DCF, FSP, DFI monitor |
| [→ Unused pins](rk3566-reference/unused-pins-power-saving.md) | GPIO pins to tie for power saving. **GPIO2_B6** is the joypad UART, not unused |
| [Input](hardware/input.md) | Buttons, UART1 stick, hall, volume, PWM5 rumble |
| [Serial](serial.md) | Debug UART: wiring, 1.5 Mbaud, getty |
| [Display](drivers-and-dts/display.md) | Panel facts vs presumption, DSI init, backlight |

## Boot and firmware

| Page | Content |
|------|---------|
| [Boot and flash](boot-and-flash.md) | Hardware overview, boot chain, historical ROCKNIX image names, SD boot overview |
| [→ Flashing](boot-and-flash/flashing.md) | MTD layout, xrock, MASKROM, backup, flash, boot.img, mtdparts |
| [→ SD multiboot](boot-and-flash/sd-multiboot-apommel.md) | apommel preloader repair: stock and an SD OS together |
| [→ Erase the preloader](boot-and-flash/stock-rocknix-without-disassembly.md) | PreloaderEraser as MASKROM access |
| [SPI and boot chain](stock-firmware-and-findings/spi-and-boot-chain.md) | SPI layout, FIT, BL31, V2 SIP DDR scaling |

## Drivers and protocols

| Page | Content |
|------|---------|
| [Drivers and DTS](drivers-and-dts.md) | Index of board DTS, drivers, porting, suspend |
| [→ Board DTS / PMIC / DDR](drivers-and-dts/board-dts-pmic-ddr-updates.md) | Evolution notes. Mixes hardware conclusions with archived-fork patch history; the page says which is which |
| [→ Patch portability](drivers-and-dts/patch-portability.md) | What each historical patch reads from DTS, and what is portable |
| [→ Drivers (WiFi/BT, GPU)](drivers-and-dts/drivers.md) | RTL8733BU and Mali-G52 |
| [→ DTS porting](drivers-and-dts/dts-porting.md) | BSP-to-mainline device tree translation |
| [→ WiFi/BT power-off](drivers-and-dts/wifi-bt-power-off.md) | Enable-GPIO behavior vs OS policy |
| [→ Suspend and vdd_logic](drivers-and-dts/suspend-and-vdd-logic.md) | Mechanism first; archived-fork shipping state at the end |
| [→ USB](drivers-and-dts/board-dts-pmic-ddr-updates.md#usb) | Upper host (EHCI+OHCI) and lower charge/gadget |

## Stock and BSP evidence

| Page | Content |
|------|---------|
| [Stock firmware and findings](stock-firmware-and-findings.md) | 20250527 and 20241119 dumps |
| [→ BSP and DDR](stock-firmware-and-findings/bsp-and-ddr-findings.md) | BSP DMC, BL31, mainline V2-SIP driver |
| [→ OTA update mechanism](stock-firmware-and-findings/ota-update-mechanism.md) | `miyoo355_fw.img`; the update spares the preloader |

## Investigations

| Page | Content |
|------|---------|
| [Power-off / RK817 drain](miyoo-flip-power-off-investigation.md) | Lab notebook. Conclusion: **SYS_CAN_SD**. Do not treat early sections as the final story |

## Implementations

| Page | Content |
|------|---------|
| [Overview](implementations/README.md) | Hardware truth vs implementation status |
| [Zlyme](implementations/zlyme.md) | **Active** OS. No feature snapshot recorded here yet |
| [ROCKNIX fork](implementations/rocknix.md) | **Archived** historical implementation |
| [Stock](implementations/stock.md) | Vendor firmware versions |

## Troubleshooting and tools

| Page | Content |
|------|---------|
| [Troubleshooting](troubleshooting.md) | Split into mainline/hardware, historical ROCKNIX runtime, and superseded notes |
| [`preloader-stock-rocknix/`](../preloader-stock-rocknix/README.md) | Multiboot and PreloaderEraser. Directory name is historical; the tools are unchanged |
