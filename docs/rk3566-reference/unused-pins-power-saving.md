# Unused Pins and Battery Saving (Miyoo Flip / RK3566)

> **Note:** The pin tables below were modeled on the **Miyoo Flip** board. Other RK3566 devices in the same family share the same pad types but may use different pins for their peripherals. **Adapt the pin lists to your specific board** before applying unused-pin pinctrl groups.

Distro-agnostic reference for which GPIO pins on the Miyoo Flip can be put into a **power-saving state** (tied to a defined level) to reduce leakage. Unused pins that are left floating can draw current (input buffer shoot-through). Tying them via pinctrl to pull-up or pull-down avoids that.

**Rule:** Only pins that are **not** used by any driver or function on the board may be included in an “unused pins” pinctrl group. A device tree can define pinctrl groups for unused pins and a consumer node that selects them at boot.

---

## 1. Pull configuration (RK3566 datasheet)

Use the datasheet pad type when choosing pull for an unused pin:

| Pad suffix (datasheet) | Unused pin pull |
|------------------------|-----------------|
| **_u** (default pull-up)   | Use **pull-up** when the pin is unused. |
| **_d** (default pull-down) | Use **pull-down** when the pin is unused. |
| **_z** (high-Z)            | Do not use as “unused” (e.g. TSADC). |

Source: RK3566 Datasheet Table 2-3 (Function IO Description).

---

## 2. Pin blocks that can be tied for battery saving

On the Miyoo Flip the following blocks are **not** used by hardware or by typical mainline use. They can be tied to pull-up or pull-down (per datasheet) in an unused-pins pinctrl group.

| Block | Pins | Datasheet pad | Suggested pull | Notes |
|-------|------|---------------|----------------|-------|
| GPIO0 unclaimed | D2–D7 | _d | pull-down | PMUPLL / GPIO-only or NC |
| GPIO1 I2C3/UART3 | A0–A1 | _u | pull-up | I2C3/UART3 not used on board |
| GPIO1 eMMC/Flash | B4–D4 | _u/_d | B4–C4 up; C5–D0 down; D1–D4 up | No eMMC on Miyoo Flip |
| GPIO1 I2S1 extra | A4, A6, B0–B2 | _d | pull-down | I2S1 RX/extra data not used |
| GPIO0 PMU unused | A6, A7, B0, B3, B5–B7, C0, C1, C5 | _d/_u | A6 down; A7,B0,B3,B5,B6 up; B7,C0,C1,C5 down | GPU_PWREN, FLASH_VOL_SEL, CLK32K, I2C1, I2C2, PWM0–2, PWM6 |
| GPIO2 unclaimed | B5, B7, C2–C6 | _u, _d | B5 up; B7,C2–C6 down | **Exclude B6** — UART1_CTSn (Miyoo serial joypad) |
| GPIO3 unclaimed | A0, A2, B7, C4–D7 | _d | pull-down | BT1120/CIF/EBC/GMAC/SDMMC2 not used |
| GPIO4 unclaimed | A1–C1, C3, C4 | _d | pull-down | Camera/EBC/GMAC not used |
| GPIO2 high | C7–D7 | _d | pull-down | Likely not bonded |
| GPIO4 high | D2–D7 | _d | pull-down | Not bonded |

**Critical:** **GPIO2_B6** (UART1_CTSn) must **not** be in any unused-pins group. It is used by the Miyoo serial joypad; tying it as unused breaks the joypad.

Disabling entire subsystems (e.g. WiFi, HDMI, debug UART) in the device tree frees more pins; those pins can then be tied if desired.

**Note:** Beyond unused pins, the DTS also disables **combphy1** and **combphy2** (no USB3/SATA/PCIe on this board), which powers down the PD_PIPE domain and further reduces idle power.

---

## 3. Pins that must NOT be tied (in use on Miyoo Flip)

Do **not** add these to any unused-pins group. They are used by hardware or by drivers.

| Pin(s) | GPIO | Used by |
|--------|------|---------|
| 0 | GPIO0_A0 | WiFi enable (RTL8733BU) |
| 1 | GPIO0_A1 | TSADC |
| 2–5 | GPIO0_A2–A5 | PMIC sleep, PMIC IRQ, SDMMC0 detect/power |
| 9–10 | GPIO0_B1–B2 | I2C0 (PMIC) |
| 12 | GPIO0_B4 | Power LED (gpio-leds) |
| 18 | GPIO0_C2 | Charging LED (gpio-leds) |
| 19–20 | GPIO0_C3–C4 | Backlight (PWM4), rumble (PWM5) |
| 22 | GPIO0_C6 | Hall sensor (gpio-keys) |
| 23 | GPIO0_C7 | LCD power (regulator) |
| 24–25 | GPIO0_D0–D1 | UART2 (debug serial) |
| 34–35, 37, 39, 43 | GPIO1_A2,A3,A5,A7,B3 | I2S1 (audio) |
| 44–60 | GPIO1_B4–D4 | (Unused on board; safe to tie — see table above) |
| 61–66 | GPIO1_D5–D7, GPIO2_A0–A2 | SDMMC0 (boot SD) |
| 67–74 | GPIO2_A3–B2 | SDMMC1, vcc-sd2 |
| **75–76, 78** | **GPIO2_B3,B4,B6** | **UART1 (Miyoo serial joypad)** — do not tie |
| 80–81 | GPIO2_C0–C1 | Joypad buttons |
| 97, 99–102, 103–104 | GPIO3_A1,A3–A6,A7,B0 | Joypad, volume keys |
| 105–110, 112–115 | GPIO3_B1–B6,C0–C3 | Joypad buttons |
| 128 | GPIO4_A0 | LCD reset |
| 146 | GPIO4_C2 | Speaker amplifier |
| 149–153 | GPIO4_C5–D1 | USB host, HP detect, HDMI |

**Rule:** If a pin is used by WiFi, PMIC, SD, UART1, joypad, LEDs, LCD, backlight, audio, or HDMI, do **not** add it to any unused group. Only pins explicitly listed as safe to tie (in §2) should be in an unused-pins pinctrl group.

---

## 4. Verifying at runtime

On a running system, check which pins are claimed:

```bash
cat /sys/kernel/debug/pinctrl/pinctrl-rockchip-pinctrl/pinmux-pins
```

Pins that show `(MUX UNCLAIMED) (GPIO UNCLAIMED)` before applying unused-pins groups are candidates for tying. Pins claimed by a driver (e.g. serial, gpio-keys, sdmmc) must not be in an unused group. After adding unused-pins groups, those pins should show as owned by the node that selects the unused pinctrl (e.g. `unused-pins-holder`).

**Note:** Some pins used as GPIO-only (e.g. power LED, charging LED, LCD power) may still show `(MUX UNCLAIMED)` because no pinctrl group is requested for their mux; the DTS references them only via `gpios = <&gpio0 ...>`. They are in use and must **not** be in any unused-pins group.

---

## 5. Summary

- **Pins that can be put in a power-saving state:** GPIO0 (D2–D7, and PMU unused A6,A7,B0,B3,B5–B7,C0,C1,C5), GPIO1 (A0–A1, A4,A6,B0–B2, B4–D4), GPIO2 (B5,B7,C2–C6,C7–D7 — **exclude B6**), GPIO3 (A0,A2,B7,C4–D7), GPIO4 (A1–C1,C3,C4,D2–D7).
- **Pull:** Use pull-up for datasheet _u pads, pull-down for _d pads when the pin is unused.
- **Do not tie:** UART1 (GPIO2_B3,B4,B6), joypad (GPIO2_C0,C1; GPIO3_A1,A3–A6,A7,B0,B1–B6,C0–C3), SD (GPIO0_A4,A5; GPIO1_D5–D7; GPIO2_A0–A2,A3–B2), I2S1 in use (GPIO1_A2,A3,A5,A7,B3), LCD/backlight (GPIO4_A0, GPIO0_C3,C7), PMIC (GPIO0_A2,A3,B1,B2), WiFi enable (GPIO0_A0), LEDs (GPIO0_B4,C2), hall (GPIO0_C6), debug UART (GPIO0_D0,D1), speaker amp (GPIO4_C2), USB/HDMI (GPIO4_C5–D1).
