# Miyoo 355 joystick calibration — unpacked study bundle

## Data flow

| Component | Role |
|-----------|------|
| **MainUI** (`binaries/MainUI`) | UI: "Calibration", "Rotate joypad…", writes **`/userdata/joypad.config`** and **`/userdata/joypad_right.config`** (text `x_min=…` lines). |
| **factory_test** | Factory flow; same config paths. |
| **miyoo_inputd** (`binaries/miyoo_inputd`, source `miyoo_inputd.c`) | Reads those files at startup; maps raw UART ADC (85–200 range) to Linux `input` axes (±32760). |

## Config file format (plain text)

Parsed by `getKeyValueDefault()` in `miyoo_inputd.c` — keys must appear as `key=123` (value read with `sscanf`, first ~4 chars after `=`).

```
x_min=83
x_max=195
y_min=74
y_max=226
x_zero=134
y_zero=148
```

- **Left stick:** `/userdata/joypad.config`
- **Right stick:** `/userdata/joypad_right.config`

Defaults if file missing or invalid (min==max around zero): see `PK_ADC_DEFAULT_*` in `miyoo_inputd.c` (e.g. X 85–200, zero ~130).

## This SPI dump (`spi_20241119160817`)

- **`userdata.img`** is extracted but **not a mounted filesystem** here: the partition is **erased flash** (pattern `0xCC`). On a real device, `/userdata` is typically **ext4** (or similar) created on first boot; calibration creates the two files there.
- Use **`joypad.config.example`** / **`joypad_right.config.example`** as templates, or run **MainUI → calibration** on hardware.

## Files in this folder

- `miyoo_inputd.c` — vendor source (from `Extra/`).
- `binaries/miyoo_inputd` — stock daemon (aarch64).
- `binaries/MainUI` — launcher + calibration writer.
- `binaries/factory_test` — factory test binary.
- `binaries/icon-joystick-calibrate.png` — UI asset (if found in rootfs).

## Related stock strings (MainUI)

- `calibration step1` / `step2`
- `x_min=%d` (printf-style save)
- Lang keys 157–167 in `usr/miyoo/bin/lang/*.lang` ("Calibration", "Rotate joypad…", etc.)
