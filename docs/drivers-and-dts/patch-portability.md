# Patch portability and DTS requirements

Detailed analysis of what each out-of-tree kernel patch reads from the device tree and how portable they are to other RK3566/RK3568 boards.

Patches live under `projects/ROCKNIX/devices/RK3566/patches/linux/` in the distribution tree.

---

## Patch 0029 — `mfd: rk8xx: BSP-style PMIC pinctrl switching`

**What the driver reads from DTS:**

The driver calls `devm_pinctrl_get(dev)` on the PMIC I2C device node, then looks up three named states:

| Lookup | pinctrl-names index | Used when |
|--------|---------------------|-----------|
| `"pmic-sleep"` | `pinctrl-1` | Suspend: after writing `SLPPIN_SLP_FUN` to SYS_CFG(3) |
| `"pmic-power-off"` | `pinctrl-2` | Shutdown: after clearing SLPPIN and setting SLPPOL_H |
| `"pmic-reset"` | `pinctrl-3` | Resume: after disarming SLPPIN registers |

All three lookups are optional (`IS_ERR → NULL`). If none exist, the patch does nothing beyond the register writes that mainline already has.

At probe, it also unconditionally writes two PMIC registers (RK817/RK809 only):
- `RK817_POWER_CONFIG` — sets DCDC3 feedback to external resistor
- `RK817_SYS_CFG(3)` — sets `SLPPIN_NULL_FUN | RST_FUNC_DEV`

**DTS required on the PMIC node:**

```dts
pinctrl-names = "default", "pmic-sleep", "pmic-power-off", "pmic-reset";
pinctrl-0 = <&pmic_int>;
pinctrl-1 = <&soc_slppin_slp>;
pinctrl-2 = <&soc_slppin_gpio>;
pinctrl-3 = <&soc_slppin_gpio>;   /* or soc_slppin_gpio_idle — see notes */
```

**Pinctrl groups required in `&pinctrl { pmic { ... } }`:**

```dts
soc_slppin_slp: soc-slppin-slp {
    rockchip,pins = <0 RK_PA2 1 &pcfg_pull_none>;     /* mux 1 = PMU_SLEEP */
};
soc_slppin_gpio: soc-slppin-gpio {
    rockchip,pins = <0 RK_PA2 RK_FUNC_GPIO &pcfg_output_low>;
};
```

**BSP (rosa1337) vs ROCKNIX differences:**

| Property | rosa1337 BSP | ROCKNIX (Miyoo Flip) |
|----------|-------------|----------------------|
| `pinctrl-0` | `<&pmic_int>` | `<&pmic_int>, <&i2s1m0_mclk>` |
| `pinctrl-1` | `<&soc_slppin_slp>, <&rk817_slppin_slp>` | `<&soc_slppin_slp>` |
| `pinctrl-2` | `<&soc_slppin_gpio>, <&rk817_slppin_pwrdn>` | `<&soc_slppin_gpio>` |
| `pinctrl-3` | `<&soc_slppin_gpio>, <&rk817_slppin_rst>` | `<&soc_slppin_gpio>` |
| `soc_slppin_slp` pull | `pcfg_pull_up` | `pcfg_pull_none` |
| `soc_slppin_gpio` pull | `pcfg_output_low_pull_down` | `pcfg_output_low` |
| Extra pinctrl | `soc_slppin_rst` (mux 2) | Not used |

The BSP includes `rk817_slppin_slp`, `rk817_slppin_pwrdn`, `rk817_slppin_rst` — these are **PMIC-internal pinctrl states** handled by the BSP's `pinctrl-rk805.c` driver (which writes PMIC registers to configure SLPPIN function). Mainline has no such PMIC pinctrl driver, so patch 0029 does the equivalent register writes directly in `rk8xx-core.c` (`SLPPIN_SLP_FUN`, `SLPPIN_DN_FUN`, `SLPPIN_NULL_FUN`).

**Portability to other RK3566/RK3568 devices:**

- The SoC-side pin is **always GPIO0_PA2** on RK3566/RK3568 — hardwired in the SoC. So `soc_slppin_slp` / `soc_slppin_gpio` definitions are portable as-is.
- The PMIC interrupt pin varies per board (GPIO0_PA3 on Miyoo Flip, could differ).
- `i2s1m0_mclk` in `pinctrl-0` is Miyoo Flip-specific (MCLK pin configuration for audio). Other boards would have their own audio pinctrl or none.
- `system-power-controller` / `rockchip,system-power-controller` is a per-board choice.

**Minimum DTS for 0029 on any RK3566/RK3568 board with RK817/RK809:**

```dts
&i2c0 {
    rk817: pmic@20 {
        pinctrl-names = "default", "pmic-sleep", "pmic-power-off", "pmic-reset";
        pinctrl-0 = <&pmic_int>;
        pinctrl-1 = <&soc_slppin_slp>;
        pinctrl-2 = <&soc_slppin_gpio>;
        pinctrl-3 = <&soc_slppin_gpio>;
        /* ... rest of PMIC node ... */
    };
};

&pinctrl {
    pmic {
        pmic_int: pmic-int {
            rockchip,pins = <0 RK_PA3 RK_FUNC_GPIO &pcfg_pull_up>;
        };
        soc_slppin_slp: soc-slppin-slp {
            rockchip,pins = <0 RK_PA2 1 &pcfg_pull_none>;
        };
        soc_slppin_gpio: soc-slppin-gpio {
            rockchip,pins = <0 RK_PA2 RK_FUNC_GPIO &pcfg_output_low>;
        };
    };
};
```

---

## Patch 0030 — `mfd: rk8xx: log ON_SOURCE/OFF_SOURCE`

**What the driver reads from DTS:** Nothing. It reads two PMIC registers (`RK817_ON_SOURCE_REG`, `RK817_OFF_SOURCE_REG`) at probe and logs them. Works on any RK817/RK809 without any DTS change.

**Portability:** Universal for any RK817/RK809 board. Zero DTS requirements.

---

## Patch 1013 — `rk3568 suspend mode configuration driver`

**What the driver reads from DTS:**

```c
node = of_find_node_by_name(NULL, "rk3568-suspend");
of_property_read_u32(node, "rockchip,sleep-mode-config", &s->mode_config);
of_property_read_u32(node, "rockchip,wakeup-config", &s->wakeup_config);
of_property_read_u32(node, "rockchip,sleep-debug-en", &s->debug_en);
```

And matches on `compatible = "rk3568,pm-config"`.

**DTS required:**

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
    rockchip,wakeup-config = <(0 | RKPM_GPIO_WKUP_EN)>;
};
```

**BSP (rosa1337) vs ROCKNIX:**

| Property | rosa1337 BSP (`rk3568.dtsi`) | ROCKNIX patch 1013 |
|----------|------------------------------|---------------------|
| Compatible | `"rockchip,pm-rk3568"` | `"rk3568,pm-config"` |
| Node name | `rockchip-suspend` | `rk3568-suspend` |
| Status | `disabled` (enabled per-board) | `okay` |
| Flags | Same 7 flags | Same 7 flags |
| Wakeup | `RKPM_GPIO_WKUP_EN` | `RKPM_GPIO_WKUP_EN` |

The namespace difference (`rk3568` vs `rockchip`) is intentional to avoid collision if the BSP driver ever lands in mainline.

**Interaction with vdd_logic:**

The `RKPM_SLP_ARMOFF_LOGOFF` flag tells BL31 to save/restore the logic domain across suspend. Without this flag, setting `regulator-off-in-suspend` on `vdd_logic` (DCDC_REG1) causes a hang on resume. So:

```dts
vdd_logic: DCDC_REG1 {
    regulator-state-mem {
        regulator-off-in-suspend;   /* ONLY safe with 1013 + ARMOFF_LOGOFF */
    };
};
```

**Portability:** The flags and wakeup sources are the same for all RK3566/RK3568 boards — these are SoC-level, not board-specific. Any RK3566/RK3568 board can copy the node verbatim. The wakeup-config may need `RKPM_USB_WKUP_EN` or other sources depending on the board's wake requirements.

---

## Patch 1012 — `RK3568 DMC devfreq driver`

**What the driver reads from DTS:**

```c
/* Matched by compatible */
{ .compatible = "rockchip,rk3568-dmc" }

/* Platform resources */
platform_get_irq_byname(pdev, "complete");    /* GIC_SPI 10 */
devm_regulator_get(dev, "center");            /* center-supply */
devm_clk_get(dev, "dmc_clk");                 /* clocks */
devfreq_event_get_edev_by_phandle(dev, "devfreq-events", 0);  /* DFI phandle */
devm_pm_opp_of_add_table(dev);                /* operating-points-v2 */
```

**DTS required:**

```dts
dmc: dmc {
    compatible = "rockchip,rk3568-dmc";
    interrupts = <GIC_SPI 10 IRQ_TYPE_LEVEL_HIGH>;
    interrupt-names = "complete";
    devfreq-events = <&dfi>;
    center-supply = <&vdd_logic>;
    clocks = <&scmi_clk 3>;
    clock-names = "dmc_clk";
    operating-points-v2 = <&dmc_opp_table>;
    status = "okay";
};

dmc_opp_table: dmc-opp-table {
    compatible = "operating-points-v2";
    opp-324000000 { opp-hz = /bits/ 64 <324000000>; opp-microvolt = <900000>; };
    opp-528000000 { opp-hz = /bits/ 64 <528000000>; opp-microvolt = <900000>; };
    opp-780000000 { opp-hz = /bits/ 64 <780000000>; opp-microvolt = <900000>; };
    opp-1056000000 { opp-hz = /bits/ 64 <1056000000>; opp-microvolt = <900000>; };
};
```

**BSP (rosa1337) vs ROCKNIX:**

| Property | rosa1337 BSP | ROCKNIX |
|----------|-------------|---------|
| Compatible | Same: `rockchip,rk3568-dmc` | Same |
| IRQ | Same: `GIC_SPI 10` | Same |
| `devfreq-events` | `<&dfi>, <&nocp_cpu>` | `<&dfi>` only |
| `center-supply` | per-board `.dtsi` | `<&vdd_logic>` |
| OPP table | per-board, varies by DDR type | Fixed 4 OPPs (adjusted by ATF at probe) |

The BSP also defines `dmc-fsp` and `dmcdbg` nodes — these are BSP-only. The ROCKNIX driver doesn't need them.

**Portability:** The `dmc` node is the same on every RK3566/RK3568 board (the SoC-level definition is in `rk3568.dtsi` in BSP). Board differences are:
- **`center-supply`**: whichever regulator feeds the logic domain (usually `vdd_logic`)
- **OPP table**: voltages depend on the specific DDR chips and board routing. The driver queries ATF for supported frequencies and disables unsupported OPPs, so a generous OPP table works.
- **DFI**: `<&dfi>` is always the same (SoC-level)

---

## Patch 1011 — `devfreq-event: rockchip-dfi: PM suspend/resume`

**What the driver reads from DTS:** Nothing additional. This patch adds PM ops to the existing `rockchip-dfi` driver. The DFI node is already defined in mainline `rk3568.dtsi`:

```dts
dfi: dfi@fe230000 {
    compatible = "rockchip,rk3568-dfi";
    reg = <0x0 0xfe230000 0x0 0x400>;
    interrupts = <GIC_SPI 20 IRQ_TYPE_LEVEL_HIGH>;
    rockchip,pmu = <&pmugrf>;
};
```

**Portability:** Universal. The DFI node is SoC-level, already in mainline. No board-specific DTS needed.

---

## Summary: What's Miyoo Flip-Specific vs Portable

| DTS Element | Miyoo Flip-Specific | Portable to Any RK3566/RK3568 |
|-------------|--------------------|-----------------------------|
| `soc_slppin_slp` / `soc_slppin_gpio` pinctrl groups | No | **Yes** — GPIO0_PA2 is hardwired on the SoC |
| `pmic_int` pin (GPIO0_PA3) | Verify per board | Usually GPIO0_PA3 on RK817 boards |
| `i2s1m0_mclk` in pinctrl-0 | **Yes** — audio-specific | No |
| PMIC `pinctrl-names` / `pinctrl-{1,2,3}` | No | **Yes** — any RK817/RK809 board |
| `rk3568-suspend` node + flags | No | **Yes** — SoC-level flags, same for all boards |
| `vdd_logic` `regulator-off-in-suspend` | No (needs 1013) | **Yes** — with 1013 + ARMOFF_LOGOFF |
| `dmc` node + OPP table | OPP voltages may vary | **Yes** — ATF adjusts OPPs at probe |
| `system-power-controller` | Per-board choice | Per-board choice |

**To bring these patches to another RK3566/RK3568 ROCKNIX device, the minimum DTS additions are:**

1. Add the three `soc_slppin_*` pinctrl groups to `&pinctrl { pmic { } }`
2. Add `pinctrl-names` / `pinctrl-{1,2,3}` to the RK817/RK809 PMIC node
3. Add the `rk3568-suspend` node with sleep/wakeup flags
4. Add the `dmc` node with `center-supply`, completion IRQ, DFI phandle, and OPP table
5. Optionally add `regulator-off-in-suspend` on `vdd_logic`
6. Enable `CONFIG_RK3568_SUSPEND_MODE=y` and `CONFIG_ARM_RK3568_DMC_DEVFREQ=y` in kernel config
