# Input

Hardware-facing description of controls on the original Miyoo Flip. Operating-system policy (which driver, which userspace mapper) is [below](#implementations) and is not a hardware requirement.

Pin constraints and the unused-pin lists: [Unused pins](../rk3566-reference/unused-pins-power-saving.md). Historical board-DTS notes: [Joypad / input](../drivers-and-dts/board-dts-pmic-ddr-updates.md#joypad--input).

## What is on the board

| Control | Established fact |
|---------|------------------|
| Face, shoulder, and system buttons | GPIO keys, not an ADC keyboard. The archived ROCKNIX DTS described **17** GPIO switches: d-pad, A/B/X/Y, Select, Start, Mode, L1/R1, L2/R2, and both stick clicks. A per-button GPIO map is not restated here. |
| Analog stick | **UART1**, Miyoo serial protocol (`rocknix,use-miyoo-serial-joypad` in the historical DTS). Not a standard ADC stick. Byte-level frames are not copied into this page; the 2024 SPI unpack has `spi_20241119160817/unpack/joystick_study/` as study notes. |
| UART1 pins that must stay free | **GPIO2_B3, GPIO2_B4, GPIO2_B6**. **GPIO2_B6** is UART1_CTSn on this path. Tying it as an unused pin breaks the stick. |
| Volume keys | GPIO, **GPIO3_PA7** and **GPIO3_PB0**, 10 ms debounce in the historical DTS. SARADC channel 0 as `adc-keys` produced phantom volume-down / recovery and was removed from that DTS ([1f129e89df](https://github.com/Zetarancio/distribution/commit/1f129e89df)). |
| Hall (lid) | **GPIO0_PC6** on the tested unit’s DTS (`gpio_keys_hall`). Wake on **lid open** only; closing the lid while suspended did not wake. |
| Rumble | **PWM5**, period 10 MHz in the historical DTS. |
| Other pins the joypad uses | Do not tie GPIO2_C0, GPIO2_C1, or the GPIO3 ranges listed as joypad in [Unused pins](../rk3566-reference/unused-pins-power-saving.md). |

## Implementations

### Stock

Stock firmware uses the same UART stick. This wiki does not document the stock userspace reader beyond `joystick_study/` in the 2024 SPI unpack. Firmware versions: [Stock](../implementations/stock.md).

### Archived ROCKNIX fork

The archived [Zetarancio/distribution](https://github.com/Zetarancio/distribution) `flip` tree exposed the stick with `rocknix-singleadc-joypad` and `rocknix,use-miyoo-serial-joypad`. Driver-source patches **0002** and **0003** carried DTS deadzone and sysfs calibration. Kernel patch **0001** (a gpiolib revert) was already gone; upstream joypad commit `1dd1115` did not need it. A **Save Miyoo Autocal** tools module stored calibration. That stack is historical: [ROCKNIX fork](../implementations/rocknix.md).

### Zlyme

[Zlyme](../implementations/zlyme.md) is the active implementation. This wiki does not yet record a Zlyme joypad driver or an InputPlumber policy. InputPlumber, if Zlyme uses it later, is an OS policy choice. It is not required by the UART or the GPIOs.
