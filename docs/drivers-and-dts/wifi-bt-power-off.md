# WiFi/BT Combo Chip Power-Off (RTL8733BU)

WiFi works with the 8733bu driver (out-of-tree). This page describes an **optional** separate driver that shuts down the RTL8733BU combo at the **GPIO level** when both WiFi and Bluetooth are off, so the chip is fully powered off and draws no standby current.

## Why Full Poweroff Requires a Separate Driver

On boards like the Miyoo Flip, the WiFi/BT combo chip (RTL8733BU) is powered by a single **enable GPIO**: when the GPIO is driven active, the chip is powered; when it is driven inactive, the chip is fully off. The mainline **8733bu** (or equivalent) driver handles USB enumeration, WiFi, and Bluetooth at the software level but **does not control this power-enable GPIO**. It only talks to the device over USB and implements rfkill by blocking radio at the software layer. So when the user “turns off” WiFi or Bluetooth in settings:

- The kernel rfkill subsystem marks the corresponding radio as blocked.
- The 8733bu driver may stop using the radio.
- **The hardware remains powered** — the enable GPIO is never toggled, so the chip stays on and draws standby current.

To actually **power off** the combo (and save maximum battery when both WiFi and BT are off), a **separate driver** is needed that:

1. **Owns the power-enable GPIO** (the same one that may be described as `vcc_wifi` or similar in the DTS).
2. **Integrates with rfkill** so that WiFi and BT “off” in userspace is reflected in the kernel’s rfkill state.
3. **Applies a clear policy**: e.g. power on if either WiFi or BT is unblocked; power off only when **both** are blocked.

Without a driver that does this (e.g. **RTL8733BU-POWER** or a similar power-control driver), the WiFi/BT combo **cannot be fully powered off**; it can only be “soft” disabled via rfkill while the chip remains powered.

---

## Typical Power-Driver Logic

A typical implementation (e.g. `rtl8733bu_power.c` or equivalent) works as follows:

1. **Platform driver** binds to a DTS node (e.g. `compatible = "rockchip,rtl8733bu-power"`) that has a single GPIO, e.g. `enable` (active-high or active-low as per hardware).

2. **Two rfkill devices** are registered:
   - One for **RFKILL_TYPE_WLAN** (WiFi).
   - One for **RFKILL_TYPE_BLUETOOTH** (BT).  
   Userspace (wifictl, bluetooth service, settings UI) blocks/unblocks these; the kernel calls the driver’s `set_block` callbacks.

3. **State tracking**: The driver keeps two booleans, e.g. `wlan_blocked` and `bt_blocked`. When either rfkill state changes, the driver updates the corresponding flag and then decides:
   - **Power ON**: if at least one of WiFi or BT is **unblocked** (user wants it available).
   - **Power OFF**: only when **both** are **blocked** (user has turned off both WiFi and BT).

4. **GPIO output**: The driver drives the enable GPIO high (power on) or low (power off) according to that policy. The GPIO is often active-low in hardware (e.g. “enable” = assert = power on), which is handled by the gpiod API.

5. **Load order**: The power driver should probe and take control of the GPIO **before** or independently of the 8733bu USB driver. When both WiFi and BT are blocked, the power driver cuts the GPIO; the USB device disappears and the 8733bu driver unbinds. When the user enables WiFi or BT again, the power driver turns the GPIO back on, the USB device reappears, and the 8733bu driver binds again.

So: **without a dedicated power driver that controls the enable GPIO**, the kernel never toggles the combo’s power pin, and the WiFi/BT combo cannot be powered off for maximum battery savings. With it, turning off both WiFi and BT in settings results in full hardware power-off of the combo chip.
