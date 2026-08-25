# Stock DTS to Mainline DTS Translation

Reference: the BSP 5.10 board DTS `rk3566-miyoo-355-v10-linux.dts`, from the vendor SDK published in [steward-fu's Miyoo Flip release](https://github.com/steward-fu/website/releases/tag/miyoo-flip), plus the [firmware dumps](../stock-firmware-and-findings.md) tracked in this repo (2024 SPI vs 2025 card image DTS).
Target: `rk3566-miyoo-flip.dts` (mainline, includes only `rk3566.dtsi`). For **PMIC, DDR, battery, SD, suspend** changes since early porting, see [Board DTS / PMIC / DDR updates](board-dts-pmic-ddr-updates.md).

## Root Node

| BSP | Mainline | Notes |
|-----|----------|-------|
| `model "MIYOO RK3566 355 V10 Board"` | `model "Miyoo Flip"` | |
| `chosen` bootargs `console=ttyFIQ0` | `console=ttyS2,1500000n8` | Mainline uses 8250 UART; BSP uses FIQ debugger |
| No `memory` node | `memory { reg = ... }` | Required for U-Boot fdt fixup |

## Critical Renames

These renames caused boot failures or hard hangs until discovered:

| BSP Property | Mainline Property | Impact |
|-------------|-------------------|--------|
| `rockchip,suspend-voltage-selector` | `fcs,suspend-voltage-selector` | **Hard hang** on 6.4+ -- fan53555 driver uses wrong VSEL register, drops VDD_CPU |
| `ttyFIQ0` | `ttyS2` | No serial output on mainline |
| `&video_phy0` | `&dsi_dphy0` | DSI PHY not found |
| `&combphy1_usq` / `&combphy2_psq` | `&combphy1` / `&combphy2` | Combo PHY not found |
| `rockchip,multicodecs-card` | `simple-audio-card` | No audio |

## Display

The display pipeline was the hardest subsystem to port. See
[display.md](display.md) for the full story.

| BSP | Mainline | Notes |
|-----|----------|-------|
| `&dsi0` panel with `simple-panel-dsi` + `panel-init-sequence` | `miyoo,flip-panel` in panel-simple.c | BSP uses DT init sequence; mainline compiles init commands into the driver |
| `&route_dsi0`, `&dsi0_in_vp0/vp1` | OF graph endpoints | Mainline uses `dsi0_in_vp1`, `vp1_out_dsi0`, `dsi0_out_panel`, `panel_in_dsi` |
| `&hdmi` (implicit) | `&hdmi` + OF graph (hdmi_in_vp0, vp0_out_hdmi) | HDMI needs explicit graph or DRM master never binds |
| `panel@0` no power/backlight | `power-supply = <&vcc3v3_lcd0_n>; backlight = <&backlight>` | Panel had no power or backlight without these |

## I2C / PMIC / Regulators

| BSP | Mainline | Notes |
|-----|----------|-------|
| `rk8600@40` with `rockchip,suspend-voltage-selector` | `fcs,suspend-voltage-selector = <1>` | **Critical.** See renames above |
| `tcs4525@1c` (vdd_cpu alt) | **omitted** | The BSP keeps this second node because the vendor kernel probes both addresses. Mainline does not need it: **Miyoo confirmed only RK8600 is populated**, so the node was dropped ([1f129e89df](https://github.com/Zetarancio/distribution/commit/1f129e89df)) rather than left to fail probe. [I2C0 CPU regulator](board-dts-pmic-ddr-updates.md#i2c0-cpu-regulator) |
| `rk817: vcc9-supply = <&dcdc_boost>` | `vcc9-supply = <&vccsys>` | Avoids PMIC->BOOST->PMIC dependency cycle |
| `rk817: pinctrl-1/2/3` (sleep/reset states) | Only `pinctrl-0 = <&pmic_int>` | Avoids PMIC->pinctrl_rk8xx->PMIC cycle | Requires patch |
| `rk817 codec` | Add `mclk` on parent node | Required for mainline RK817 codec |

## Sound

| BSP | Mainline | Notes |
|-----|----------|-------|
| `rk817-sound` (`rockchip,multicodecs-card`) | `simple-audio-card` | Mainline binding; CPU subnode needs `bitclock-master` and `frame-master` |
| `&i2s0_8ch`, `&i2s1_8ch` | Same | Needs `CONFIG_SND_SOC_ROCKCHIP_I2S_TDM=y` |

## Storage

| BSP | Mainline | Notes |
|-----|----------|-------|
| `&nandc0` | Not in mainline | BSP name |
| `&sfc flash@0` (75 MHz, 4+1 dummy) | `&sfc flash@0` (24 MHz, 1+1 dummy) | Frequency lowered for reliability; uses fixed-partitions |

## SoC Subsystems

| BSP | Mainline | Status |
|-----|----------|--------|
| `&bus_npu` | -- | BSP-only, no mainline |
| `&dfi`, `&dmc` | `&dfi`, `&dmc` + out-of-tree DMC devfreq | DMC: out-of-tree driver for mainline **7.0+** (see [BSP and DDR findings](../stock-firmware-and-findings/bsp-and-ddr-findings.md), [SPI and boot chain](../stock-firmware-and-findings/spi-and-boot-chain.md)) |
| `&iep`, `&jpegd`, `&mpp_srv` | -- | BSP-only multimedia (MPP framework) |
| `&rk_rga` | `rockchip-rga` | Mainline driver; working in ROCKNIX |
| `&rkvdec`, `&rkvenc` (VPU/vepu) | `hantro-vpu` (dec/enc) | Mainline hantro driver; working in ROCKNIX |
| `&rknpu` | -- | BSP-only, no mainline |
| `&pmu_io_domains` | Same | |
| `&saradc`, `&tsadc` | Same | |
| `&uart1` | Same | Mainline needs `dma-names = "tx", "rx"` |
| `&vop`, `&vop_mmu` | Same | |
| USB PHYs / hosts | See [USB](#usb) | Stock enables more nodes than this board uses. Mapping below. |

## USB

Stock enables almost every USB2 host and both OTG PHYs. Mainline must name which connector is which. The wrong call — treating `usb2phy1_otg` / `usb_host0_ehci` as unused — disabled the **upper USB-C host**. Current mapping: [Board DTS — USB](board-dts-pmic-ddr-updates.md#usb).

| Stock (enabled) | Mainline | Function |
|-----------------|----------|----------|
| `&usb2phy1_otg` + `&usb_host0_ehci` | **okay**, `phy-supply = <&vcc5v0_host>` | Upper USB-C **host** |
| `&usb2phy0_otg` + `&usb_host0_xhci` | okay, `dr_mode = "otg"` | Lower USB-C charge / gadget |
| `&usb2phy1_host` + `&usb_host1_ehci` | okay, `phy-supply = <&vcc_3v3>` | RTL8733BU |
| `&usb2phy0_host` + `&usb_host1_xhci` | okay, no external connector | Kept off the WiFi PHY |
| `&usb_host0_ohci`, `&usb_host1_ohci` | **disabled** | USB 1.1 companions |
| `&combphy1`, `&combphy2` | **disabled** | No USB3 / SATA / PCIe |
| `OTG_SWITCH` | present | RK817 OTG 5V, **not** upper-port VBUS |

## Nodes Not Ported (No Mainline Equivalent)

- `charge-animation` -- no mainline driver
- `vad` -- voice activity detection
- BSP-only multimedia: `iep`, `jpegd`, `mpp_srv`, `rknpu`
- `bus_npu` -- NPU not in mainline
