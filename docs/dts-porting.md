# Stock DTS to Mainline DTS Translation

Reference: `Extra/rockchip/rk3566-miyoo-355-v10-linux.dts` (BSP 5.10, from steward-fu).
Target: `rk3566-miyoo-flip.dts` (mainline, includes only `rk3566.dtsi`).

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
| `tcs4525@1c` (vdd_cpu alt) | `status = "disabled"` | Not populated; disable to avoid probe noise |
| `rk817: vcc9-supply = <&dcdc_boost>` | `vcc9-supply = <&vccsys>` | Avoids PMIC->BOOST->PMIC dependency cycle |
| `rk817: pinctrl-1/2/3` (sleep/reset states) | Only `pinctrl-0 = <&pmic_int>` | Avoids PMIC->pinctrl_rk8xx->PMIC cycle |
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
| `&bus_npu`, `&dfi`, `&dmc` | -- | BSP-only, no mainline equivalent |
| `&iep`, `&jpegd`, `&mpp_srv` | -- | BSP-only multimedia |
| `&rk_rga`, `&rkvdec`, `&rkvenc`, `&rknpu` | -- | BSP-only, no mainline driver |
| `&pmu_io_domains` | Same | |
| `&saradc`, `&tsadc` | Same | |
| `&uart1` | Same | Mainline needs `dma-names = "tx", "rx"` |
| `&vop`, `&vop_mmu` | Same | |

## Nodes Not Ported (No Mainline Equivalent)

- `charge-animation` -- no mainline driver
- `vad` -- voice activity detection
- BSP multimedia: `rk_rga`, `rkvdec`, `rkvenc`, `rknpu`, `iep`, `jpegd`, `mpp_srv`
- DMC/DFI -- DDR frequency scaling (closed-source dependencies)
- `bus_npu` -- NPU not in mainline
