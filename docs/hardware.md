# Hardware specifications

Device specs for the Miyoo Flip (RK3566). For serial console wiring and usage see [Serial](serial.md). For storage layout and flashing see [Flashing](flashing.md).

---

## Miyoo Flip specifications

| Component | Detail |
|-----------|--------|
| SoC | Rockchip RK3566 (quad Cortex-A55 @ 1.8 GHz) |
| GPU | Mali-G52 2EE (Bifrost), 200–800 MHz |
| RAM | LPDDR4 |
| Storage | SPI NAND 128 MB (Winbond, via SFC) |
| SD slots | 2× MicroSD (MMC1 @ fe2b0000, MMC2 @ fe2c0000) |
| Display | 640×480 MIPI DSI, FT8006M controller, 2-lane RGB888 burst |
| Backlight | PWM4 |
| WiFi/BT | RTL8733BU (USB combo) |
| Audio | RK817 codec, I2S, speaker amplifier |
| PMIC | RK817 (main) + RK8600 at I2C 0x40 (VDD_CPU) |
| USB | USB 2.0 OTG |
| UART | ttyS2 (fe660000), 1,500,000 baud, 3.3V |

Pinout and board photos: [steward-fu pin mapping](https://steward-fu.github.io/website/handheld/miyoo_flip_pin.htm), [specs](https://steward-fu.github.io/website/handheld/miyoo_flip_spec.htm). SD slot mapping is in [Serial — SD card slot mapping](serial.md).
