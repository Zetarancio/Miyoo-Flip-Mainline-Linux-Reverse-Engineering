# Miyoo Flip board DTS, PMIC, DDR — recent evolution

Distro-agnostic summary of **what changed** on the Miyoo Flip port since early mainline bring-up. Full history: [Zetarancio/distribution commits on branch `flip`](https://github.com/Zetarancio/distribution/commits/flip/). Align mainline DTS and kernel patches with **miyoo355_fw_20250509213001 stock firmware** where noted in [Stock firmware and findings](../stock-firmware-and-findings.md).

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

### Patch 1011 — DFI suspend/resume (DDRMON reinit after deep sleep)

**See [Patch portability — 1011](patch-portability.md#patch-1011--devfreq-event-rockchip-dfi-pm-suspendresume).**

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

### Patch 0029 — rk8xx PMIC pinctrl switching (RK817 sleep/resume/power-off)

DTS requires on the RK817 PMIC node:

Notes
```dts
pinctrl-names = "default", "pmic-sleep", "pmic-power-off", "pmic-reset";
pinctrl-0 = <&pmic_int>, <&i2s1m0_mclk>;
pinctrl-1 = <&soc_slppin_slp>;
pinctrl-2 = <&soc_slppin_gpio>;
pinctrl-3 = <&soc_slppin_gpio>;
/* system-power-controller; */
```
- `pinctrl-names` will be updated to match mainline names. Check the patch for future infos.
- `pinctrl-0` must **not** include any SLPPIN group. If SLPPIN_DN_FUN is retained from a prior shutdown, driving GPIO0_PA2 high at probe triggers an immediate power-off before the driver can clear it.
- `pmic-sleep` (`pinctrl-1`): muxes the pin to PMU_SLEEP so the PMIC applies `regulator-state-mem` during suspend.
- `pmic-power-off` / `pmic-reset` (`pinctrl-2`/`pinctrl-3`): mux to GPIO so BL31 can drive the pin for shutdown/resume.
- `system-power-controller` must be **commented out** (DEV_OFF races with PSCI SYSTEM_OFF).

### Patch 0030 — rk8xx ON/OFF source logging

**See [Patch portability — 0030](patch-portability.md#patch-0030--mfd-rk8xx-log-on_sourceoff_source).**

No DTS changes needed (reads ON_SOURCE / OFF_SOURCE registers at probe for debugging power-on/off causes).

---

## RK817 / suspend / power-off

| Topic | Notes |
|-------|--------|
| **rk8xx suspend/resume** | Kernel patches align RK817 sleep/resume with BSP ordering (e.g. `SLPPIN_SLP_FUN`, resume path). DTS may use `pmic-reset` tied to sleep-pin GPIO for reliable resume. |
| **Full power-off** | Do **not** use `system-power-controller` on RK817: mainline `DEV_OFF` can race PSCI `SYSTEM_OFF`, leaving the PMIC partly on and draining the battery. Without it, shutdown uses `rk8xx_shutdown()` + BL31. See [troubleshooting](../troubleshooting.md). |
| **Deep sleep** | Still requires **rk3568-suspend** (BL31 deep-sleep flags) + sensible `vdd_logic` / regulator-off-in-suspend where used. See [suspend and vdd_logic](suspend-and-vdd-logic.md). |
| **vcc9 / BOOST** | Document clearly that RK817 `vcc9` needs the correct supply (e.g. avoid fw_devlink cycles vs `dcdc_boost`). |

---

## DDR / DMC (devfreq)

| Topic | Notes |
|-------|--------|
| **Out-of-tree DMC** | Same V2 SIP + MCU/IRQ model as BSP; still the path for DDR frequency scaling on RK3566 mainline. |
| **Driver tuning** | Recent trees add stability tweaks (e.g. self-refresh idle, ratelimit on transitions, regulator handling) — review the DMC devfreq patch in your kernel tree if scaling misbehaves after suspend. |

---

## I2C0 CPU regulator (TCS4525 and RK8600)

**miyoo355_fw_20250509213001** stock DTS enables **both** a **TCS4525 @ 0x1c** and an **RK8600 @ 0x40** as possible CPU rails. That implies **two board revisions** may exist in the wild (one populated part per address), but **this is not proven** on hardware—only the **firmware/DTS** documents both.

The Miyoo Flip mainline DTS was aligned to that model:

- **[b7525be](https://github.com/Zetarancio/distribution/commit/b7525bed1d9d262d621d66f1108c859399db7777)** — Comments and **full TCS4525 node** from stock (with `fcs,suspend-voltage-selector`, suspend state, etc.); documents two revisions vs 2025 firmware; clarifies USB host 5V and SD power pinctrl vs stock 2025.
- **[6882112](https://github.com/Zetarancio/distribution/commit/68821122aa0476ed453cdc1b073922b0805d0214)** — **Both** `tcs4525@1c` and `rk8600@40` use `status = "okay"` (no longer disabling TCS4525 to silence probe). **TCS4525 on real hardware with only RK8600 is still untested** in that configuration; the expectation is the same as stock: **only the populated chip probes successfully**. The other address gets a normal **driver probe failure** (`-ENXIO` / chip ID) and is **ignored**—**the system boots and runs** using the regulator that is actually present.

---

## SD / eMMC PHY

| Topic | Notes |
|-------|--------|
| **Shared vqmmc** | Both MicroSD slots share a **single `vqmmc` rail** (vccio_sd). They must operate at the same I/O voltage. Tested: **two 1.8 V cards** (works). Untested but plausible: **two 3.3 V cards**. Also works: **one single 3.3 V card**. **You cannot mix a 1.8 V and a 3.3 V card.** |
| **SDR50 on slot 2** | Removed from second slot — shared vqmmc limits stable UHS negotiation when both slots are populated. Slot 0 (boot) keeps SDR12/SDR25/SDR50/SDR104. |
| **Karlman MMC** | Not useful for this board. The Karlman warm-reboot MMC patch was tried and removed — the actual constraint is the shared vqmmc rail, not a warm-reboot bug. |
| **CPU rail / I2C0** | See [I2C0 CPU regulator (TCS4525 and RK8600)](#i2c0-cpu-regulator-tcs4525-and-rk8600) — dual nodes enabled like stock; two revisions **possible**, **not proven**. |

---

## Display / WiFi (brief)

| Topic | Notes |
|-------|--------|
| **DSI / panel** | Module **LMY35120-20p**; DSI facts from stock DTS — see [Display — sure vs presumed](display.md#module-name-vs-what-is-proven). Init/flags aligned with **miyoo355_fw_20250509213001** where they diverged from 2024 dumps. |
| **RTL8733BU** | GPIO power rail, disable USB autosuspend when the chip is power-gated, and several driver patches for suspend/resume and power. Optional **rtl8733bu-power**-style driver for full cut-off. See [drivers](drivers.md), [WiFi/BT power-off](wifi-bt-power-off.md). |

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
| **Driver** | `rocknix-singleadc-joypad` with `rocknix,use-miyoo-serial-joypad` — analog sticks are read via **UART1** (Miyoo serial protocol), not ADC channels. |
| **Analog sticks** | Deadzone 4914, fuzz 32, flat 32, threshold 128; L/R axis tuning 90. Sysfs calibration available at runtime; joystick cal saved/restored on boot via quirks/modules. Some of these feature requires dedicated patches avalaible in rocknix branch. |
| **GPIO buttons** | 17 GPIO switches: dpad (up/down/left/right), A/B/X/Y, select, start, mode, L1/R1, L2/R2, thumb L/R. |
| **Debounce** | Volume keys: 10 ms (matches stock gpio-keys-polled). Lid (hall sensor): 1500 ms to avoid double triggers ([eda5e75](https://github.com/Zetarancio/distribution/commit/eda5e752f89d0b8cc6421fcbd84db7bddc01e466)). |
| **Rumble** | PWM5 @ 10 MHz period. |
| **ADC keys** | **Disabled** in DTS — floating ADC ch0 causes phantom `KEY_VOLUMEDOWN` and triggers stock recovery entry. Volume up/down are on GPIO (GPIO3_PA7 / GPIO3_PB0). |
| **Hall sensor** | `SW_LID` on GPIO0_PC6, wakeup-source (lid open/close detection). |

---

## Other DTS details

| Topic | Notes |
|-------|--------|
| **combphy1/2** | **Disabled** — no USB3/SATA/PCIe on this board. Saves PD_PIPE power domain. |
| **i2c3 / touch** | **Disabled** — Hynitron CST3xx identified at 0x3d, but no touchscreen is present. |
| **CPU clock-latency** | `clock-latency-ns = 300000000` on the 408 MHz CPU OPP reduces I2C storm to the PMIC during rapid frequency transitions. |
| **LEDs** | Power green (GPIO0_PB4, no default trigger). Charger red (GPIO0_PC2, `battery-charging` trigger, `retain-state-suspended`). |
| **USB host speed** | `usb_host1_xhci` forced to `maximum-speed = "high-speed"` — no SuperSpeed for the RTL8733BU WiFi/BT module. |
| **SFC** | **Disabled** in ROCKNIX DTS (boots from SD). BSP SPI NAND layout preserved in DTS comments as reference. |

---

## Final state after reversions (important)

Several ideas were tested and later reverted. Use the **final validated state**:

| Area | Final state |
|------|-------------|
| **RK817 power-off** | Keep `system-power-controller` **disabled** on Miyoo Flip RK817 to avoid DEV_OFF vs PSCI race and battery drain while off to match stock firmware. Still under testing as **miyoo355_fw_20250509213001 stock firmware** actually keeps it enabled. |
| **Battery OCV** | OCV table must be **descending**. Keep the corrected 2025-style battery curve/settings. Hardware pack: Miyoo **755060**, **3.7 V** nominal, **3000 mAh**, **11.1 Wh** (see [Hardware overview](../boot-and-flash.md)). |
| **WiFi (RTL8733BU)** | For GPIO-controlled power, disable USB autosuspend and keep suspend/resume hardening. LPS/LCLK tuning was iterated; use latest stable combination, not early intermediate commits. |
| **SD shared vqmmc** | Both slots at same voltage (two 1.8 V tested, two 3.3 V plausible, one 3.3 V works); **cannot mix 1.8 V and 3.3 V**. SDR50 removed from second slot (shared vqmmc limits stable UHS on slot 2). |
| **DMC / suspend** | Keep the out-of-tree DMC + rk3568-suspend path, plus latest rk8xx suspend/resume ordering updates. |
| **VDD_CPU (I2C0)** | **Both** `tcs4525@1c` and `rk8600@40` **enabled** (`okay`), matching 2025 stock ([6882112](https://github.com/Zetarancio/distribution/commit/68821122aa0476ed453cdc1b073922b0805d0214)). Two board variants are **firmware-inferred only**; absent chip = probe fail, **boot OK**. |

Reference stream: [flip branch commits](https://github.com/Zetarancio/distribution/commits/flip/).
