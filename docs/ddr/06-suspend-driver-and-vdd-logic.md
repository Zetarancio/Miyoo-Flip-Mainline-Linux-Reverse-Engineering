# Suspend Mode Driver & vdd_logic Off-in-Suspend

## Overview

An out-of-tree kernel driver (`rk356x-suspend`) was implemented to configure
BL31 (ARM Trusted Firmware) deep-sleep flags via SIP SMC calls. This enables
the deepest suspend states on RK3566, matching the stock BSP firmware behavior.

Combined with `vdd_logic` set to `regulator-off-in-suspend`, the system achieves
significantly lower power consumption during sleep.

---

## 1. Problem Statement

The mainline kernel on RK3566 does not include Rockchip's BSP `rockchip_pm_config`
driver. Without it, BL31 uses compiled-in default sleep flags, which typically
do not enable the deepest power modes (oscillator off, PMIC low-power, center
power domain off, etc.).

Additionally, turning off `vdd_logic` during suspend without first telling BL31
to expect `ARMOFF_LOGOFF` mode causes the system to hang on resume — BL31 does
not save/restore the logic domain state if it doesn't know it will be powered off.

---

## 2. Implementation

### Patch

In the [ROCKNIX distribution](https://github.com/Zetarancio/distribution): `projects/ROCKNIX/devices/RK3566/patches/linux/1013-soc-rockchip-add-suspend-mode-configuration-driver.patch`

### Files Added by the Patch

| File | Purpose |
|------|---------|
| `drivers/soc/rockchip/rk356x_suspend_config.c` | Platform driver: reads DTS config and sends SMC calls |
| `include/dt-bindings/suspend/rockchip-rk3568.h` | `RKPM_SLP_*` and `RKPM_*_WKUP_EN` flag definitions |

### Kconfig

```
config RK356X_SUSPEND_MODE
    bool "RK356x suspend mode configuration"
    depends on HAVE_ARM_SMCCC && SUSPEND && ARCH_ROCKCHIP
```

Enabled in `linux.aarch64.conf` with `CONFIG_RK356X_SUSPEND_MODE=y`.

### Naming Convention

The driver uses the `rk356x` namespace (`rk356x-suspend`, `rk356x,pm-config`)
to avoid collisions with Rockchip's BSP `rockchip_pm_config` driver, which uses
`rockchip-suspend` / `rockchip,pm-rk3568`. This ensures no conflicts if BSP code
is ever merged upstream.

---

## 3. How It Works

### Boot Sequence

1. Driver probes via `late_initcall_sync` (compatible = `rk356x,pm-config`)
2. Reads `rockchip,sleep-mode-config` and `rockchip,wakeup-config` from DTS
3. Sends config to BL31 via `SIP_SUSPEND_MODE` (SMC 0x82000003)
4. BL31 stores the flags for use during subsequent suspend cycles

### Suspend Sequence

1. Kernel calls `rk356x_suspend_prepare()` (PM `.prepare` callback)
2. Driver re-sends sleep config to BL31 (ensures flags are current)
3. Kernel proceeds with normal PSCI suspend
4. BL31 uses the configured flags to enter deep sleep:
   - Powers off ARM cores
   - Powers off logic domain (`ARMOFF_LOGOFF`)
   - Powers off center power domain
   - Puts PMIC into low-power mode
   - Disables oscillator, switches to 32K PVTM clock

### Resume Sequence

1. GPIO wakeup interrupt triggers
2. BL31 restores logic domain state (because `ARMOFF_LOGOFF` was set)
3. ARM cores reinitialize
4. OP-TEE secondary CPUs reinitialize
5. Kernel resumes normally

---

## 4. DTS Configuration

### rk356x-suspend Node

```dts
#include <dt-bindings/suspend/rockchip-rk3568.h>

rk356x-suspend {
    compatible = "rk356x,pm-config";
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

**sleep-mode-config = 0x5ec** matches stock firmware flags:

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

`regulator-off-in-suspend` is safe **only** when the suspend driver is active
and has sent `RKPM_SLP_ARMOFF_LOGOFF` to BL31. Without this flag, BL31 does
not save/restore the logic domain state, and the system hangs on resume.

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

```
[    3.077330] rk356x-suspend-config rk356x-suspend: sleep-mode-config=0x5ec wakeup-config=0x10 (smc ret=0)
```

Driver probes successfully and BL31 accepts the configuration (`smc ret=0`).

### Suspend/Resume Cycle

```
[   54.188462] PM: suspend entry (deep)
[   65.289629] Enabling non-boot CPUs ...
[   66.830750] PM: suspend exit
```

Full deep sleep cycle confirmed (with vdd_logic off-in-suspend):
- `abcdeghijsramwfi` — BL31 suspend sequence letters
- `ABCDEFGHIJKLM` — BL31 resume sequence letters
- OP-TEE secondary CPUs reinitialize
- All 4 ARM cores come back up
- USB bus re-enumerates (expected after deep sleep)
- Total suspend duration ~12 seconds in test

**Status: CONFIRMED WORKING** — committed and pushed (2026-02-25).

---

## 7. Debugging Tips

### Enable BL31 Sleep Debug

Set `rockchip,sleep-debug-en = <1>` in the DTS node. BL31 will print
detailed power domain and register state over serial during suspend/resume.

### Serial Console

Ensure `uart2` is enabled in DTS and `systemd.debug_shell=ttyS2` is in
the kernel command line for serial debug access.

### If Device Does Not Wake

1. Verify driver loaded: `dmesg | grep rk356x-suspend`
2. Check SMC return code is 0
3. Temporarily revert `vdd_logic` to `regulator-on-in-suspend` with
   `regulator-suspend-microvolt = <900000>` to test without logic power-off
4. Check wakeup source — `RKPM_GPIO_WKUP_EN` must match actual wakeup GPIO

---

## 8. Kconfig Dependency Note

The Kconfig dependency must be `HAVE_ARM_SMCCC` (not `ARM_SMCCC`).
`HAVE_ARM_SMCCC` is the boolean that arm64 sets; `ARM_SMCCC` does not exist
as a standalone Kconfig option. Using the wrong symbol causes `make olddefconfig`
to silently drop the config option.

---

## 9. Relationship to DDR Frequency Scaling

The suspend driver and the DDR DMC devfreq driver
(`1012-devfreq-rockchip-add-rk3568-dmc-devfreq-driver.patch`) are independent
but complementary:

| Feature | DMC Devfreq (1012) | Suspend Driver (1013) |
|---------|-------------------|----------------------|
| Purpose | DDR frequency scaling during runtime | Deep sleep configuration |
| SIP Function | `SIP_DRAM_CONFIG` (0x82000008) | `SIP_SUSPEND_MODE` (0x82000003) |
| Active during | Normal operation | Suspend/resume |
| Power saving | Reduces DDR power at idle | Reduces total SoC power during sleep |
| vdd_logic | Uses vdd_logic as center-supply | Enables vdd_logic power-off in suspend |

Together they provide comprehensive power management: DDR scales to 324 MHz
at idle (saving runtime power), and during suspend the entire logic domain
powers off (saving sleep power).
