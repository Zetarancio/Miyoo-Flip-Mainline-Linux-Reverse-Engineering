# DDR exploration (Miyoo Flip / RK3566)

Notes on DDR init, DMC, boot chain, and suspend for the Miyoo Flip (RK3566). The BSP uses Rockchip rkbin (DDR init blob + BL31); mainline can use **out-of-tree drivers** for DMC devfreq and for **deep sleep** (rk3568-suspend), confirmed working with mainline kernel 6.18+.

**Naming:** The suspend driver is **rk3568-suspend** (not rk356x). It configures **deep sleep** (BL31 power-down of logic/center/oscillator), not generic “sleep.” It is required for `vdd_logic` off-in-suspend to work.

**ROCKNIX:** Both the DMC devfreq (rk3568-dmc) and rk3568-suspend drivers are available in [ROCKNIX](https://rocknix.org/) via [Zetarancio/distribution](https://github.com/Zetarancio/distribution) (branch `flip`).

## Index

| Doc | Content |
|-----|--------|
| [01 - BSP file listing and DDR findings](01-bsp-file-listing-and-ddr-findings.md) | BSP sources, DMC driver location, mainline driver status |
| [02 - TRM part 1 (registers and DPLL)](02-trm-part1-registers-and-dpll.md) | TRM excerpts: registers, DPLL |
| [03 - TRM part 2 (DMC, HWFFC, DCF)](03-trm-part2-dmc-hwffc-dcf.md) | TRM excerpts: DMC, hardware FSP, DCF |
| [04 - RK3566 datasheet DDR specs](04-rk3566-datasheet-ddr-specs.md) | Datasheet DDR timing / electrical specs |
| [05 - SPI image analysis and boot chain](05-spi-image-analysis-and-boot-chain.md) | SPI layout, FIT components, BL31/OP-TEE, DDR scaling, V2 SIP |
| [06 - Suspend driver and vdd_logic](06-suspend-driver-and-vdd-logic.md) | rk3568-suspend (BL31 **deep sleep**), vdd_logic off-in-suspend |
| [07 - WiFi/BT combo power-off](07-wifi-bt-combo-power.md) | Why full poweroff of RTL8733BU needs a separate GPIO power driver |

## Summary

- **DDR init:** Handled by Rockchip blob (loader) + BL31; version must match. No mainline replacement for the blob.
- **DMC scaling:** BSP `rockchip_dmc.c` uses V2 SIP (shared memory + MCU/IRQ). An out-of-tree mainline driver (rk3568-dmc) implements this and works; see ROCKNIX [Zetarancio/distribution](https://github.com/Zetarancio/distribution) (branch `flip`).
- **Boot chain:** Any U-Boot for this board must include OP-TEE (BL32) in the FIT image (ATF + OP-TEE + U-Boot).
- **Deep sleep:** Out-of-tree driver **rk3568-suspend** (compatible `rk3568,pm-config`) configures BL31 **deep-sleep** flags via SIP. It is required for `vdd_logic` off-in-suspend; without it, turning off vdd_logic in suspend causes hang on resume. Available in ROCKNIX [Zetarancio/distribution](https://github.com/Zetarancio/distribution) (branch `flip`). See [06 - Suspend driver and vdd_logic](06-suspend-driver-and-vdd-logic.md).
- **WiFi/BT full poweroff:** The RTL8733BU USB driver (8733bu) only does software rfkill; it does **not** control the board’s power-enable GPIO. Full hardware poweroff of the combo chip requires a **separate driver** that owns the enable GPIO and integrates with rfkill. See [07 - WiFi/BT combo power-off](07-wifi-bt-combo-power.md).
