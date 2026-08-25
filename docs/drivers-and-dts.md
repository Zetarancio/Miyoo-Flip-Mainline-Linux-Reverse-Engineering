# Drivers and DTS

Distro-agnostic reference: board DTS evolution and required nodes for out-of-tree patches, WiFi/GPU drivers, display bring-up, BSP-to-mainline DTS porting, optional WiFi/BT GPIO power-off, and rk3568-suspend / vdd_logic deep sleep.

Commit history: [`next` (integration)](https://github.com/Zetarancio/distribution/commits/next/) · [`flip` (device images)](https://github.com/Zetarancio/distribution/commits/flip/).

---

## Board DTS, PMIC, DDR — recent evolution

What changed on the Miyoo Flip port since early mainline bring-up: out-of-tree patches (DMC **1012**, DFI **1010**, deferred **1013**, **0007** RK817 drain), **I2C0 RK8600** only (TCS4525 dropped per Miyoo confirmation), joypad, audio/PipeWire quirks, RTL8733BU stack, upper USB-C host. **Kernel:** **7.0.2** on `flip` (tip **`3c149fbbf9`**).

**[Full board DTS details →](drivers-and-dts/board-dts-pmic-ddr-updates.md)** | **[Patch portability analysis →](drivers-and-dts/patch-portability.md)**

---

## Drivers: WiFi/Bluetooth and GPU

RTL8733BU WiFi/BT combo from [Awesome-Embedded-Learning-Studio/rtl8733bu-linux-driver](https://github.com/Awesome-Embedded-Learning-Studio/rtl8733bu-linux-driver) (pinned for 7.0.2; **no local patches**), architecture, firmware, optional GPIO power-off. Mali-G52: mali_kbase vs Panfrost, OPP table (200–800 MHz), **libmali g29p1**, DTS patch, known harmless warnings.

**[Full drivers guide →](drivers-and-dts/drivers.md)**

---

## DTS porting (BSP to mainline)

Translation of the stock BSP 5.10 DTS to mainline: critical renames (`rockchip,suspend-voltage-selector` → `fcs,...`, `ttyFIQ0` → `ttyS2`, `video_phy0` → `dsi_dphy0`), display pipeline, I2C/PMIC/regulators, sound, storage, **USB port mapping**, SoC subsystems, and nodes not ported.

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

**Standard suspend** works on **`flip`**. **Deep suspend** (1013 + `vdd_logic` off) is **deferred** — patches `.testing-disabled`, Kconfig off; EmulationStation upstream blocker.

**[Full suspend guide →](drivers-and-dts/suspend-and-vdd-logic.md)**
