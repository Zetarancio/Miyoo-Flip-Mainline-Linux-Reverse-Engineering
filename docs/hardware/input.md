# Input

Hardware-facing description of controls on the original Miyoo Flip. Operating-system policy (which driver, which userspace mapper) is [below](#implementations) and is not a hardware requirement.

Pin constraints and the unused-pin lists: [Unused pins](../rk3566-reference/unused-pins-power-saving.md). Historical board-DTS notes: [Joypad / input](../drivers-and-dts/board-dts-pmic-ddr-updates.md#joypad--input).

## What is on the board

| Control | Established fact |
|---------|------------------|
| Face, shoulder, and system buttons | GPIO keys, not an ADC keyboard. The archived ROCKNIX DTS described **17** GPIO switches: d-pad, A/B/X/Y, Select, Start, Mode, L1/R1, L2/R2, and both stick clicks. A per-button GPIO map is not restated here. |
| Analog stick | **UART1**, Miyoo serial protocol (`rocknix,use-miyoo-serial-joypad` in the historical DTS). Not a standard ADC stick. Line settings and frame format: [UART stick protocol](#uart-stick-protocol). |
| UART1 pins that must stay free | **GPIO2_B3, GPIO2_B4, GPIO2_B6**. **GPIO2_B6** is UART1_CTSn on this path. Tying it as an unused pin breaks the stick. |
| Volume keys | GPIO, **GPIO3_PA7** and **GPIO3_PB0**, 10 ms debounce in the historical DTS. SARADC channel 0 as `adc-keys` produced phantom volume-down / recovery and was removed from that DTS ([1f129e89df](https://github.com/Zetarancio/distribution/commit/1f129e89df)). |
| Hall (lid) | **GPIO0_PC6** on the tested unit’s DTS (`gpio_keys_hall`). Wake on **lid open** only; closing the lid while suspended did not wake. |
| Rumble | **PWM5**. The archived fork’s DTS has `pwms = <&pwm5 0 10000000 0>`. The Rockchip 3-cell PWM specifier is channel, period in nanoseconds, flags, so that is channel 0, a **10,000,000 ns / 10 ms period (100 Hz)**, flags 0. |
| Other pins the joypad uses | Do not tie GPIO2_C0, GPIO2_C1, or the GPIO3 ranges listed as joypad in [Unused pins](../rk3566-reference/unused-pins-power-saving.md). |

## UART stick protocol

**Verified from stock source.** The stock reader `spi_20241119160817/unpack/joystick_study/miyoo_inputd.c` opens `/dev/ttyS1` (UART1) and calls `trimui_uart_set(fd, 9600, 0, 8, 1, 'N')`: **9600 baud, 8N1**, hardware flow control off. It parses a six-byte frame:

```text
FF  YL  XL  YR  XR  FE
```

`0xFF` starts a frame and `0xFE` ends it. Each axis (left Y, left X, right Y, right X) is one unsigned byte. A comment in the same file gives the example frame `FF 80 9A 88 93 FE`.

**Observed on hardware, one unit.** The sender delivers about **66.8–66.9 frames/s**: about 66.8 valid frames/s in one test, and 4078 valid frames in 60.95 s (66.91/s) with the sticks untouched (2026-09-23), 0 bad frames in both. That is the sender’s own cadence, not a host polling rate. Both were measured during Zlyme’s Phase 3 joypad work, with a kernel `serdev` receiver at 9600 8N1.

## Implementations

### Stock

Stock firmware uses the same UART stick. The stock userspace reader in `joystick_study/` (2024 SPI unpack) is the source of the [protocol above](#uart-stick-protocol); this wiki does not document the rest of it. Firmware versions: [Stock](../implementations/stock.md).

### Archived ROCKNIX fork

The archived [Zetarancio/distribution](https://github.com/Zetarancio/distribution) `flip` tree exposed the stick with `rocknix-singleadc-joypad` and `rocknix,use-miyoo-serial-joypad`. Driver-source patches **0002** and **0003** carried DTS deadzone and sysfs calibration. Kernel patch **0001** (a gpiolib revert) was already gone; upstream joypad commit `1dd1115` did not need it. A **Save Miyoo Autocal** tools module stored calibration. That stack is historical: [ROCKNIX fork](../implementations/rocknix.md).

### Zlyme

[Zlyme](../implementations/zlyme.md) is the active implementation. Zlyme zlyme44 (`337ccbce`) uses its own out-of-tree driver, `miyoo-flip-gamepad`: one input device for the UART1 sticks (through `serdev`), the GPIO buttons, and PWM5 `FF_RUMBLE`, with calibration restored from userspace through sysfs. Zlyme layers InputPlumber v0.81.0 on top as OS policy, presenting virtual Xbox 360 pads to applications. InputPlumber is not required by the UART or the GPIOs. Details stay in Zlyme.
