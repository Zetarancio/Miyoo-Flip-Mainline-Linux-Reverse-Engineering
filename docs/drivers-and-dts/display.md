# Display Bring-Up

## Status: Working

The Miyoo Flip's 640x480 MIPI DSI panel is fully functional on mainline
Linux 6.19.

## Problem

The BSP kernel uses a Rockchip-specific `simple-panel-dsi` driver that
reads init commands from a `panel-init-sequence` DT property. This
driver and DT property do not exist in mainline.

## Root Causes (All Five Were Needed)

### 1. Panel init commands sent in video mode

The DW MIPI DSI bridge switches to **video mode** before calling
`drm_panel_enable()`. Sending DSI init commands in `enable()` meant
they competed with the video stream for the shared payload FIFO,
causing `-ETIMEDOUT` errors.

**Fix:** Send DSI init commands in `prepare()` instead. The bridge
ordering (`pre_enable_prev_first = true`) guarantees `prepare()` runs
while the DSI host is still in **command mode**.

### 2. Missing PWM backlight driver

`CONFIG_BACKLIGHT_PWM=m` (module) but no module infrastructure.
Backlight driver never loaded.

**Fix:** `CONFIG_BACKLIGHT_PWM=y` (built-in).

### 3. Missing Rockchip PWM controller driver

Without `CONFIG_PWM_ROCKCHIP`, PWM4 could not generate a signal.

**Fix:** `CONFIG_PWM=y`, `CONFIG_PWM_ROCKCHIP=y`.

### 4. Missing DTS references on panel node

The `panel@0` node did not reference the LCD power supply or backlight.

**Fix:** Added `power-supply = <&vcc3v3_lcd0_n>` and `backlight = <&backlight>`
to `panel@0` in the DTS.

### 5. Missing panel timing delays

The BSP uses `init-delay-ms = 200` and `enable-delay-ms = 200`. A
mainline panel descriptor without these delays can fail.

**Fix:** Add `.delay = { .prepare = 200, .enable = 200, .disable = 20,
.unprepare = 20 }` to the panel descriptor (or equivalent in your driver).

## Display Pipeline (Mainline)

```
VOP2 (VP1) ──OF graph──> DSI host (fe060000) ──OF graph──> panel@0
                              |                                |
                      dw-mipi-dsi-rockchip              panel-simple-dsi
                      dw-mipi-dsi (bridge)             (miyoo,flip-panel)
                              |
                         dsi_dphy0
```

### DRM Bridge Call Sequence

1. `dsi_bridge.atomic_pre_enable()` -- configures DSI, enters **command mode**
2. `panel_bridge.pre_enable()` -> `drm_panel_prepare()` -> `panel_simple_prepare()`
   - Power supply on, 200 ms delay
   - **DSI init commands sent here** (command mode, clean FIFO)
3. `dsi_bridge.atomic_enable()` -- switches to **video mode**
4. `panel_bridge.enable()` -> `drm_panel_enable()` -> `panel_simple_enable()`
   - 200 ms enable delay, then backlight on

## DSI Init Commands

The BSP `panel-init-sequence` was decoded into 22 structured commands:

```
[type] [delay_ms] [len] [payload...]
 0x05   0xFA       0x01  0x11          Sleep Out, 250 ms
 0x05   0x20       0x01  0x29          Display On, 32 ms
 0x29   0x00       0x04  B9 F1 12 87   Vendor register setup
 ...
```

Plus 2 exit commands (Display Off + Sleep In). These are compiled into
the `miyoo_flip_panel` descriptor in `panel-simple.c`.

## Backlight minimum and resume

**PWM 4/255 is the minimum** that reliably latches on cold resume at 800 Hz ([e78fefa](https://github.com/Zetarancio/distribution/commit/e78fefa352156b5bb718a5a77ece264016a4dd28)). PWM 2/255 (0.78% duty) lights the panel during normal operation but fails to latch after deep sleep. PWM 4/255 (1.57% duty) reliably latches while still being very dim. A 20 ms post-PWM-on delay is added for additional stability.

## Files Changed

| File | Change |
|------|--------|
| `panel-simple.c` (kernel patch) | Panel descriptor with mode, DSI init/exit sequences, timing delays. `panel_simple_dsi_send_one()` with retry logic |
| `rk3566-miyoo-flip.dts` | `power-supply`, `backlight` on panel; OF graph endpoints for DSI/HDMI/VOP; PWM minimum 4/255 at 800 Hz, 20 ms post-PWM-on delay |
| Kernel config | `CONFIG_BACKLIGHT_PWM=y`, `CONFIG_PWM=y`, `CONFIG_PWM_ROCKCHIP=y` |

## Verification

```bash
# Should show colored noise on the 640x480 LCD
dd if=/dev/urandom of=/dev/fb0 bs=4096 count=300
```
