# Miyoo Flip board DTS, PMIC, DDR — recent evolution

Distro-agnostic summary of **what changed** on the Miyoo Flip port since early mainline bring-up. Full history: [Zetarancio/distribution commits on branch `flip`](https://github.com/Zetarancio/distribution/commits/flip/) (wiki README: tip **`47fb7252bc`** — *Miyoo Flip: drop the post-sleep rfkill quirk*, 2026-08-29; RK3566 **7.0.2**). Align DTS with **`miyoo355_fw_20250527`** stock where noted in [Stock firmware and findings](../stock-firmware-and-findings.md).

**Post-merge Miyoo / RK3566 work on `flip`:** RTL8733BU **001–006** ([39d9bb5](https://github.com/Zetarancio/distribution/commit/39d9bb5fe3), [6126f46](https://github.com/Zetarancio/distribution/commit/6126f46bdf), [ecccdef](https://github.com/Zetarancio/distribution/commit/ecccdef4b9), [6a7ac83](https://github.com/Zetarancio/distribution/commit/6a7ac83e87), [69d1b17](https://github.com/Zetarancio/distribution/commit/69d1b1714b)); POWER **`.suspend_late`** ([e728b28](https://github.com/Zetarancio/distribution/commit/e728b28834)); drop post-sleep rfkill quirk ([47fb725](https://github.com/Zetarancio/distribution/commit/47fb7252bc)); Bluetooth agent loop ([86de663](https://github.com/Zetarancio/distribution/commit/86de6632e5)); [Upper USB-C host](https://github.com/Zetarancio/distribution/commit/06fd5cd044); [7.1-port tree](https://github.com/Zetarancio/distribution/commit/3c149fbbf9); [Merge upstream/next](https://github.com/Zetarancio/distribution/commit/e59615f198) (RK3566 stays 7.0.2). Earlier: PipeWire **`pulse.idle.timeout = 60`** ([32fa5f3](https://github.com/Zetarancio/distribution/commit/32fa5f3308)); LED low-battery via shared **`led_flash`** ([f559f5e5](https://github.com/Zetarancio/distribution/commit/f559f5e5aa)); DFI PM at **`1010`**; **`CONFIG_RK3568_SUSPEND_MODE`** off while **1013** is `.testing-disabled` ([ca7bb4a9](https://github.com/Zetarancio/distribution/commit/ca7bb4a903)). [*DTS cleanup*](https://github.com/Zetarancio/distribution/commit/1f129e89df) (adc-keys, hall, **TCS4525** dropped — [I2C0](#i2c0-cpu-regulator)); [*prime rk817 Playback Mux*](https://github.com/Zetarancio/distribution/commit/79453c8d9b).

---

## Required DTS nodes for out-of-tree patches

Each out-of-tree kernel patch below needs specific DTS nodes to function. Patches live under `projects/ROCKNIX/devices/RK3566/patches/linux/` in the distribution tree.

**For detailed portability analysis** (what each patch reads from DTS, BSP vs ROCKNIX differences, minimum DTS for other RK3566/RK3568 boards), see [Patch portability and DTS requirements](patch-portability.md).

### Patch 1012 — DMC devfreq driver (DDR frequency scaling)

**See [Patch portability — 1012](patch-portability.md#patch-1012--rk3568-dmc-devfreq-driver) for detailed analysis.**

```dts
dmc: dmc {
    compatible = "rockchip,rk3568-dmc";
    devfreq-events = <&dfi>;
    center-supply = <&vdd_logic>;
    clocks = <&scmi_clk 3>;
    clock-names = "dmc_clk";
    operating-points-v2 = <&dmc_opp_table>;
    status = "okay";
};

dmc_opp_table: dmc-opp-table {
    compatible = "operating-points-v2";
    opp-324000000  { opp-hz = /bits/ 64 <324000000>;  opp-microvolt = <900000>; };
    opp-528000000  { opp-hz = /bits/ 64 <528000000>;  opp-microvolt = <900000>; };
    opp-780000000  { opp-hz = /bits/ 64 <780000000>;  opp-microvolt = <900000>; };
    opp-1056000000 { opp-hz = /bits/ 64 <1056000000>; opp-microvolt = <900000>; };
};
```

Also requires `&dfi { status = "okay"; }`.

### Patch 1010 — DFI suspend/resume (DDRMON reinit after deep sleep)

**See [Patch portability — 1010](patch-portability.md#patch-1010--devfreq-event-rockchip-dfi-pm-suspendresume).**

Same `&dfi { status = "okay"; }` node. The patch adds PM suspend/resume ops so DDRMON state is restored when the center power domain is off during deep sleep.

### Patch 1013 — rk3568-suspend (BL31 deep-sleep configuration)

**See [Patch portability — 1013](patch-portability.md#patch-1013--rk3568-suspend-mode-configuration-driver) for detailed analysis.**

```dts
#include <dt-bindings/suspend/rockchip-rk3568.h>

rk3568-suspend {
    compatible = "rk3568,pm-config";
    status = "okay";
    rockchip,sleep-debug-en = <0>;
    rockchip,sleep-mode-config = <
        (0
        | RKPM_SLP_CENTER_OFF
        | RKPM_SLP_ARMOFF_LOGOFF
        | RKPM_SLP_PMIC_LP
        | RKPM_SLP_HW_PLLS_OFF
        | RKPM_SLP_PMUALIVE_32K
        | RKPM_SLP_OSC_DIS
        | RKPM_SLP_32K_PVTM
        )
    >;
    rockchip,wakeup-config = <RKPM_GPIO_WKUP_EN>;
};
```

Regulators with `regulator-off-in-suspend` on vdd_logic, vdd_gpu, etc. are only safe when `RKPM_SLP_ARMOFF_LOGOFF` is set (BL31 saves/restores the logic domain). See [suspend and vdd_logic](suspend-and-vdd-logic.md).

### Patch 0007 — rk817_charger: clear SYS_CAN_SD (off-state drain)

**See [Patch portability — 0007](patch-portability.md#patch-0007--rk817_charger-clear-sys_can_sd-off-state-drain).**

**No DTS requirement.** Adds `regmap_write_bits(..., RK817_PMIC_CHRG_TERM, RK817_SYS_CAN_SD, 0)` in `rk817_battery_init()` so the PMIC does not keep **~8 mA** charger monitoring active when the system is off. Stock BSP always cleared this bit; mainline did not.

**Full analysis:** [Power-off battery drain investigation](../miyoo-flip-power-off-investigation.md). **Commit:** [560a99c](https://github.com/Zetarancio/distribution/commit/560a99cbe1d6b2a3760639ca0e8e730f101e9abb).

### Patch 0029 — rk8xx PMIC pinctrl switching (historical)

The BSP-style **0029** mfd patch (PMIC pinctrl / extra `rk808_power_off()` sequencing) was **removed** from the active Miyoo Flip / RK3566 patch set ([f9a59b0](https://github.com/Zetarancio/distribution/commit/f9a59b020de4e0109569e8f05d2760702b701e46)): it worsened off-state behavior in testing and is **not** the correct fix for the **~8 mA** leak (that is **patch 0007** above).

**Portability reference** (if you revive 0029 elsewhere): [Patch portability — 0029](patch-portability.md#patch-0029--mfd-rk8xx-bsp-style-pmic-pinctrl-switching).

**Current DTS direction:** Miyoo Flip aligns SLPPIN-related pinctrl with **upstream `pmic_pins`** where possible ([a482d5c](https://github.com/Zetarancio/distribution/commit/a482d5cfc4)) — see the live `rk3566-miyoo-flip.dts` in the distribution tree.

### Patch 0030 — rk8xx ON/OFF source logging

**See [Patch portability — 0030](patch-portability.md#patch-0030--mfd-rk8xx-log-on_sourceoff_source).**

No DTS changes needed (reads ON_SOURCE / OFF_SOURCE registers at probe for debugging power-on/off causes).

---

## RK817 / suspend / power-off

| Topic | Notes |
|-------|--------|
| **rk8xx suspend/resume** | Kernel patches align RK817 sleep/resume with BSP ordering (e.g. `SLPPIN_SLP_FUN`, resume path). DTS may use `pmic-reset` tied to sleep-pin GPIO for reliable resume. |
| **Full power-off** | Off-state **current** is **SYS_CAN_SD** until patch **0007** (BSP parity). Validate a real off with **`ON_SOURCE = 0x80`**; **`0x02` is a warm reboot** (was the 8733bu panic). Prefer `ON_SOURCE` over `OFF_SOURCE`. Multiboot preloader does not change drain. Details: [investigation](../miyoo-flip-power-off-investigation.md#re-verification-2026-08-27), [troubleshooting](../troubleshooting.md). |
| **Deep sleep** | **1013** + **`vdd_logic` off-in-suspend** — **deferred** on **`flip`** (`.testing-disabled`, Kconfig off) until EmulationStation upstream fix. Standard suspend still works. See [suspend and vdd_logic](suspend-and-vdd-logic.md). |
| **vcc9 / BOOST** | Document clearly that RK817 `vcc9` needs the correct supply (e.g. avoid fw_devlink cycles vs `dcdc_boost`). |

---

## DDR / DMC (devfreq)

| Topic | Notes |
|-------|--------|
| **Out-of-tree DMC** | Same V2 SIP + MCU/IRQ model as BSP; still the path for DDR frequency scaling on RK3566 mainline. |
| **Driver tuning** | Recent trees add stability tweaks (e.g. self-refresh idle, ratelimit on transitions, regulator handling) — review the DMC devfreq patch in your kernel tree if scaling misbehaves after suspend. |

---

## I2C0 CPU regulator

**Current `flip`:** **RK8600 @ 0x40** only — **TCS4525 @ 0x1c** removed in [*Miyoo Flip DTS: cleanup and fixes*](https://github.com/Zetarancio/distribution/commit/1f129e89df) after **Miyoo officially confirmed** to this project that there is **no second CPU-regulator hardware variant** (only RK8600 is populated on retail units).

**2025 stock** (`miyoo355_fw_20250527`) still lists **both** I2C addresses in the BSP DTS; that is **not** proof of two production SKUs. Earlier port commits briefly enabled both nodes ([b7525be](https://github.com/Zetarancio/distribution/commit/b7525bed1d9d262d621d66f1108c859399db7777), [6882112](https://github.com/Zetarancio/distribution/commit/68821122aa0476ed453cdc1b073922b0805d0214)) before this trim.

---

## SD / eMMC PHY

| Topic | Notes |
|-------|--------|
| **Shared vqmmc** | Both MicroSD slots share a **single `vqmmc` rail** (vccio_sd). They must operate at the same I/O voltage. Tested: **two 1.8 V cards** (works). Untested but plausible: **two 3.3 V cards**. Also works: **one single 3.3 V card**. **You cannot mix a 1.8 V and a 3.3 V card.** |
| **SDR50 on slot 2** | Removed from second slot — shared vqmmc limits stable UHS negotiation when both slots are populated. Slot 0 (boot) keeps SDR12/SDR25/SDR50/SDR104. |
| **Karlman MMC** | Not useful for this board. The Karlman warm-reboot MMC patch was tried and removed — the actual constraint is the shared vqmmc rail, not a warm-reboot bug. |
| **CPU rail / I2C0** | See [I2C0 CPU regulator](#i2c0-cpu-regulator) — **RK8600** only on current `flip`. |

---

## Display / WiFi (brief)

| Topic | Notes |
|-------|--------|
| **DSI / panel** | Module **LMY35120-20p**; DSI facts from stock DTS — see [Display — sure vs presumed](display.md#module-name-vs-what-is-proven). Init/flags aligned with **`miyoo355_fw_20250527`** where they diverged from 2024 dumps. |
| **RTL8733BU** | GPIO power rail (`rtl8733bu-power`) plus the 7.1-port driver tree and local patches **001–006**. Runtime `modprobe` still sets IPS/LPS/USB autosuspend. See [drivers](drivers.md), [WiFi/BT power-off](wifi-bt-power-off.md). |

---

## Bootloader

| Topic | Notes |
|-------|--------|
| **BL31 / OP-TEE** | U-Boot FIT may track newer rkbin BL32; some trees adjust reserved-memory for OP-TEE. Always match **DDR init blob ↔ BL31** version expectations (see [SPI and boot chain](../stock-firmware-and-findings/spi-and-boot-chain.md)). |

---

## Joypad / input

The Miyoo Flip uses a serial-based analog stick and GPIO buttons, not a standard ADC joypad.

| Topic | Notes |
|-------|--------|
| **Driver** | `rocknix-singleadc-joypad` with `rocknix,use-miyoo-serial-joypad` — UART1 Miyoo serial protocol. Driver-source patches **0002** / **0003** (DTS deadzone + sysfs cal). The old kernel **0001** gpiolib revert is **gone** (upstream joypad `1dd1115` does not need it). **Save Miyoo Autocal** tools module persists calibration. |
| **GPIO buttons** | 17 GPIO switches: dpad (up/down/left/right), A/B/X/Y, select, start, mode, L1/R1, L2/R2, thumb L/R. |
| **Debounce** | Volume keys: 10 ms (GPIO). Lid: separate `gpio_keys_hall` node ([1f129e8](https://github.com/Zetarancio/distribution/commit/1f129e89df)). |
| **Rumble** | PWM5 @ 10 MHz period. |
| **ADC keys** | **Node removed** — SARADC ch0 caused phantom volume-down / recovery ([1f129e8](https://github.com/Zetarancio/distribution/commit/1f129e89df)). Volume on GPIO3_PA7 / GPIO3_PB0. |
| **Hall sensor** | `gpio_keys_hall` on GPIO0_PC6; **wake on lid open only** (closing lid while suspended does not wake). |

---

## USB

Two USB-C ports, mapped as follows. Earlier trees treated `usb2phy1_otg` / `usb_host0_ehci` as unused and disabled them to dodge a suspend hang; that was the wrong node, and it is what broke host. Current mapping ([06fd5cd0](https://github.com/Zetarancio/distribution/commit/06fd5cd044)):

| Connector / function | Controller | PHY | VBUS / notes |
|----------------------|------------|-----|----------------|
| **Upper USB-C host** | `usb_host0_ehci` `fd800000` | `usb2phy1_otg` | `phy-supply = <&vcc5v0_host>` (GPIO4_PC5). Plug-and-play host. A high-inrush hub already inserted at power-on can brown out the board on battery. |
| **Lower USB-C** charge / gadget | `usb_host0_xhci` `fcc00000` | `usb2phy0_otg` | `dr_mode = "otg"`, `extcon = <&usb2phy0>`. No VBUS supply on this PHY. |
| **WiFi RTL8733BU** | `usb_host1_ehci` `fd880000` | `usb2phy1_host` | Analog supply `vcc_3v3` (stock used 5V). Enable GPIO is GPIO0_PA0 via `rtl8733bu_power`. |
| No external connector | `usb_host1_xhci` `fd000000` | `usb2phy0_host` | USB2-only (`maximum-speed = "high-speed"`). Kept off the WiFi PHY. |
| Disabled | `usb_host0_ohci` `fd840000`, `usb_host1_ohci` `fd8c0000` | — | USB 1.1 companions; not needed. |
| Disabled | `combphy1` / `combphy2` | — | No USB3 / SATA / PCIe on this board. |

`otg_switch` on the RK817 is that PMIC's OTG 5V output. It is **not** the upper USB-C VBUS rail (`vcc5v0_host` is).

---

## Other DTS details

| Topic | Notes |
|-------|--------|
| **combphy1/2** | **Disabled** — no USB3/SATA/PCIe on this board. Saves PD_PIPE power domain. |
| **i2c3 / touch** | **Disabled** — Hynitron CST3xx identified at 0x3d, but no touchscreen is present. |
| **CPU clock-latency** | `clock-latency-ns = 300000000` on the 408 MHz CPU OPP reduces I2C storm to the PMIC during rapid frequency transitions. |
| **LEDs** | Green power + red status/charging via `010-led_control` / `bin/ledcontrol`. Low-battery blink uses shared **`led_flash`** ([f559f5e5](https://github.com/Zetarancio/distribution/commit/f559f5e5aa)); `DEVICE_BATTERY_LED_STATUS="false"`. |
| **PipeWire** | `99-rk3566-power.conf`: **`pulse.idle.timeout = 60`** (was 5s; fixes ~1.7s sink wake after idle) — [32fa5f3](https://github.com/Zetarancio/distribution/commit/32fa5f3308). |
| **SFC** | **Disabled** in ROCKNIX DTS (boots from SD). BSP SPI NAND layout preserved in DTS comments as reference. |

---

## Final state after reversions (important)

Several ideas were tested and later reverted. Use the **final validated state**:

| Area | Final state |
|------|-------------|
| **RK817 power-off / off-state drain** | **~8 mA “off” drain** is fixed by kernel **patch 0007** (clear **SYS_CAN_SD** in `rk817_charger`). See [investigation](../miyoo-flip-power-off-investigation.md) and [troubleshooting](../troubleshooting.md). DTS for `system-power-controller` and SLPPIN pinctrl follows the live `flip` tree ([560a99c](https://github.com/Zetarancio/distribution/commit/560a99cbe1d6b2a3760639ca0e8e730f101e9abb), [a482d5c](https://github.com/Zetarancio/distribution/commit/a482d5cfc4)). Omitting `system-power-controller` was **not** the real fix for the mA-level leak. |
| **Battery OCV** | OCV table must be **descending**. Keep the corrected 2025-style battery curve/settings. Hardware pack: Miyoo **755060**, **3.7 V** nominal, **3000 mAh**, **11.1 Wh** (see [Hardware overview](../boot-and-flash.md)). |
| **WiFi (RTL8733BU)** | Driver tree is [Awesome-Embedded-Learning-Studio/rtl8733bu-linux-driver](https://github.com/Awesome-Embedded-Learning-Studio/rtl8733bu-linux-driver) pinned at `c46aa25e`. **Local patches 001–006** (shutdown hook, suspend bound, two cfg80211 BSS double-release fixes, drop concurrent mode, restore SAE/WPA3). GPIO cut-off is **RTL8733BU-POWER** (`.suspend_late` / `.resume`). Runtime: `rtw_ips_mode=0 rtw_power_mgnt=1 rtw_lps_level=1 rtw_enusbss=0`. |
| **SD shared vqmmc** | Both slots at same voltage (two 1.8 V tested, two 3.3 V plausible, one 3.3 V works); **cannot mix 1.8 V and 3.3 V**. SDR50 removed from second slot (shared vqmmc limits stable UHS on slot 2). |
| **DMC / suspend** | Out-of-tree **DMC** + **DFI 1010** PM patch. **1013** rk3568-suspend **`.testing-disabled`**; `CONFIG_RK3568_SUSPEND_MODE` **not set** ([ca7bb4a9](https://github.com/Zetarancio/distribution/commit/ca7bb4a903)) until EmulationStation upstream fix — [suspend](suspend-and-vdd-logic.md). |
| **VDD_CPU (I2C0)** | **RK8600 @ 0x40** only; **TCS4525** removed per **Miyoo official confirmation** (no second regulator SKU) ([1f129e89df](https://github.com/Zetarancio/distribution/commit/1f129e89df)). |
| **Audio** | `099-audio_prime` sets rk817 **Playback Mux** at boot and after sink resume; PipeWire idle **60s** ([79453c8](https://github.com/Zetarancio/distribution/commit/79453c8d9b), [32fa5f3](https://github.com/Zetarancio/distribution/commit/32fa5f3308)). |
| **USB** | Upper USB-C **host** enabled (`usb2phy1_otg` + `usb_host0_ehci` + `vcc5v0_host`). Do not re-disable as unused. [USB](#usb). |

Reference stream: [flip branch commits](https://github.com/Zetarancio/distribution/commits/flip/).

---

## Fork vs upstream (`flip` maintenance)

After each merge from `upstream/next`, re-check these **Miyoo Flip invariants** (none of the fork’s suspend/DMC/RK817 patches are in upstream `next` as of merge **`e59615f198`**):

| Must keep | Why |
|-----------|-----|
| `rk3566-miyoo-flip` in `config.xml` | Device profile |
| `ADDITIONAL_DRIVERS` … `RTL8733BU RTL8733BU-POWER` | WiFi/BT stack. Keep patches **001–006**; POWER is the GPIO cut-off (including suspend) |
| Upper USB-C host: `usb2phy1_otg` + `usb_host0_ehci` + `phy-supply = <&vcc5v0_host>` | Do not re-disable as “unused” |
| `CONFIG_ARM_RK3568_DMC_DEVFREQ=y`; patches **0007**, **1010**, **1012a/b** | DMC + off-state drain |
| **1013** `.testing-disabled`; `CONFIG_RK3568_SUSPEND_MODE` **off** | Deep suspend deferred (ES) |
| `pulse.idle.timeout = 60` | RK3566 PipeWire power conf |
| Joypad driver patches **0002** / **0003** (no kernel `0001`) | Stock `1dd1115` does not need the gpiolib revert |
| Miyoo quirks: `099-audio_prime`, `060-btusb_power`, `sleep.d/001-btusb` | Audio + BT suspend |

RK3566 does **not** use InputPlumber (`ROCKNIX_JOYPAD=yes`). Re-verify lid/power suspend after upstream changes to **`rocknix-fake-suspend`**.
