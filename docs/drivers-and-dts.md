# Drivers and DTS

Distro-agnostic reference: board DTS evolution and required nodes for out-of-tree patches, WiFi/GPU drivers, display bring-up, BSP-to-mainline DTS porting, optional WiFi/BT GPIO power-off, and rk3568-suspend / vdd_logic deep sleep.

Full history: [Zetarancio/distribution commits on branch `flip`](https://github.com/Zetarancio/distribution/commits/flip/).

---

## Board DTS, PMIC, DDR — recent evolution

What changed on the Miyoo Flip port since early mainline bring-up: required DTS nodes for each out-of-tree patch (DMC, DFI, rk3568-suspend, rk8xx pinctrl, ON/OFF logging), RK817 suspend/power-off, **I2C0 VDD_CPU** (TCS4525 @0x1c and RK8600 @0x40 both enabled like 2025 stock—possible dual hardware revisions, unproven), DDR/DMC devfreq, shared SD `vqmmc` constraint, joypad/input, and the final validated state after reversions.

**[Full board DTS details →](drivers-and-dts/board-dts-pmic-ddr-updates.md)** | **[Patch portability analysis →](drivers-and-dts/patch-portability.md)**

---

## Drivers: WiFi/Bluetooth and GPU

RTL8733BU WiFi/BT combo driver (8733bu, out-of-tree), architecture (WiFi + BT coexistence firmware), build, test, and firmware files. Mali-G52 GPU: mali_kbase vs Panfrost, OPP table (200–800 MHz), libmali blob, DTS patch, and known harmless warnings.

**[Full drivers guide →](drivers-and-dts/drivers.md)**

---

## DTS porting (BSP to mainline)

Translation of the stock BSP 5.10 DTS to mainline: critical renames (`rockchip,suspend-voltage-selector` → `fcs,...`, `ttyFIQ0` → `ttyS2`, `video_phy0` → `dsi_dphy0`), display pipeline, I2C/PMIC/regulators, sound, storage, SoC subsystems, and nodes not ported.

**[Full DTS porting reference →](drivers-and-dts/dts-porting.md)**

---

## Display bring-up

The 640×480 MIPI DSI panel (**LMY35120-20p**; [sure vs presumed](drivers-and-dts/display.md#module-name-vs-what-is-proven)) is working on mainline. Five root causes were found: DSI init commands sent in video mode instead of command mode, missing PWM backlight driver, missing Rockchip PWM controller driver, missing DTS references on the panel node, and missing timing delays. Includes the display pipeline diagram and DSI init command reference.

**[Full display bring-up →](drivers-and-dts/display.md)**

---

## WiFi/BT combo power-off (optional)

WiFi works with the 8733bu driver. An optional separate driver shuts down the RTL8733BU combo at the GPIO level when both WiFi and Bluetooth are off, for full hardware power-off and maximum battery savings. Covers why a separate driver is needed, the typical two-rfkill implementation, and load ordering.

**[Full WiFi/BT power-off guide →](drivers-and-dts/wifi-bt-power-off.md)**

---

## Suspend and vdd_logic off-in-suspend

The out-of-tree **rk3568-suspend** driver configures BL31 deep-sleep flags via SIP SMC calls. Required for `vdd_logic` off-in-suspend — without it, turning off vdd_logic causes resume hangs. Covers the problem statement, implementation, boot/suspend/resume sequences, DTS configuration (sleep-mode-config flags), SIP protocol, debugging, and the relationship to DDR frequency scaling.

**[Full suspend guide →](drivers-and-dts/suspend-and-vdd-logic.md)**
