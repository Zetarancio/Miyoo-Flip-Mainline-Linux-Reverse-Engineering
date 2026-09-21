# Suspend and vdd_logic

Standard suspend and deep suspend are different mechanisms on RK3566/RK3568. DDR frequency scaling is a third, independent mechanism.

1. **Standard suspend** is ordinary Linux suspend-to-RAM (`echo mem > /sys/power/state`). It does not need the rk3568-suspend driver.
2. **Deep suspend** is a BL31 configuration. An out-of-tree driver sends `SIP_SUSPEND_MODE` (SMC `0x82000003`) so BL31 uses **`ARMOFF_LOGOFF`** and saves the logic domain. Sections [3](#3-how-it-works) and [5](#5-sip-protocol-details) describe that path.
3. **`vdd_logic` off-in-suspend is only safe in that mode.** Without `ARMOFF_LOGOFF`, resume hangs because BL31 has not saved the logic domain. See [vdd_logic](#vdd_logic-regulator).
4. **DMC devfreq** uses a different SIP (`SIP_DRAM_CONFIG`, `0x82000008`). It is not required for deep suspend, and deep suspend is not required for DMC. See [§9](#9-relationship-to-ddr-frequency-scaling).

The behavior below was proven on hardware and on the archived Miyoo Flip ROCKNIX fork. **Zlyme has not been recorded here as shipping deep suspend.** The fork’s last shipping choice (deep suspend left off) is [at the end of this page](#historical-implementation--archived-miyoo-flip-rocknix-fork).

---

## Overview

An out-of-tree kernel driver named **rk3568-suspend** (formerly referred to as rk356x in some docs) configures BL31 (ARM Trusted Firmware) **deep-sleep** flags via SIP SMC calls. This enables the deepest suspend states on RK3568/RK3566 SoCs, matching the behavior of stock BSP firmware.

**The driver is required for `vdd_logic` off-in-suspend to work.** It tells BL31 to use `ARMOFF_LOGOFF` so the logic domain is saved and restored across suspend. Without it, turning off vdd_logic in suspend causes the system to hang on resume. With the driver and vdd_logic configured with `regulator-off-in-suspend`, the device achieves **deep sleep**: the logic domain (and optionally center domain, oscillator, PMIC low-power mode) is powered down, greatly reducing sleep current.

The driver and Kconfig use the **rk3568** namespace (`rk3568-suspend` node, `CONFIG_RK3568_SUSPEND_MODE`) to avoid collisions with BSP `rockchip_pm_config` if that code is ever merged upstream.

---

## 1. Problem Statement

Mainline kernel on RK3568/RK3566 does not include Rockchip's BSP `rockchip_pm_config` driver. Without a substitute:

- BL31 uses compiled-in default sleep flags, which usually do **not** enable the deepest power modes (oscillator off, PMIC low-power, center power domain off, etc.).
- Turning off **vdd_logic** during suspend without first telling BL31 to expect `ARMOFF_LOGOFF` mode causes the system to hang on resume — BL31 does not save/restore the logic domain state unless it has been configured for that mode.

So both **deep sleep** and **vdd_logic off in suspend** depend on a driver that programs BL31 via SIP. The rk3568-suspend driver is for **deep sleep**, not for generic “sleep” (e.g. idle or light suspend).

---

## 2. Implementation

### Source (archived ROCKNIX fork)

The rk3568-suspend driver sources and DTS references live in the archived fork [Zetarancio/distribution](https://github.com/Zetarancio/distribution) branch **`flip`**. Shipping state: [historical implementation](#historical-implementation--archived-miyoo-flip-rocknix-fork).

### Patch (distribution-agnostic)

The driver is added by a kernel patch that creates:

- `drivers/soc/rockchip/rk3568_suspend_config.c` — platform driver that reads DTS and sends SMC calls.
- `include/dt-bindings/suspend/rockchip-rk3568.h` — `RKPM_SLP_*` and `RKPM_*_WKUP_EN` flag definitions.

Typical path in a source tree: e.g. `patches/linux/1013-soc-rockchip-add-suspend-mode-configuration-driver.patch` (or equivalent, depending on the distribution).

### Kconfig

```
config RK3568_SUSPEND_MODE
    bool "RK3568 suspend mode configuration"
    depends on HAVE_ARM_SMCCC && SUSPEND && ARCH_ROCKCHIP
```

Enabling it means `CONFIG_RK3568_SUSPEND_MODE=y`. On the archived `flip` tree it is **not set** — see [historical implementation](#historical-implementation--archived-miyoo-flip-rocknix-fork). Everything from here on describes how the driver works and what it achieved in testing.

### Naming

The driver uses the **rk3568** namespace (`rk3568-suspend` node, `rk3568,pm-config` compatible, `rk3568-suspend-config` as driver name) so it does not conflict with BSP `rockchip-suspend` / `rockchip,pm-rk3568`.

---

## 3. How It Works

### Boot Sequence

1. Driver probes via `late_initcall_sync` (compatible = `rk3568,pm-config`).
2. Reads `rockchip,sleep-mode-config` and `rockchip,wakeup-config` from the `rk3568-suspend` DTS node.
3. Sends config to BL31 via `SIP_SUSPEND_MODE` (SMC 0x82000003).
4. BL31 stores the flags for use during subsequent suspend cycles.

### Suspend Sequence

1. Kernel calls `rk3568_suspend_prepare()` (PM `.prepare` callback).
2. Driver re-sends sleep config to BL31 (ensures flags are current).
3. Kernel proceeds with normal PSCI suspend.
4. BL31 uses the configured flags to enter **deep sleep**:
   - Powers off ARM cores
   - Powers off logic domain (`ARMOFF_LOGOFF`)
   - Powers off center power domain
   - Puts PMIC into low-power mode
   - Disables oscillator, switches to 32K PVTM clock

### Resume Sequence

1. GPIO (or other configured) wakeup triggers.
2. BL31 restores logic domain state (because `ARMOFF_LOGOFF` was set).
3. ARM cores and OP-TEE secondary CPUs reinitialize.
4. Kernel resumes normally.

---

## 4. DTS Configuration

### rk3568-suspend Node

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

**sleep-mode-config = 0x5ec** (example) matches typical stock deep-sleep flags:

| Flag | Bit | Effect |
|------|-----|--------|
| `RKPM_SLP_CENTER_OFF` | 2 | Power off center power domain |
| `RKPM_SLP_ARMOFF_LOGOFF` | 3 | Power off ARM + logic domain |
| `RKPM_SLP_PMIC_LP` | 5 | PMIC enters low-power mode |
| `RKPM_SLP_HW_PLLS_OFF` | 6 | Disable hardware PLLs |
| `RKPM_SLP_PMUALIVE_32K` | 7 | PMU alive on 32K clock |
| `RKPM_SLP_OSC_DIS` | 8 | Disable main oscillator |
| `RKPM_SLP_32K_PVTM` | 10 | Use 32K PVTM clock source |

### vdd_logic Regulator

```dts
vdd_logic: DCDC_REG1 {
    /* ... */
    regulator-state-mem {
        regulator-off-in-suspend;
    };
};
```

**vdd_logic and the suspend driver**

- **vdd_logic** supplies the SoC logic domain. Turning it off in suspend (`regulator-off-in-suspend`) is only safe if BL31 has been told to use `ARMOFF_LOGOFF` and will save/restore that domain.
- The **rk3568-suspend** driver is what sends that configuration to BL31. So:
  - **Without** the rk3568-suspend driver: do **not** use `regulator-off-in-suspend` on vdd_logic, or the device will hang on resume.
  - **With** the driver and the correct `rockchip,sleep-mode-config` (including `RKPM_SLP_ARMOFF_LOGOFF`), vdd_logic can be turned off in suspend and the device achieves much lower sleep power (deep sleep).

---

## 5. SIP Protocol Details

| SMC Function ID | Value |
|-----------------|-------|
| `SIP_SUSPEND_MODE` | 0x82000003 |

| Sub-command | Value | Purpose |
|-------------|-------|---------|
| `SUSPEND_MODE_CONFIG` | 0x01 | Set sleep mode flags |
| `WKUP_SOURCE_CONFIG` | 0x02 | Set wakeup source flags |
| `SUSPEND_DEBUG_ENABLE` | 0x05 | Enable/disable BL31 sleep debug output |

---

## 6. Confirmed Working — Boot Log Evidence

**Historical capture**, from a build where the 1013 patches and `vdd_logic` off-in-suspend were enabled. The archived `flip` tree does not produce these lines.

```
rk3568-suspend-config rk3568-suspend: sleep-mode-config=0x5ec wakeup-config=0x10 (smc ret=0)
```

Driver probes and BL31 accepts the configuration (`smc ret=0`).

### Suspend/Resume Cycle

With vdd_logic off-in-suspend and the rk3568-suspend driver:

- Suspend: `PM: suspend entry (deep)` then BL31 sequence (e.g. `abcdeghijsramwfi`).
- Resume: BL31 resume sequence (e.g. `ABCDEFGHIJKLM`), OP-TEE and cores come up, then `PM: suspend exit`.
- USB and other buses may re-enumerate after deep sleep; that is expected.

---

## 7. Debugging Tips

### BL31 sleep debug

Set `rockchip,sleep-debug-en = <1>` in the `rk3568-suspend` node. BL31 will print detailed power-domain and register state over serial during suspend/resume.

### Serial console

Use a serial port (e.g. uart2) and a kernel command line that keeps the console available (e.g. `no_console_suspend` and, if used, `systemd.debug_shell=ttyS2`).

### If the device does not wake

1. Confirm driver load: `dmesg | grep rk3568-suspend`
2. Check SMC return code is 0 in the probe message.
3. To test without logic power-off: temporarily use `regulator-on-in-suspend` or `regulator-suspend-microvolt` for vdd_logic instead of `regulator-off-in-suspend`.
4. Verify wakeup source: `RKPM_GPIO_WKUP_EN` (or other flags) must match the actual wakeup source (e.g. GPIO) used by the board.

---

## 8. Kconfig Dependency

The Kconfig option must depend on `HAVE_ARM_SMCCC` (not `ARM_SMCCC`). On arm64, `HAVE_ARM_SMCCC` is the symbol that indicates SMCCC support. Using a non-existent or wrong symbol can cause `make olddefconfig` to drop the option.

---

## 9. Relationship to DDR Frequency Scaling

The suspend driver and the DDR DMC devfreq driver (rk3568-dmc) are independent but complementary. The archived ROCKNIX fork carried both ([Zetarancio/distribution](https://github.com/Zetarancio/distribution) `flip`, stamp `d249b09bd9`). A later OS does not have to keep that patch layout.

| Feature | DMC devfreq | rk3568-suspend |
|---------|-------------|-----------------|
| Purpose | DDR frequency scaling at runtime | **Deep sleep** configuration |
| SIP function | `SIP_DRAM_CONFIG` (0x82000008) | `SIP_SUSPEND_MODE` (0x82000003) |
| Active when | Normal operation | Suspend/resume |
| Power saving | Lower DDR power at idle | Lower total SoC power in sleep |
| vdd_logic | May use vdd_logic as center-supply | Required for vdd_logic off-in-suspend |

Together they give both runtime power savings (DDR scaling) and much better suspend (logic/center/oscillator off with vdd_logic off).

---

## Historical implementation — archived Miyoo Flip ROCKNIX fork

Source tree: **[Zetarancio/distribution](https://github.com/Zetarancio/distribution)** branch **`flip`**, wiki stamp **`d249b09bd9`** (2026-09-02). This is not Zlyme, and the fork is not maintained. Summary: [ROCKNIX fork](../implementations/rocknix.md).

| Mode | Archived `flip` tree | Notes |
|------|----------------------|--------|
| **Standard suspend** (suspend-to-RAM / `echo mem > /sys/power/state`) | **Demonstrated** without the deep-sleep driver stack. | Combo chip power for sleep was **RTL8733BU-POWER** `.suspend_late` / `.resume` ([e728b28](https://github.com/Zetarancio/distribution/commit/e728b28834)); the Miyoo Flip `sleep.d` 001-btusb pre/post hooks were removed ([47fb725](https://github.com/Zetarancio/distribution/commit/47fb7252bc)). `060-btusb_power` still wrote a `bluetooth.service` drop-in. Enabling **`usb_host0_ohci` without the PHY 480 MHz clock** hung in `suspend_ops->enter()` (firmware SMC); the fourth clock was added on that tree ([54d8b02](https://github.com/Zetarancio/distribution/commit/54d8b02425)). |
| **Deep suspend** (BL31 `ARMOFF_LOGOFF`, lowest sleep current, **`vdd_logic` off-in-suspend**) | **Left off** | Patches **1013a** / **1013b** were **`*.testing-disabled`**. Kernel config: **`CONFIG_RK3568_SUSPEND_MODE` was not set** ([ca7bb4a9](https://github.com/Zetarancio/distribution/commit/ca7bb4a903)). DTS: **`rk3568-suspend`** commented out; **`vdd_logic`** stayed **`regulator-on-in-suspend`**. |

**Why that tree left deep suspend off even though testing had shown it working:** re-enabling it was blocked on an **upstream EmulationStation** fix. Shipping it would have regressed the handheld UX for typical users of that image.

**Rough standby expectation (informal, that configuration):** with deep suspend off, field-style estimates were on the order of **40–50 hours** suspended on a charge. With **deep suspend** plus **`vdd_logic` off-in-suspend** and the full BL31 flag set, similar estimates in testing clustered around **100–120 hours**.

