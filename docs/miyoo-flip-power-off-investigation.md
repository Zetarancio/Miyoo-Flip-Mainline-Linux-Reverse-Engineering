# Miyoo Flip — Power-off battery drain investigation

**Wiki:** This file is the long-form write-up. The wiki index links here from [Troubleshooting](troubleshooting.md), [Stock firmware and findings](stock-firmware-and-findings.md), and [Board DTS / PMIC](drivers-and-dts/board-dts-pmic-ddr-updates.md).

**Artifacts in this repository** (also on GitHub [`main`](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering)):

| Path | GitHub | Purpose |
|------|--------|---------|
| `bl31_v1.44_stock_disasm/` | [tree](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/tree/main/bl31_v1.44_stock_disasm) | Disassembly of stock-adjacent `rk3568_bl31_v1.44.elf` (Steward-fu rkbin snapshot). |
| `bl31_v1.45_rocknix_disasm/` | [tree](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/tree/main/bl31_v1.45_rocknix_disasm) | Disassembly of ROCKNIX `rk3568_bl31_v1.45.elf`. |
| `bl31_v1.44_vs_v1.45_diff.patch` | [blob](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/blob/main/bl31_v1.44_vs_v1.45_diff.patch) | Diff between v1.44 and v1.45 disassembly exports. |
| `logs/Stock-dump.txt` | [blob](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/blob/main/logs/Stock-dump.txt) | Stock BSP runtime: GPIO, pinmux, regulator summary, partial PMIC reads. |
| `logs/Rocknix-dump-Before-ChargerFIX.txt` | [blob](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/blob/main/logs/Rocknix-dump-Before-ChargerFIX.txt) | ROCKNIX PMIC `i2cdump` @ 0x20, debugfs; **before** kernel patch 0007 (SYS_CAN_SD). |

> **Date:** 2026-03-29 — 2026-04-05
>
> **Symptom:** ~8 mA battery drain while fully OFF (measured with ammeter).
>
> **Root cause (§18):** SYS_CAN_SD — bit 7 of RK817 register 0xe6
> (CHRG_TERM).  The BSP charger driver unconditionally clears this bit at
> probe (`rk817_charge_sys_can_sd_disable`); the mainline `rk817_charger.c`
> never touches it, leaving the hardware default (set).  When set, the
> PMIC charger monitoring block stays powered after system-off, drawing
> ~8 mA.  Clearing it → 0.05 mA.
>
> **Fix:** Kernel patch `0007-power-supply-rk817-disable-idle-charger-
> monitoring-f.patch` — one `regmap_write_bits` in `rk817_battery_init()`.
> (Same topic was once called “patch 007” in discussion; the file in-tree is **0007**.)

> **Resolution (wiki):** With this patch applied, off-state current matches stock (~0.05 mA). The investigation below is preserved as a **chronological lab notebook**; §1–§16 include hypotheses later refined in §17–§18.
>
> **Investigation history (§1–§17):** Explored and ruled out shutdown
> sequencing (SLPPIN/DEV_OFF/BL31), GPIO0_PA2 pinctrl management, RK860
> CPU regulator quiescent draw, WiFi chip, USB PHY topology, IRQ masking,
> regulator DTS differences, and unused-pin holders.  Ammeter measurements
> (§14) established 8 mA as the board's hardware default and 0.05 mA as
> stock's target.  Full PMIC register comparison (§17) identified 21
> config differences; systematic binary search (§18) narrowed to one bit.

---

## 1. Kernel power-off call chain (verified — mainline 6.18.x)

```
kernel_power_off()                        (kernel/reboot.c)
 ├─ device_shutdown()                     runs i2c .shutdown callbacks
 │     └─ rk8xx_shutdown()               ALWAYS runs (rk8xx-core.c)
 │           writes SLPPIN_DN_FUN (vanilla only — patch 0029 does not touch this)
 │
 ├─ do_kernel_power_off_prepare()         sys_off POWER_OFF_PREPARE chain
 │     └─ rk808_power_off()              ONLY if system-power-controller
 │           vanilla: typically DEV_OFF on RK817_SYS_CFG(3) for RK817
 │           + patch 0029: IRQ mask, SLPPIN/pinctrl sequence, SLPPIN_DN_FUN,
 │           mdelay(2) in the RK809/RK817 case (see `0029-...patch.off`)
 │           (0029 is `.patch.off` in tree — prepare path is vanilla)
 │
 └─ machine_power_off()                   (arch/arm64/kernel/process.c)
       └─ do_kernel_power_off()
             └─ pm_power_off()            set by PSCI driver
                   └─ psci_sys_poweroff() → SMC PSCI_0_2_FN_SYSTEM_OFF
                         └─ BL31 (rkbin blob) — behavior unknown
```

### What each step does to the RK817 PMIC (register 0xf4 = `RK817_SYS_CFG(3)`)

| Step | With `system-power-controller` | Without `system-power-controller` |
|------|-------------------------------|----------------------------------|
| `rk8xx_shutdown` | Writes SLPPIN_DN_FUN (bits [4:3] = 0b10). Configures PMIC sleep-pin function to "power down" — but does NOT trigger it (pin is driven LOW by SoC, PMIC waits for HIGH transition due to SLPPOL_H). | Same |
| `rk808_power_off` | With `system-power-controller`: vanilla mainline writes **DEV_OFF** (bit 0) for RK817 (verify exact `rk8xx-core.c` in your build). **Patch 0029** adds a BSP-style sequence in the same function’s RK809/RK817 branch (IRQ masks, optional `pmic-power-off` pinctrl, **SLPPIN_DN_FUN**, `mdelay(2)`) — it does **not** add that logic to `rk8xx_shutdown()`. | **Does not run** — handler not registered |
| PSCI SYSTEM_OFF | BL31 blob executes. Unknown whether it asserts GPIO0_PA2 to trigger SLPPIN power-down. | Same |

**Key finding:** Without `system-power-controller`, the ONLY mechanism that can power off the PMIC is BL31 asserting GPIO0_PA2 during PSCI SYSTEM_OFF. Whether it actually does this is unknown — the BL31 binary is closed-source and rkbin contains no documentation about SYSTEM_OFF behavior.

---

## 1b. BSP vs mainline — which driver, which shutdown path?

Rockchip ships **two independent MFD implementations** for the same DT compatible
`rockchip,rk817`. They are **not** layered (BSP `rk808_probe()` does **not** call
mainline `rk8xx_probe()`). Kconfig chooses which object files are built; a given
kernel image should enable **only one** of the two I2C drivers, otherwise both
would register for the same compatible and **whichever probes first wins**
(behavior is undefined and should be avoided).

| | **BSP path** (`drivers/mfd/rk808.c`) | **Mainline split path** (`rk8xx-core.c` + `rk8xx-i2c.c`) |
|---|--------------------------------------|-----------------------------------------------------------|
| **Typical Kconfig** | `CONFIG_MFD_RK808=y` (e.g. `rockchip_linux_defconfig` in rk3568_linux-rosa1337) | `CONFIG_MFD_RK8XX=y` + `CONFIG_MFD_RK8XX_I2C=y` (e.g. ROCKNIX RK3566 `linux.aarch64.conf`; `CONFIG_MFD_RK808` not set) |
| **I2C driver** | `rk808_i2c_driver` (module name `"rk808"`) | `rk8xx_i2c_driver` (module name `"rk8xx-i2c"`) |
| **Entry point** | `rk808_probe()` | `rk8xx_i2c_probe()` → `rk8xx_probe()` |
| **DT property for PMIC power-off handler** | `rockchip,system-power-controller` (`of_property_read_bool` on PMIC node) | `system-power-controller` **or** `rockchip,system-power-controller` (`device_property_read_bool` — exact set depends on kernel version; verify in-tree) |

### Shutdown phases for **RK817** (order is `kernel_power_off()` in `reboot.c`)

| Phase | BSP (`rk808.c`) | Mainline (`rk8xx-core.c` + `rk8xx-i2c.c`) |
|-------|-----------------|---------------------------------------------|
| **1. `device_shutdown()`** | No `.shutdown` on `rk808_i2c_driver` for RK817 | `rk8xx_i2c_shutdown()` → `rk8xx_shutdown()` writes **SLPPIN_DN_FUN** only. **Patch 0029 does not change this path.** |
| **2. `do_kernel_power_off_prepare()`** | If `rockchip,system-power-controller`: `rk817_shutdown_prepare()` — IRQ mask, pinctrl, **SLPPIN_DN_FUN**, `mdelay(2)`. **No DEV_OFF.** | If `system-power-controller`: **`rk808_power_off()`**. Vanilla mainline (~6.18.x) typically ends this phase with **DEV_OFF** for RK817 (confirm in your tree’s `rk8xx-core.c`). **Patch 0029** (`projects/ROCKNIX/devices/RK3566/patches/linux/0029-mfd-rk8xx-add-pmic-pinctrl-switching-for-RK817.patch.off`) **replaces/expands the RK809/RK817 `case` inside `rk808_power_off()`** with IRQ masks, optional `pmic-power-off` pinctrl (NULL_FUN → SLPPOL_H → GPIO), **SLPPIN_DN_FUN**, and `mdelay(2)` — still **after** phase 1, so you get **vanilla `rk8xx_shutdown()`** then **0029-augmented prepare**. Whether **DEV_OFF** still runs in the same handler after that `case` depends on the full function layout after your rebase — **inspect the built `rk8xx-core.c`**. |
| **3. `syscore_shutdown()`** | For RK817, `device_shutdown_fn` is never set → no BSP syscore PMIC step. | No equivalent syscore PMIC shutdown in `rk8xx_probe()`. |
| **4. `machine_power_off()` → PSCI** | `pm_power_off` → `PSCI_0_2_FN_SYSTEM_OFF` → BL31 blob | Same |

### Summary -- what actually differs for RK817 power-off

| Mechanism | BSP `rk808.c` | Mainline + ROCKNIX |
|-----------|---------------|---------------------|
| **DEV_OFF (bit 0, reg 0xf4)** | **Never** used for RK817 | **Typically yes** in vanilla `rk808_power_off()` for RK817 (mainline). **Patch 0029 does not remove this by itself** — verify post-`case` flow in your kernel tree. |
| **SLPPIN_DN_FUN (bits [4:3])** | Yes, in `rk817_shutdown_prepare()` | **Phase 1:** `rk8xx_shutdown()` (vanilla). **With patch 0029, also phase 2:** second SLPPIN/pinctrl sequence inside **`rk808_power_off()`**. |
| **I2C `.shutdown` callback** | No `.shutdown` on BSP I2C driver | Yes: `rk8xx_i2c_shutdown()` → `rk8xx_shutdown()` (SLPPIN_DN_FUN); unchanged by 0029. |

**Verified from `0029-mfd-rk8xx-add-pmic-pinctrl-switching-for-RK817.patch.off`:** The published diff modifies **`rk808_power_off()`** (RK809/RK817 branch), **RK817 suspend/resume** branches, adds **`rk817_pinctrl_init()`** at probe (BUCK3 feedback + `SYS_CFG(3)` init), and **`rk808.h`** — it contains **no hunks under `rk8xx_shutdown()`**.

**Speculation:** Mainline added DEV_OFF for RK817 as a register-level power-off that
does not depend on BL31 toggling GPIO0_PA2. Whether that matches Rockchip's
silicon intent better than BSP's SLPPIN-only path is not documented in public
sources; only testing (e.g. off-state drain) can validate it.
---

## 2. DEV_OFF vs SLPPIN_DN_FUN — register 0xf4 bit layout

From `include/linux/mfd/rk808.h` (verified in BSP 5.10, 6.6, and mainline):

```
RK817_SYS_CFG(3) = register 0xf4

Bit [0]    DEV_OFF           — software power-off command
Bit [2]    DEV_RST           — software reset command (6.6 BSP only defines this)
Bits [4:3] SLPPIN_FUNC       — sleep pin function selector:
             0b00 = NULL_FUN  (pin has no effect)
             0b01 = SLP_FUN   (pin triggers PMIC sleep mode)
             0b10 = DN_FUN    (pin triggers PMIC power-down)
             0b11 = RST_FUN   (pin triggers PMIC reset)
Bit [5]    SLPPOL            — sleep pin polarity (H=active high, L=active low)
Bits [7:6] RST_FUNC          — reset behavior:
             0b00 = reset entire device
             0b01 = reset registers only
```

**DEV_OFF and SLPPIN_DN_FUN are independent mechanisms in the same register:**
- DEV_OFF (bit 0): immediate software power-off, no external pin needed
- SLPPIN_DN_FUN (bits [4:3]): configures what happens when the sleep pin
  transitions — requires external GPIO assertion to take effect

### BSP kernel behavior (verified in three trees: stock 5.10, rosa1337, rockchip 6.6)

**The BSP NEVER writes DEV_OFF for RK817/RK809.** The `rk8xx_device_shutdown()` function has no `case RK817_ID` / `case RK809_ID`. Only RK805, RK808, RK816, RK818 use DEV_OFF.

The BSP uses for RK817 (I2C `rk808.c` path):
1. `rk817_shutdown_prepare()` → SLPPIN_DN_FUN + optional pinctrl (same register effect
   as PMIC-internal `pin_fun2` when used from DT).
2. **No** `rk8xx_device_shutdown()` / syscore `pm_shutdown` path for RK817 (those exist
   only for RK801/805/808/816/818). Full power-off still relies on **BL31 after PSCI
   SYSTEM_OFF** and/or PMIC reaction to SLPPIN/DEV_OFF. **Speculation:** older BSP
   comment paths that “spin” after `pm_shutdown()` do not apply to RK817 on this
   driver branch.

### Mainline kernel behavior (verified — rk8xx-core.c in 6.18.x)

Mainline `rk808_power_off()` DOES write DEV_OFF for RK817:
```c
case RK809_ID:
case RK817_ID:
    reg = RK817_SYS_CFG(3);
    bit = DEV_OFF;           // BIT(0)
    break;
```

This is a **mainline divergence from BSP**, not a bug per se — mainline developers
added DEV_OFF support for RK817 as a direct power-off mechanism.

### Other ROCKNIX RK3566 devices (verified)

- **Powkiddy X55** (`rk3566-powkiddy-rk2023.dtsi`): `system-power-controller` enabled,
  `pinctrl-names = "default"` only (no pmic-sleep/power-off/reset states).
  Same vendor BL31 (`rk3568_bl31_v1.45.elf`). No reported drain issues (unverified —
  no user reports checked).
- **Anbernic RG-DS** (`rk3568-anbernic-rg-ds.dts`): `system-power-controller` enabled,
  `pinctrl-names = "default"` only. Same vendor BL31. Has a comment claiming
  `system-power-controller` "is needed when using mainline ATF" and "not needed"
  with vendor ATF — **this claim is unverified and may be wrong**.

---

## 3. PMIC-internal pinctrl: needed or not?

### What the stock firmware does (verified from decompiled DTS)

Stock DTS `pinctrl-2` (pmic-power-off) = `<soc_slppin_gpio>` + `<rk817_slppin_pwrdn>`:
- `soc_slppin_gpio`: SoC-side — muxes GPIO0_PA2 to GPIO mode, output low
- `rk817_slppin_pwrdn`: PMIC-internal — writes pin_fun2 → `RK817_PINMUX_FUN2` (= 2)

The PMIC-internal pinctrl driver (`pinctrl-rk805.c`) writes to `RK817_SYS_CFG(3)` bits
[4:3] via `_rk817_pinctrl_set_mux()`. The value for `pin_fun2` is 2, shifted by
`ffs(RK817_SLPPIN_FUNC_MSK) - 1 = 3`, so the register write is `2 << 3 = 0x10` →
which is exactly `SLPPIN_DN_FUN`.

### What our patch 0029 does (verified from patch source)

File: `projects/ROCKNIX/devices/RK3566/patches/linux/0029-mfd-rk8xx-add-pmic-pinctrl-switching-for-RK817.patch.off`.

**Scope (not exhaustive):** optional SoC pinctrl states (`pmic-sleep` / `pmic-power-off` / `pmic-reset`); **`rk817_pinctrl_init()`** at probe (`RK817_POWER_CONFIG` BUCK3 feedback external, `SYS_CFG(3)` = `SLPPIN_NULL_FUN | RK817_RST_FUNC_DEV`); **RK809/RK817 suspend/resume** register ordering + pinctrl; **`rk808_power_off()`** RK809/RK817 case — IRQ masks, optional `pmic-power-off` path, `SLPPIN_DN_FUN` + `mdelay(2)`.

The PMIC-internal stock abstraction (`rk817_slppin_pwrdn` → `SLPPIN_DN_FUN` on bits [4:3]) is **functionally the same bit value** as a direct:

```c
regmap_update_bits(rk808->regmap,
                   RK817_SYS_CFG(3),
                   RK817_SLPPIN_FUNC_MSK, SLPPIN_DN_FUN);
```

**Conclusion:** For the **SLPPIN function bits** alone, BSP PMIC-internal pinctrl and this register write match. Patch 0029 still adds **SoC-side** pinctrl, **probe-time** init, **suspend/resume** behavior, and a **second** SLPPIN sequence in **`rk808_power_off()`** — those are not duplicated by stock DTS alone. The SoC-side mux controls GPIO0_PA2’s electrical path to BL31/PMU.

---

## 4. Stock `rockchip-suspend` node and `0x5ec`

### Decoding `0x5ec` (verified from `include/dt-bindings/suspend/rockchip-rk3568.h`)

```
0x5ec = 0b 0101 1110 1100

Bit  2: RKPM_SLP_CENTER_OFF     — power off center logic domain
Bit  3: RKPM_SLP_ARMOFF_LOGOFF  — ARM off + logic off
Bit  5: RKPM_SLP_PMIC_LP        — PMIC enters low-power mode
Bit  6: RKPM_SLP_HW_PLLS_OFF    — turn off hardware PLLs
Bit  7: RKPM_SLP_PMUALIVE_32K   — PMU alive domain runs at 32K
Bit  8: RKPM_SLP_OSC_DIS        — disable main oscillator
Bit 10: RKPM_SLP_32K_PVTM       — use PVTM for 32K clock
```

### Our DTS value (verified from `rk3566-miyoo-flip.dts`)

```
RKPM_SLP_CENTER_OFF | RKPM_SLP_ARMOFF_LOGOFF | RKPM_SLP_PMIC_LP
| RKPM_SLP_HW_PLLS_OFF | RKPM_SLP_PMUALIVE_32K | RKPM_SLP_OSC_DIS
| RKPM_SLP_32K_PVTM
= BIT(2)|BIT(3)|BIT(5)|BIT(6)|BIT(7)|BIT(8)|BIT(10)
= 0x5ec
```

**Our ROCKNIX DTS matches stock exactly for sleep-mode-config.** Both pass `0x5ec` to BL31.

### Relevance to power-off drain

**This node configures SUSPEND (sleep) behavior, NOT power-off.** The
`sleep-mode-config` is sent to BL31 via `SIP_SUSPEND_MODE` SMC and affects what BL31
does during `suspend-to-RAM`. It has no direct effect on the `PSCI_SYSTEM_OFF` path.

However, for **virtual power-off** (which the stock BSP supports via
`rockchip,virtual-poweroff` property), the suspend config IS used because virtual
power-off is implemented as `PSCI_SYSTEM_SUSPEND` (deep suspend that looks like
power-off). Our ROCKNIX kernel does not use virtual power-off.

---

## 5. What other ROCKNIX RK3566 devices do (verified, for context)

| Device | `system-power-controller` | PMIC pinctrl states | Vendor BL31 | Reported drain |
|--------|--------------------------|--------------------|----|---|
| Powkiddy X55 | Yes | default only | rk3568_bl31_v1.45 | Unknown |
| Anbernic RG-DS | Yes | default only | rk3568_bl31_v1.45 | Unknown |
| **Miyoo Flip** | **Yes (recently)** | default + sleep + power-off + reset | rk3568_bl31_v1.45 | **~1%/hour** (confirmed WITH and WITHOUT `system-power-controller` + patch 0029) |

Note: the Miyoo Flip is the only device with full pinctrl states defined, thanks to
patch 0029. Whether this matters for power-off (vs suspend) is unclear.

---

## 6. Hypotheses (speculation section)

### Hypothesis A: Without `system-power-controller`, nothing powers off the PMIC

**Evidence:**
- Without `system-power-controller`, `rk808_power_off()` (DEV_OFF) never runs
- `rk8xx_shutdown()` writes SLPPIN_DN_FUN but doesn't trigger the pin
- PSCI SYSTEM_OFF calls into BL31 blob — unknown what it does
- If BL31 doesn't assert GPIO0_PA2, PMIC stays on with all regulators active
- SoC halts in WFI but still draws power from active regulators

**Status:** Plausible. Would explain 1%/hour. **Testing `system-power-controller`
enabled should confirm or reject this** — if DEV_OFF works, drain should stop
regardless of BL31 behavior.

### Hypothesis B: DEV_OFF races with PSCI causing partial shutdown

**Evidence:** None from primary sources. This claim comes from previous
reverse-engineering docs (`troubleshooting.md`) but:
- The kernel call chain shows DEV_OFF fires in `do_kernel_power_off_prepare()`
  BEFORE `machine_power_off()` / PSCI
- Other ROCKNIX devices use this exact combination without reported issues
- Whether DEV_OFF actually causes problems is unverified

**Status:** Unverified speculation. Contradicted by other devices working. May
have been a misdiagnosis of a different issue (e.g., `soc_slppin_gpio_idle`
race during resume, which was the actual bug fixed earlier).

### Hypothesis C: BL31 drives GPIO0_PA2 during SYSTEM_OFF, so `system-power-controller` is redundant

**Evidence:**
- Patch 0029 commit message claims "BL31 drives the pin as GPIO to assert SLPPIN"
- The Anbernic comment says `system-power-controller` "is not needed" with vendor ATF
- BSP never uses DEV_OFF for RK817 — relies on SLPPIN_DN_FUN + BL31

**Status:** Unverified — no BL31 source available. If this were true, drain
would NOT occur without `system-power-controller` (contradicts the observed
symptom). Either BL31 doesn't drive the pin, or something else prevents clean
power-off.

### Hypothesis D: Something prevents BL31 from reaching the GPIO assertion

**Evidence (speculation):**
- With patch 0029, **`rk808_power_off()`** may select `pmic-power-off`
  (GPIO output LOW) and write SLPPIN_DN_FUN before PSCI SYSTEM_OFF
- SLPPOL_H means PMIC triggers on HIGH transition
- If BL31 tries to set GPIO0_PA2 HIGH but the pinmux is already in GPIO mode
  with output LOW, BL31 might re-drive it HIGH successfully — OR there could
  be a timing/configuration issue
- Without patch 0029's pinctrl switching (like Powkiddy/Anbernic), the pin
  is in whatever state boot left it — typically PMU_SLEEP mux from a previous
  suspend, which BL31 might handle differently

**Status:** Pure speculation. Would require logic analyzer or BL31 disassembly.

---

## 7. Test plan

1. **Test power-off with `system-power-controller` enabled** (current DTS state)
   - If drain stops → DEV_OFF works, root cause was Hypothesis A
   - If drain continues → DEV_OFF alone is insufficient, need further investigation

2. If #1 fails, compare **0029 on vs off** (0029 already adds SLPPIN_DN_FUN +
   pinctrl inside **`rk808_power_off()`**, not in `rk8xx_shutdown()`). Field
   result: **0029 off** improved drain (§12–§13).

3. If still failing, add serial debug: print register 0xf4 state just before
   PSCI SYSTEM_OFF to verify DEV_OFF bit was written and retained

---

## 8. Open question: should DEV_OFF be removed from mainline RK817 path?

### Findings

- **BSP** (all three trees): never uses DEV_OFF for RK817. Uses only SLPPIN_DN_FUN.
- **Mainline** (6.18.x): uses DEV_OFF for RK817 in `rk808_power_off()`.
- **BSP `rk8xx-core.c`** (6.6): has a SEPARATE `rk808_power_off()` that DOES use
  DEV_OFF for RK817 — but this is the SPI/generic core path, not the I2C path
  (`rk808.c`) which is what RK3566 boards actually use.

There are **two different shutdown codepaths in the BSP 6.6 kernel**:
- `rk808.c` (I2C): `rk817_shutdown_prepare()` — SLPPIN_DN_FUN only, no DEV_OFF
- `rk8xx-core.c` (generic/SPI): `rk808_power_off()` — DOES use DEV_OFF for RK817

**Verified:** These are completely independent drivers. `rk808.c` has its own
`rk808_probe()` (I2C) that does NOT call `rk8xx_probe()` from `rk8xx-core.c`.
The I2C path is the one that matches `"rockchip,rk817"` DT compatible on actual
RK3566 boards. At probe, when `rockchip,system-power-controller` is set, it
registers `rk817_shutdown_prepare` — SLPPIN_DN_FUN only, never DEV_OFF.

The `rk8xx-core.c` `rk808_power_off()` (with DEV_OFF) is only reachable via
`rk8xx_probe()`, which is called by the **mainline-style** split drivers
(`rk8xx-i2c.c` / `rk8xx-spi.c`). The BSP 6.6 kernel ships both driver sets
but standard I2C boards use `rk808.c`. The `rk8xx-core.c` DEV_OFF path is
effectively dead code for I2C-connected RK817 in the BSP.

**Conclusion:** In the BSP 6.6 kernel, RK817 power-off uses ONLY SLPPIN_DN_FUN.
DEV_OFF for RK817 exists only in mainline's unified `rk8xx-core.c` driver
(which ROCKNIX uses via kernel 6.18.13).

**For our patch 0029**, which modifies `rk8xx-core.c` (the mainline unified path):
`rk8xx_shutdown()` stays vanilla (SLPPIN_DN_FUN in phase 1). **`rk808_power_off()`**
gains the BSP-style IRQ/pinctrl/SLPPIN/`mdelay` block in the RK809/RK817 `case`
(phase 2), in addition to whatever **DEV_OFF** logic your tree retains after the
switch. That is two PMIC-touching prepare phases after one shutdown callback — not
“0029 inside `rk8xx_shutdown()`.”

**No change recommended until testing confirms whether DEV_OFF works.**

---

## 9. How to match the BSP shutdown path on ROCKNIX

The BSP RK817 power-off does exactly two things:
1. `rk817_shutdown_prepare()`: mask IRQs + SLPPIN_DN_FUN + optional pinctrl + mdelay(2)
2. PSCI SYSTEM_OFF (BL31 handles the rest)

ROCKNIX with patch 0029 enabled does:
1. `rk8xx_shutdown()`: **vanilla** SLPPIN_DN_FUN only (0029 does not modify this)
2. `rk808_power_off()`: **0029** adds IRQ mask + SLPPIN/pinctrl + `mdelay(2)` in the RK809/RK817 branch; vanilla may still apply **DEV_OFF** — confirm in build
3. PSCI SYSTEM_OFF

ROCKNIX with patch 0029 **disabled** (current tree): steps 1 + vanilla step 2 + 3.

### Option A: Replace DEV_OFF with SLPPIN_DN_FUN in patch 0029 (recommended to test)

Add a hunk to patch 0029 that changes `rk808_power_off()` for RK817 from:
```c
case RK809_ID:
case RK817_ID:
    reg = RK817_SYS_CFG(3);
    bit = DEV_OFF;
    break;
```
to the BSP equivalent (mask IRQs, pinctrl, SLPPIN_DN_FUN, mdelay):
```c
case RK809_ID:
case RK817_ID:
    regmap_update_bits(rk808->regmap, RK817_INT_STS_MSK_REG0, 0xff, 0xff);
    regmap_update_bits(rk808->regmap, RK817_INT_STS_MSK_REG1, 0xff, 0xff);
    regmap_update_bits(rk808->regmap, RK817_INT_STS_MSK_REG2, 0xff, 0xff);
    regmap_update_bits(rk808->regmap, RK817_RTC_INT_REG, (0x3 << 2), 0);
    if (rk808->pins && rk808->pins->power_off) {
        regmap_update_bits(rk808->regmap, RK817_SYS_CFG(3),
                           RK817_SLPPIN_FUNC_MSK, SLPPIN_NULL_FUN);
        regmap_update_bits(rk808->regmap, RK817_SYS_CFG(3),
                           RK817_SLPPOL_MSK, RK817_SLPPOL_H);
        pinctrl_select_state(rk808->pins->p, rk808->pins->power_off);
    }
    ret = regmap_update_bits(rk808->regmap, RK817_SYS_CFG(3),
                             RK817_SLPPIN_FUNC_MSK, SLPPIN_DN_FUN);
    mdelay(2);
    return NOTIFY_DONE;
```

This makes **`rk808_power_off()`** carry the full BSP sequence (Option A is
already close to what 0029 does in that function). **`rk8xx_shutdown()`** remains
a separate, earlier SLPPIN write unless you change it explicitly. The prepare
handler runs last before PSCI SYSTEM_OFF.

**Note:** This change requires `rk808_power_off()` to return early (before the
shared `regmap_update_bits(rk808->regmap, reg, bit, bit)` at the bottom) since
we're replacing the `reg`/`bit` switch with inline register writes. The function
structure changes from a switch-then-write to an early-return for RK817.

### Option B: Keep DEV_OFF, just test it

If `system-power-controller` with DEV_OFF stops the drain, there's no need
to match BSP exactly. DEV_OFF may be the simpler and more reliable mechanism
(direct register command vs. depending on BL31 to toggle a GPIO).

### Option C: Remove `system-power-controller` and rely only on `rk8xx_shutdown()`

Without the DT property, `rk808_power_off()` is never registered. Shutdown
would be:
1. `rk8xx_shutdown()`: SLPPIN_DN_FUN (vanilla; 0029 does not alter this)
2. PSCI SYSTEM_OFF -> BL31

This is closest to BSP but failed with drain -- suggesting either BL31 does
not assert GPIO0_PA2 or `rk8xx_shutdown()` alone is insufficient. Not
recommended unless you can verify BL31 behavior with a logic analyzer.

---

## 10. Confirmed: drain persists WITH system-power-controller + patch 0029

> **Date:** 2026-03-31
>
> **Test result:** Device STILL drains ~1%/hour while OFF with
> `system-power-controller` enabled and patch 0029 applied.

This **rejects Hypothesis A** — DEV_OFF alone is not sufficient. With 0029 on,
**`rk8xx_shutdown()`** (vanilla SLPPIN) and **`rk808_power_off()`** (0029’s
IRQ/pinctrl/SLPPIN sequence **plus** vanilla DEV_OFF if still in the handler)
still correlated with high drain — the PMIC was not fully off to the battery.

### Rejected / updated hypotheses

| Hypothesis | Status | Evidence |
|------------|--------|----------|
| A: "nothing powers off PMIC without system-power-controller" | **Rejected** | Drain persists WITH it enabled (DEV_OFF fires) |
| B: "DEV_OFF races with PSCI" | **Inconclusive** | Not the sole cause — drain also present without system-power-controller |
| C: "BL31 handles it all" | **Rejected** | Drain present in both cases |
| D: "Something blocks BL31 GPIO assertion" | **Inconclusive** | Still possible but can't test without logic analyzer |
| H1: "WiFi chip holds USB bus, blocks PMIC shutdown" | **Rejected** | WiFi killed before poweroff, drain still ~1%/h |
| H2: "USB PHY conflict prevents clean shutdown" | **Rejected** | WiFi-off test drain unchanged; PHY fix kept for correctness |
| H3: "rtl8733bu_power GPIO doesn't cut chip power" | **Rejected** | GPIO confirmed working (chip gone from lsusb) |
| H4: "Chip stays active when driver unloaded" | **Rejected** | Full power-off confirmed via GPIO + lsusb; drain persists |
| H5: "Patch 0029 `rk808_power_off()` / pinctrl interferes with clean SLPPIN+BL31 off" | **Partially confirmed** | §11 H5 + §12–§13; 0029 off → better drain, OFF_SOURCE 0x08 |

---

## 11. New investigation: USB WiFi chip (RTL8733BU) as drain source

### Key difference: Miyoo Flip vs X55 WiFi architecture

| | **Powkiddy X55** (no drain, upstream) | **Miyoo Flip** (drains) |
|---|--------------------------------------|------------------------|
| **WiFi chip** | SDIO-based (on `&sdmmc2`, `mmc-pwrseq-simple`) | **USB-based** (RTL8733BU, out-of-tree driver on EHCI) |
| **WiFi driver** | In-tree rtw88 SDIO | Out-of-tree `8733bu` vendor module |
| **Driver `.shutdown`** | rtw88 has proper PM callbacks | **No `.shutdown` on kernel >= 6.8** (removed upstream, vendor driver follows) |
| **Power control** | `mmc-pwrseq-simple` (SDIO slot power) | `rtl8733bu_power` (GPIO via rfkill) |
| **PHY topology** | Clean: SDIO, no USB host conflict | **PHY conflict found** (see below) |

### DTS bug found: USB PHY conflict (fixed 2026-03-31)

Two controllers were sharing one UTMI PHY, which stock firmware does NOT do:

```
BEFORE (bug):
  usb_host1_xhci → usb2phy1_host  ← CONFLICT
  usb_host1_ehci → usb2phy1_host  ← WiFi here too

AFTER (matching stock):
  usb_host1_xhci → usb2phy0_host  (its default PHY)
  usb_host1_ehci → usb2phy1_host  (WiFi, sole owner)
  usb_host0_ehci → okay           (stock enabled)
  usb_host0_ohci → okay           (stock enabled)
  usb_host1_ohci → okay           (stock enabled)
  usb2phy1_otg   → okay           (stock enabled)
```

### Missing pre-shutdown WiFi power-down (added 2026-03-31)

The out-of-tree `8733bu` driver has `.shutdown = rtw_dev_shutdown` only on
kernel < 6.8. On kernel 6.18 (ROCKNIX), **there is no `.shutdown` callback**.
The chip stays fully powered through `device_shutdown()` → PMIC shutdown.

Added `070-wifi_shutdown` quirk that installs a systemd unit to unload `8733bu`
+ `btusb`, block rfkill, and cut chip GPIO power before kernel shutdown.

---

## 11b. Suspend hang on mainline 6.18 (USB — separate from power-off drain)

**Symptom (2026-04-01):** Entering system suspend (`echo mem > /sys/power/state`) appeared to hang after the task freezer succeeded. The kernel never printed `Disabling non-boot CPUs` or reached the usual BL31 suspend path; resume never happened without a hard reset.

**Not the primary cause for this hang:** Patch 0029, RK817 PMIC pinctrl switching, or Mali regulator warnings. Older Steward-fu–style logs show the same Mali “failed to get regulator” noise while suspend still completes; treat those as red herrings unless paired with a real freeze.

**Confirmed fix (runtime isolation):** Unbinding the extra USB platform devices allowed suspend to complete in one test session:

- `fd800000.usb` (EHCI)
- `fd840000.usb` (OHCI companion for the unused host port)
- `fd8c0000.usb` (OHCI companion for the WiFi EHCI port)

After unbind, the log showed the normal progression through CPU off and `PM: suspend exit` on resume.

**Root cause (hypothesis → validated in-tree):** On this board, nothing is routed to the `usb2phy1_otg`–backed host pair (`usb_host0_ehci` / `usb_host0_ohci`). Stock DTS still enables them; their suspend callbacks on mainline 6.18.x deadlock or stall the global suspend sequence. Likewise, `usb_host1_ohci` is only the USB 1.1 companion to the WiFi EHCI controller; the RTL8733BU is high-speed and does not need OHCI. Disabling those controllers in the device tree removes the bad suspend path while keeping `usb_host1_ehci` + `usb_host1_xhci` (on `usb2phy0_host`) for the intended topology.

**Device tree follow-up:** Comments in `rk3566-miyoo-flip.dts` document controller addresses, which blocks stay disabled, and why (`usb_host1_xhci` uses `usb2phy0_host` so it does not share a PHY with the WiFi EHCI on `usb2phy1_host`). This work is orthogonal to the power-off / patch 0029 discussion below.

### Outstanding hypotheses (2026-03-31)

**H1: USB WiFi chip holds bus active, preventing clean PMIC shutdown**
- The RTL8733BU is USB-attached and has no `.shutdown` callback on 6.18.
  It stays powered and may keep USB PHY active during `device_shutdown()`.
  If USB bus activity prevents the I2C bus from completing DEV_OFF or
  SLPPIN writes, the PMIC never receives the power-off command.
- **Rejected (2026-04-01):** Manual test with `test-wifi-poweroff.sh` —
  chip powered off (RTL8733BU gone from `lsusb`, GPIO0_PA0 deasserted).
  Drain still ~7% over ~6.5 h (~1%/h). WiFi is not the off-state drain cause.

**H2: USB PHY conflict causes undefined behavior during shutdown**
- Two controllers sharing one UTMI PHY may cause the PHY to stay powered or
  prevent clean controller shutdown.
- **Rejected (2026-04-01):** WiFi-off test still drained ~1%/h. The PHY
  conflict is a real DTS bug (fixed) but is not the off-state drain cause:
  the drain predates the conflict (device also drained without
  `system-power-controller` when no USB host activity was relevant to
  power-off). DTS fix kept for correctness.

**H3: rtl8733bu_power GPIO doesn't actually cut chip power**
- The rfkill GPIO may not fully power off the chip (e.g. chip has internal
  LDO, USB VBUS keeps it alive, or GPIO only controls one power domain).
- **Rejected (2026-04-01):** `test-wifi-poweroff.sh` confirmed GPIO0_PA0
  transitions from `out lo` (asserted/ON) to `out hi` (deasserted/OFF),
  RTL8733BU disappears from `lsusb`. GPIO does cut chip power. Drain
  persists anyway → chip power is not the cause.

**H4: Chip stays active even when driver is unloaded**
- USB devices can draw power from VBUS regardless of driver state. The
  RTL8733BU may enter a low-power idle state but not fully power off when
  its driver is unloaded. Only cutting the power GPIO truly kills it.
- **Rejected (2026-04-01):** Same evidence as H3 — after rfkill block the
  chip is gone from USB bus entirely. The full unload + rfkill + GPIO
  sequence works, but drain persists.

**H5: Patch 0029’s extra work in `rk808_power_off()` (and probe/suspend) interferes
with a clean SLPPIN_DN + BL31 power-off**
- Order: **`rk8xx_shutdown()`** runs first (vanilla SLPPIN_DN_FUN only — 0029 does
  not modify this). Then **`rk808_power_off()`** runs; **with 0029** it masks IRQs,
  may select `pmic-power-off` pinctrl, and writes SLPPIN_DN_FUN again with `mdelay(2)`,
  while vanilla may still write **DEV_OFF** afterward depending on the function
  structure. The resulting **0xf4** / GPIO0_PA2 state may not match what BL31
  expects for a clean DN transition.
- **Partially confirmed (2026-04-03):** Patch 0029 disabled. OFF_SOURCE
  consistently shows **0x08** (SLPPIN_DN trigger); effective off path is **SLPPIN +
  BL31**, not DEV_OFF in the sticky OFF_SOURCE bits. Drain improved from ~1%/h to
  ~0.15–0.21%/h (2–3% / 14h); longer-term measurement needed. See §13.
- **2026-04-03 ammeter (§14):** Stock SPI **~0.05 mA** off vs ROCKNIX / SPI-erased
  (no ROCKNIX boot) **~8 mA** off — the **~8 mA** tracks **non-stock SPI / SD-boot
  prep**, not Linux `poweroff` alone; percentage-based field logs may still disagree
  with the meter (gauge vs true current).

---

## 12. Patch 0029 disabled; DTS aligned with vanilla rk8xx (2026-04-01)

The build system only applies files named `*.patch`. Patch 0029 was removed from the active set by renaming it to:

- **Inactive:** `projects/ROCKNIX/devices/RK3566/patches/linux/0029-mfd-rk8xx-add-pmic-pinctrl-switching-for-RK817.patch.off`
- **Re-enable:** rename back to `...RK817.patch` if you need the BSP-style PMIC pinctrl state machine again.

**Scope:** The file lives under `devices/RK3566/patches/linux/` — when disabled it affects **every** RK3566 device in this tree (Miyoo Flip, X55, Powkiddy, etc.). Coordinate before toggling.

**Suspend without 0029:** Earlier notes assumed suspend would regress without patch 0029. On Miyoo Flip, **full suspend/resume was re-tested with 0029 off** after the USB controller disablement in §11b. Suspend completes; the previous freeze was driven by USB, not by the absence of 0029.

**DTS with vanilla rk817 behavior:** The PMIC node now uses `pinctrl-names = "default"` only and includes `soc_slppin_slp` in `pinctrl-0` so GPIO0_PA2 is muxed to `PMU_SLEEP` for deep sleep — required because this product’s BL31 does not perform the same pin setup as typical Rockchip BSP stacks (contrast X55 / other RK3566 boards). `system-power-controller` remains enabled for the DEV_OFF path in `rk808_power_off()`.

**Power-off drain:** Field testing associated patch 0029 with worse fully-off drain; keeping it off removes the extra **`rk808_power_off()`** / probe / suspend changes while retaining vanilla **`rk8xx_shutdown()`** SLPPIN_DN_FUN + BL31. ON_SOURCE/OFF_SOURCE evidence (§13) shows DEV_OFF is **not** the mechanism recorded as shutting down the PMIC on this board — **SLPPIN_DN via BL31** is. `system-power-controller` remains enabled as a harmless safety net; if future data show it interferes, it can be removed without affecting the real shutdown path.

---

## 13. ON_SOURCE / OFF_SOURCE register evidence (2026-04-03)

Patch 0030 (`0030-mfd-rk8xx-log-on-off-source-for-RK817-RK809.patch`) reads
`RK817_ON_SOURCE_REG` (0xf5) and `RK817_OFF_SOURCE_REG` (0xf6) at probe and
logs them to dmesg. These registers record the reason the PMIC last powered
on and off, respectively.

### Raw data (build 20260401, patch 0029 inactive, USB topology fix applied)

| Boot | ON_SOURCE | OFF_SOURCE | Context |
|------|-----------|------------|---------|
| 1 | 0x80 | 0x08 | Cold start (power key), after prior poweroff |
| 2 | 0x80 | 0x08 | Cold start (power key), after `poweroff` via SSH |
| 3 | 0x02 | 0x08 | Warm reboot (`reboot` via SSH), charger connected |

### Interpretation

**OFF_SOURCE = 0x08 consistently — bit 3 = SLPPIN_DN trigger.**

The PMIC powered off because GPIO0_PA2 was asserted while SLPPIN_DN_FUN was
configured in `RK817_SYS_CFG(3)`. The shutdown sequence that produces this:

1. `device_shutdown()` → `rk8xx_shutdown()` writes **SLPPIN_DN_FUN** (bits [4:3])
   to register 0xf4. This arms the sleep pin for power-down on the next
   rising edge (SLPPOL_H).
2. `rk808_power_off()` writes **DEV_OFF** (bit 0) to register 0xf4. However,
   DEV_OFF does NOT appear in OFF_SOURCE — it either does not complete before
   the PMIC acts on SLPPIN, or the PMIC prioritizes SLPPIN as the recorded
   off-source.
3. `machine_power_off()` → PSCI SYSTEM_OFF → **BL31 drives GPIO0_PA2**.
   The PMIC sees the pin transition with DN_FUN active → powers off via SLPPIN.

**Key finding:** The effective power-off mechanism on Miyoo Flip is **SLPPIN_DN
via BL31**, not DEV_OFF via `system-power-controller`. BL31's PSCI SYSTEM_OFF
handler does drive the sleep pin on this board — answering the "unknown BL31
behavior" question from §1.

**ON_SOURCE = 0x80 — bit 7 = power key long-press power-on.** Normal cold
start. After a `reboot`, ON_SOURCE = 0x02 (bit 1 = plug-in) because the PMIC
does not fully power-cycle during a warm reset; the charger maintaining VSYS
is recorded as the on-source instead of the power key.

### Implications

- **`system-power-controller` / DEV_OFF is not the mechanism that kills the
  PMIC** on this device. It can remain as a harmless safety net but is not
  operationally necessary. If it ever interferes, removing it should not
  affect power-off behavior.
- **`rk8xx_shutdown()` writing SLPPIN_DN_FUN is the critical kernel step.**
  Without it, BL31 asserting GPIO0_PA2 would have no effect (PMIC would be
  in NULL_FUN or SLP_FUN). This function runs unconditionally in vanilla
  `rk8xx-core.c`, independent of `system-power-controller` or patch 0029.
- **Patch 0029’s extra manipulation likely interfered** — IRQ masking, SoC
  pinctrl, **second SLPPIN sequence in `rk808_power_off()`**, probe-time
  `SYS_CFG(3)` / BUCK3 init, and suspend/resume ordering may have left the PMIC
  or pin mux in a state where BL31’s GPIO assertion did not yield a clean DN_FUN
  power-down. Disabling 0029 restored **vanilla** `rk8xx_shutdown()` + prepare
  only and correlated with improved drain (~1%/h → ~0.15–0.21%/h).
- **`soc_slppin_slp` in pinctrl-0** muxes GPIO0_PA2 to PMU_SLEEP at boot
  for suspend. During power-off, BL31 apparently re-muxes or directly
  drives the pin as GPIO regardless of the Linux-time mux state.

### Off-state drain status

Initial measurement: **2–3% over 14 hours (~0.15–0.21%/h)**. This is a
significant improvement from the ~1%/h measured with patch 0029 active, but
falls in the range where coulomb-counter drift, voltage relaxation, and SOC
quantization can dominate. **Direct ammeter data (§14)** shows a large gap
between **stock (~50 µA)** and **ROCKNIX / erased-SPI (~8 mA)** off current;
reconcile percentage-based logs with the meter (gauge path, “off” definition,
and whether the device was ever on ROCKNIX vs only SPI-erased). Longer-term
measurement (48–72h+) is still useful on the stock image to confirm sub-mA off.

---

## 14. Direct off-state current: hardware default vs stock shutdown (2026-04-03)

### Instrumentation

- **Meter:** Ermenrich Zing TC07.
- **Awake:** COM + **10 A** jack, DC **10 A** range (boot transients exceed 20 mA;
  do not power-on on the mA range — overload / flicker).
- **Off:** COM + **VΩmA** jack, DC **20 mA** range (or next range if pegged).
- **Wiring:** One conductor of the battery feed broken; meter in series so
  all load current flows through the meter. Same battery and same break
  point for all rows below.

### Experimental sequence

Each step was performed on the same unit, same battery, same meter break point.

| Step | Action | Off current |
|------|--------|-------------|
| 1 | ROCKNIX running → `poweroff` from ROCKNIX | **~8 mA** |
| 2 | Enter MASKROM → flash stock SPI (`spi_20241119160817`) → **do not boot stock** | **~8 mA** |
| 3 | Boot stock → `poweroff` from stock (or hard-reset long-press) | **~0.05 mA** |
| 4 | Still on stock → enter MASKROM → erase internal SPI (**no SD card, no ROCKNIX involved**) | **~8 mA** |

Awake draw: **~0.6 A** on both stock and ROCKNIX (consistent meter setup).

### Interpretation

1. **~8 mA is the board's hardware default off-state.** It appears whenever
   no firmware has run a shutdown sequence. Step 2 proves this: stock firmware
   is on SPI but was never booted -- 8 mA. Step 4 confirms it without ROCKNIX
   even being present: stock was running, SPI erased, no SD card -- 8 mA.
2. **Stock BSP actively reduces off-state current to ~0.05 mA** during its
   shutdown path (step 3). Stock's `rk817_shutdown_prepare()` (or another
   BSP-specific step) configures PMIC registers, GPIO states, or power rails
   in a way that **persists after PMIC power-off** and suppresses the ~8 mA
   baseline. The kernel `poweroff` is not just arming SLPPIN -- it is
   **reconfiguring hardware that would otherwise leak**.
3. **ROCKNIX does not perform this extra configuration.** Mainline
   `rk8xx_shutdown()` + `rk808_power_off()` + BL31 SYSTEM_OFF arms SLPPIN
   and powers off the PMIC, but leaves the board's default leaky state intact.
4. **The Miyoo Flip board is "worse" than typical RK3566 designs** -- its
   default off-state draws ~8 mA instead of the sub-mA expected from the PMIC
   alone. Other RK3566 boards (X55, Anbernic, Powkiddy) likely have lower
   hardware baseline off current. The stock BSP was designed around this
   specific board and compensates; mainline Linux does not.
5. **Reconcile with earlier %/hour logs:** 8 mA continuous = ~192 mAh/day on a
   3000 mAh pack (~6%/day = ~0.27%/h), not the ~1%/h seen earlier. The ~1%/h
   with patch 0029 active was likely higher real drain (0029 interfered and
   added more leakage). Current ~8 mA matches the improved ~0.15-0.21%/h gauge
   reading from section 13 reasonably well.

### Next steps

See **section 15** — ribbon-cable isolation test and RK860 CPU regulator
analysis narrow the root cause significantly.

### Reference paths

- Stock SPI package (example): `/home/ale/Downloads/Steward-fu-FLIP/spi_20241119160817`
- Erase / SD-boot procedure: `/home/ale/Downloads/Steward-fu-FLIP/docs/boot-and-flash/flashing.md`

---

## 15. Ribbon-cable isolation + RK860 CPU regulator (2026-04-03)

### 15a. WiFi + display ribbon cable disconnected — still ~8 mA

**Experiment:** Boot ROCKNIX, SSH in, disconnect the shared ribbon cable
that carries both WiFi (RTL8733BU) and display, then `poweroff` via SSH.

**Result:** Off-state current remains **~8 mA** — identical to ribbon-cable-connected.

**Conclusion:** WiFi module and display panel are **not** the drain source.
The 8 mA is on the **main board** itself, independent of anything on the
ribbon cable.

#### Stock firmware userspace — nothing special

Full analysis of stock rootfs (`spi_20241119160817/unpack/rootfs/`) confirmed:

- `keymon` and `MainUI` simply call `poweroff` (the Linux command).
  No `devmem`, `i2cset`, `/dev/mem` access, no direct PMIC writes.
- `power-key.sh` long-press handler calls `poweroff`.
- `S36load_wifi_modules stop` does `echo 0 > /sys/class/rfkill/rfkill0/state`.
- Official **20250527** card firmware (`miyoo355_fw_20250527`) adds `hardwareservice` and
  `btmanager` — neither touches PMIC or power registers.

**There is no Miyoo userspace power-off fixup.** The fix is entirely in the
BSP kernel.

#### Stock firmware WiFi chip

Stock DTS says `wifi_chip_type = "rtl8733bu"` and stock boot log confirms
`CHIP TYPE: RTL8733B`, USB VID/PID `0x0BDA:0xB733`. The `RTL8189FU.ko` in
`/system/lib/modules/` is an unused leftover — the actual `rtl8733bu` driver
is **built into** the stock kernel.

#### OFF_SOURCE discrepancy

| Scenario | OFF_SOURCE | Meaning |
|----------|-----------|---------|
| Hardware long-press (stock + ROCKNIX) | `0x04` (bit 2) | PWRON_LP |
| ROCKNIX software `poweroff` | `0x08` (bit 3) | SLPPIN_DN |
| Stock software `poweroff` | `0x80` (bit 7) | Unknown — different mechanism |

Stock software poweroff produces `OFF_SOURCE=0x80`, not `0x08`. The two
kernels trigger **different** PMIC shutdown paths. Exact meaning of bit 7
in RK817 OFF_SOURCE is not documented in the SDK headers; needs datasheet.
BL31 disassemblies (`bl31_v1.44_stock_disasm/` and `bl31_v1.45_rocknix_disasm/`)
show identical PSCI SYSTEM_OFF code, so the difference is upstream of BL31 —
in the kernel's PMIC register writes before PSCI is invoked.

### 15b. Root cause: RK860 CPU regulator — VBAT-powered, no mainline .shutdown

**The RK860 (RK8600) CPU voltage regulator is powered directly from the
battery** (`vin-supply = <&vccsys>`), not through an RK817 PMIC rail. It
stays powered even after the PMIC shuts off all its regulators.

Stock shutdown log (from `logs/boot_log_STOCK_INCLUDE_SLEEP_POWEROFF_AND_DEBUG.txt`):

```
[273.315031] rk860-regulator 0-0040: rk860..... reset
[273.316298] rk860-regulator 0-0040: force rk860x_reset ok!
```

The BSP `fan53555.c` has a `.shutdown` callback (`fan53555_regulator_shutdown`)
that writes `CTL_RESET` to the RK860's slew register, forcing a hardware
reset. This puts the RK860 into its lowest-power state while it remains
connected to VBAT.

**Mainline `fan53555.c` (linux 6.18) has no `.shutdown` callback at all.**
The RK860 is left in its active/enabled state after the PMIC powers off.
With `vin-supply = <&vccsys>` (battery rail), it continues drawing quiescent
current from the battery indefinitely.

Relevant driver comparison:

| | BSP `fan53555.c` | Mainline `fan53555.c` (6.18) |
|--|---|---|
| `.shutdown` | `fan53555_regulator_shutdown` — writes `CTL_RESET` | **absent** |
| Effect on RK860 | Reset → low-power state | Left enabled → draws quiescent current |
| Input supply | `vccsys` (VBAT) — always present | Same — always present |

The RK860's quiescent current when enabled but unloaded is typically in the
low-mA range, consistent with the observed ~8 mA.

**UPDATE:** Patch 0006 (`fan53555_regulator_shutdown` with `CTL_RESET`) was
applied and confirmed executing (boot log shows `debug981cf3 shutdown CTL_RESET
ret=0`). Drain **still ~8 mA**. The RK860 is NOT the sole culprit. See §16
for the actual root cause.

### 15c. Why other RK3566 devices don't drain

Most RK3566 boards (Anbernic, Powkiddy, X55) use the same
`fan53555`-compatible CPU regulator family, but:

1. Their mainline DTS may have the CPU regulator powered from a PMIC-switched
   rail (not `vccsys`), so it loses power when the PMIC turns off.
2. Or they have a separate enable GPIO that the regulator framework de-asserts.
3. Or their board's hardware quiescent is inherently lower (pull resistors, FET
   switches on the VBAT path).

The Miyoo Flip is unusual in connecting the CPU regulator **directly to the
battery** without an intermediate switch.

### 15d. Fix

Add a `.shutdown` callback to the mainline `fan53555` driver (or a board-level
quirk) that writes `CTL_RESET` to the RK860 during `device_shutdown()`.

Minimal kernel patch (untested):

```c
static void fan53555_regulator_shutdown(struct i2c_client *client)
{
    struct fan53555_device_info *di = i2c_get_clientdata(client);
    /* Reset the regulator to its lowest-power state.
     * On boards where vin-supply is battery-direct (e.g. Miyoo Flip),
     * this prevents mA-level quiescent draw after PMIC power-off. */
    regmap_update_bits(di->regmap, di->slew_reg, CTL_RESET, CTL_RESET);
}
```

And in the `i2c_driver` struct:

```c
static struct i2c_driver fan53555_regulator_driver = {
    // ...
    .shutdown = fan53555_regulator_shutdown,
};
```

**Alternative (DTS-only, not yet verified):** Remove `regulator-always-on`
from the RK860 node so the regulator framework disables it when all
consumers are released during shutdown. However, this may cause issues if
the kernel tries to disable vdd_cpu while still running.

### 15e. Internal SPI NAND

The internal SPI NAND (disabled in ROCKNIX DTS) is powered by PMIC rails
(vcc_1v8 / vcc_3v3). When the PMIC powers off, the SPI NAND loses power.
Its standby current is in the µA range and cannot account for the ~8 mA.
The SPI NAND itself is not the drain source. The preloader content (U-Boot
SPL/TPL) in SPI has no effect on off-state drain — the user's experiments
in §14 proved that: flashing stock SPI without booting still shows 8 mA.

---

## 16. Boot-time PMIC initialisation — the real root cause (2026-04-03)

### 16a. The user's key experiment

| Step | Drain | What ran |
|------|-------|----------|
| Erase SPI NAND (no firmware at all) | **~8 mA** | Nothing — hardware defaults |
| Flash stock SPI without booting | **~8 mA** | Firmware on SPI but never executed |
| Boot stock, then **hardware long-press** | **~0.05 mA** | Stock U-Boot + kernel **booted** |
| Boot ROCKNIX, software `poweroff` | **~8 mA** | ROCKNIX U-Boot + kernel booted |

The hardware long-press is a **pure PMIC event** — no kernel shutdown path
runs. If stock's 0.05 mA is achieved via long-press after boot, then
something configured **at boot time** (not during shutdown) determines
whether the PMIC enters its deep-off state properly.

### 16b. BSP U-Boot init vs upstream U-Boot init

**BSP `rk817_init_reg[]`** (Rockchip SDK, `drivers/power/pmic/rk8xx.c`):

```c
static struct reg_data rk817_init_reg[] = {
    { RK817_BUCK4_CMIN,     0x6b, 0x6e },   /* under-voltage protection */
    { RK817_PMIC_SYS_CFG1,  0x20, 0x70 },   /* hotdie 105C / TSD 140C */
    { RK817_PMIC_SYS_CFG3,  0x00, 0x18 },   /* SLPPIN = NULL_FUN */
};
```

**Upstream `rk817_init_reg[]`** (u-boot v2026.01, used by ROCKNIX):

```c
static struct reg_data rk817_init_reg[] = {
    { RK817_BUCK4_CMIN,     0x60, 0x60 },   /* under-voltage protection only */
};
```

**Missing from upstream:**

| Register | Address | BSP value (mask) | What it does |
|----------|---------|-------------------|-------------|
| `RK817_PMIC_SYS_CFG1` | 0xf2 | 0x20 (0x70) | Hotdie threshold 105C, thermal shutdown 140C |
| **`RK817_PMIC_SYS_CFG3`** | **0xf4** | **0x00 (0x18)** | **Sets SLPPIN bits [3:4] to NULL_FUN (disabled)** |

The SYS_CFG3 write is critical: it puts the sleep pin into a **known clean
state** at boot, before anyone else (kernel, BL31) touches it.

### 16c. BSP U-Boot also handles `POWER_EN_SAVE`

BSP U-Boot conditionally writes `POWER_EN_SAVE0` / `POWER_EN_SAVE1`
(registers 0x99 / 0xa4) from the current `POWER_EN0–3` state. Stock DTS
has `not-save-power-en = <0x01>` which **skips** these writes.

Upstream U-Boot **always** writes them (no `not-save-power-en` support).
This means upstream U-Boot snapshots the enabled-regulator bitmask into
POWER_EN_SAVE on every boot. This may cause the PMIC to keep regulators
enabled across power-off events. Needs investigation.

### 16d. BSP kernel probe vs mainline kernel probe

**BSP kernel** (`rk808.c`) calls `rk817_of_property_prepare()` at probe:

1. Reads `pmic-reset-func` from DTS (stock: `<0>` = `RST_FUNC_DEV` = reset
   the whole device, not just registers).
2. Writes `RK817_SYS_CFG(3)`: `SLPPIN_NULL_FUN` + RST_FUNC.
3. Then `rk817_pre_init_reg[]` writes `SLPPOL_L` (bit 5) to `SYS_CFG(3)`.

Net boot-time writes to register **0xf4** (SYS_CFG3):

| Bits | BSP value | Meaning |
|------|-----------|---------|
| [3:4] SLPPIN_FUNC | `00` = NULL_FUN | Sleep pin has no function yet |
| [5] SLPPOL | `0` = LOW active | Sleep pin polarity |
| [6:7] RST_FUNC | `00` = RST_FUNC_DEV | Reset = full device reset |

**Mainline kernel** (`rk8xx-core.c`) at probe:

- `rk817_pre_init_reg[]` does **NOT** contain any `SYS_CFG(3)` entry.
- No `rk817_of_property_prepare()` equivalent.
- No `pmic-reset-func` handling.
- **Register 0xf4 is never written at boot.**

The only time mainline writes SYS_CFG(3) is during `rk8xx_shutdown()` (to
set SLPPIN_DN_FUN) and `rk808_power_off()` (to write DEV_OFF). By then the
PMIC's configuration may already be in a state that prevents deep-off.

### 16e. DTS regulator comparison — NOT the cause

Comprehensive side-by-side comparison of all PMIC regulators (DCDC_REG1-4,
LDO_REG1-9, BOOST, OTG_SWITCH), fixed regulators, CPU regulator, and
USB PHY supplies between ROCKNIX, stock source DTS, and decompiled stock
2025 firmware DTS shows:

- PMIC regulator configurations are **identical or ROCKNIX is more conservative**
  (fewer `regulator-always-on` / `regulator-boot-on` flags).
- Suspend-state (`regulator-state-mem`) configs are equivalent.
- Power-off state is determined by PMIC internal logic (controlled by
  SYS_CFG3), not by individual regulator DTS properties.

### 16f. `unused_pins_holder` — NOT the root cause

ROCKNIX DTS claims ~50 unused GPIO pins via `unused_pins_holder` with
explicit pull-up/pull-down resistors. Stock DTS leaves them **floating**.
ROCKNIX's approach is actually **better** for power (floating CMOS inputs
cause leakage current).

**Proof:** User's SPI-erase experiment shows 8 mA with no firmware
loaded — no kernel, no DTS, no pinctrl. The `unused_pins_holder` only
takes effect when the ROCKNIX kernel boots. Therefore it cannot be the
root cause of the 8 mA.

However, it is still worth testing without `unused_pins_holder` to rule out
any unexpected interaction (e.g., claiming a pin that conflicts with PMIC
operation). See §16h.

### 16g. SLPPOL-only patch — FAILED

Patch `0007-mfd-rk8xx-set-RK817-sleep-pin-polarity-low-at-probe.patch` was
created, adding to `rk817_pre_init_reg[]`:

```c
{RK817_SYS_CFG(3), RK817_SLPPOL_MSK, RK817_SLPPOL_L},
```

This changed SYS_CFG(3) from `0x20` → `0x00` (cleared bit 5 only).
**Result: no change — drain remains ~8 mA.** Patch deleted.

**Why it failed:** The patch only changed SLPPOL (polarity, bit 5) but
left SLPPIN_FUNC at its hardware default NULL_FUN (bits [3:4] = 00).
With SLPPIN_FUNC = NULL_FUN the sleep pin has *no function at all* — the
PMIC ignores it entirely, so polarity is irrelevant.

Stock `0xf4 = 0x18` decodes as:
- bits [3:4] = 11 → **SLPPIN_FUNC = RST_FUN** (sleep pin acts as reset)
- bit 5 = 0 → SLPPOL = LOW-active
- bits [6:7] = 00 → RST_FUNC = DEV (full device reset)

Our patch `0xf4 = 0x00` had:
- bits [3:4] = 00 → SLPPIN_FUNC = NULL_FUN (pin ignored) ← WRONG
- bit 5 = 0 → SLPPOL = LOW-active

The BSP kernel sets SLPPIN_FUNC = RST_FUN at probe via `rk817_pinctrl_init()`
(selects `pmic-reset` pinctrl state which calls `rk817_slppin_set(RST_FUN)`).
Without RST_FUN, the PMIC cannot detect the SoC's off state via GPIO0_PA2,
so it may stay in a shallow power-off mode.

Also deleted: CPU-regulator patch (0006, fan53555 shutdown reset) — not the
root cause.

### 16h. Ruled-out DTS suspects

- **combphy1/combphy2 disabled**: Already disabled by default in mainline
  `rk356x-base.dtsi`. They use `PD_PIPE` power domain which is not
  always-on. After SoC power-off, combo PHYs have no power regardless of
  DTS status. Stock enabling them has no effect on off-state current.
  **NOT the cause.**

- **vcc5v0_usb removed**: This was a virtual `regulator-fixed` node with
  no GPIO — just a supply-chain abstraction between dcdc_boost and
  vcc5v0_host. Removing it and feeding vcc5v0_host directly from
  dcdc_boost is functionally equivalent. **NOT the cause.**

- **vcc5v0_host not always-on**: GPIO4_PC5 controlled. After SoC power-off,
  GPIO4 power domain is dead. Pin state is determined by board design
  (external pulls), identical for stock and ROCKNIX. The `always-on`
  property only affects runtime. **NOT the cause for off-state drain.**

### 16i. RST_FUN at probe — BOOT LOOP

Patch `0007` v2 attempted to write RST_FUN + SLPPOL_L in
`rk817_pre_init_reg[]` (early in `rk8xx_probe()`), plus RST_FUN in
`rk8xx_shutdown()` and `rk8xx_resume()`.

**Result: boot loop.** The kernel starts, fan53555 regulator probes
(0x40), then the system immediately resets. The ON_SOURCE/OFF_SOURCE
log from the 0030 patch never appears, confirming the reset occurs
during `rk8xx_probe()` itself — when `rk817_pre_init_reg[]` writes
RST_FUN to `SYS_CFG(3)`.

**Root cause: GPIO0_PA2 pin function mismatch.**

Comparing the dump files for pin 2 (gpio0-2):
- **Stock**: `function pmic group soc_slppin_gpio` — GPIO mode (func 0),
  pin output 0, pull-down. BSP's `rk817_pinctrl_init()` drives the pin
  HIGH via GPIO API *before* writing RST_FUN, so the PMIC sees the
  inactive level and does not trigger.
- **ROCKNIX**: `function pmic group soc-slppin-slp` — PMU_SLEEP mode
  (func 1), no pull, no explicit output level. The PMU hardware may not
  drive this pin until later in boot; with `pcfg_pull_none` the pin
  floats. When RST_FUN + SLPPOL_L is written, the PMIC interprets the
  undefined/low level as "active" and immediately resets the SoC.

The BSP avoids this by using GPIO mode and controlling the pin level
programmatically through `rk817_pinctrl_init()` with multiple pinctrl
states (`soc_slppin_gpio`, `soc_slppin_slp`, `soc_slppin_rst`).
Mainline ROCKNIX only defines `soc_slppin_slp` (PMU_SLEEP).

### 16j. Patch 0007 v3 — shutdown/resume RST_FUN — FAILED

Patch v3 changed only shutdown (RST_FUN instead of DN_FUN) and
resume (RST_FUN instead of NULL_FUN), plus SLPPOL_L at probe.
No RST_FUN at probe.

**Result: same ~8 mA drain AND boot loop on power-cycle.**

Why RST_FUN at shutdown fails: `rk8xx_shutdown()` runs via
`device_driver.shutdown` BEFORE `rk808_power_off()` (which writes
DEV_OFF). So the sequence is:
1. `rk8xx_shutdown()` → writes RST_FUN to SYS_CFG(3)
2. `rk808_power_off()` → writes DEV_OFF (bit 0 of SYS_CFG(3))
3. PMIC starts powering off, SoC loses power
4. PMU_SLEEP pin level changes
5. PMIC sees pin change + RST_FUN → triggers RESET instead of
   completing power-off → system reboots

RST_FUN means "reset on pin change", not "power down on pin change".
It should only be active during NORMAL OPERATION (to detect SoC
crashes and auto-reset). DN_FUN is the correct function for the
shutdown path. Stock BSP never uses RST_FUN at shutdown — it uses
DN_FUN with a careful pinctrl transition.

**All 0007 patches deleted.**

### 16k. BSP pinctrl architecture (root cause analysis)

The BSP and mainline differ fundamentally in how they manage GPIO0_PA2:

**Stock BSP has 4 PMIC pinctrl states** (from decompiled DTS):
```
pinctrl-names = "default", "pmic-sleep", "pmic-power-off", "pmic-reset";
pinctrl-0 = <&soc_slppin_gpio>;                     // GPIO mode
pinctrl-1 = <&soc_slppin_slp &rk817_slppin_slp>;    // PMU_SLEEP + SLP_FUN
pinctrl-2 = <&soc_slppin_gpio &rk817_slppin_pwrdn>;  // GPIO + DN_FUN
pinctrl-3 = <&soc_slppin_gpio &rk817_slppin_rst>;    // GPIO + RST_FUN
```

Each state pairs a SoC-side pin mux with a PMIC-internal pinctrl entry
(via BSP's `pinctrl_rk8xx` driver that writes SLPPIN_FUNC register).

State transitions:
- **Boot**: default (GPIO mode, pin driven HIGH → PMIC ignores)
- **Active**: pmic-reset (GPIO mode + RST_FUN → auto-reset on SoC crash)
- **Suspend**: pmic-sleep (PMU_SLEEP mux + SLP_FUN → PMIC enters sleep)
- **Resume**: back to pmic-reset
- **Shutdown**: pmic-power-off (GPIO mode + DN_FUN → deep power-down)

BSP shutdown also: masks all PMIC interrupts (INT_STS_MSK_REG0-2 +
RTC alarm), NULL_FUN → SLPPOL_H → select power-off pinctrl → DN_FUN
→ 2ms sync delay. This careful sequence ensures deep off.

**ROCKNIX mainline has only 1 state**:
```
pinctrl-0 = <&soc_slppin_slp>;  // PMU_SLEEP mode, always
```
No PMIC-internal pinctrl driver. Only simple SLPPIN_FUNC register
writes in suspend/resume/shutdown (no pinctrl switching, no IRQ
masking, no sync delays).

### 16l. What's missing (ranked by likely impact)

1. **PMIC interrupt masking at shutdown**: BSP masks all PMIC IRQs
   before power-off. Unmasked interrupts (power key, battery events)
   could keep the PMIC partially awake in off-state.

2. **Pin function mismatch**: ROCKNIX keeps GPIO0_PA2 in PMU_SLEEP
   mode (func 1) permanently. Stock uses GPIO mode (func 0) by
   default and only switches to PMU_SLEEP for suspend. With PMU_SLEEP
   mode at shutdown, the pin level is controlled by SoC hardware,
   which may not transition cleanly during power-off, preventing
   DN_FUN from triggering deep off.

3. **Missing SLPPOL/sync dance**: BSP writes NULL_FUN → SLPPOL_H →
   reads SYS_STS → 2ms delay before setting DN_FUN. This ensures
   the PMIC's I2C interface synchronizes the state change. Mainline
   just writes DN_FUN directly.

4. **No RST_FUN during active state**: Without RST_FUN during normal
   operation, a hardware long-press power-off leaves SLPPIN_FUNC at
   NULL_FUN. The PMIC enters a shallow off state because it cannot
   detect the SoC's actual power state.

### 16m. I2C device comparison

Both stock and ROCKNIX see the same I2C devices:
- Bus 0: RK817 PMIC (0x20), RK860 CPU regulator (0x40)
- Bus 3: touch controller @ 0x3d (Hynitron CST3xx)

ROCKNIX disables i2c3 entirely (`status = "disabled"`). Stock has
it enabled and bound. The touch controller is unlikely to cause 8 mA
drain since it's powered from a regulator that can be disabled.
No unknown devices found.

### 16n. Test results — IRQ masking alone + soc_slppin_slp removal

1. **IRQ masking patch (old 0007)**: Added INT_STS_MSK_REG0-2 masking +
   RTC alarm disable + 2ms mdelay to `rk8xx_shutdown()`. No SLPPIN
   changes. Result: **still 8 mA**. IRQ masking alone is not sufficient.

2. **Removed soc_slppin_slp from pinctrl-0**: Changed PMIC `pinctrl-0`
   from `<&pmic_int>, <&i2s1m0_mclk>, <&soc_slppin_slp>` to just
   `<&pmic_int>, <&i2s1m0_mclk>`. Result: **still 8 mA**.

Neither individual fix reduces drain. The shutdown path needs the full
BSP pinctrl management to achieve 0.05 mA.

### 16o. Upstream RK3566 comparison

Every upstream RK3566/RK3568 board with RK817/RK809 uses the same
minimal approach: `pinctrl-0 = <&pmic_int>` (+ optional i2s1m0_mclk).
**None of them configure GPIO0_PA2 on the PMIC node.** Power-off is
purely DEV_OFF via `system-power-controller`. Only exception: PineNote
includes `pmic_sleep` in its pinctrl-0 (similar to our earlier config).

This confirms the Miyoo Flip's hardware requires active SLPPIN management
during shutdown that the generic mainline path doesn't provide.

### 16p. Full BSP pinctrl approach — enabled

**Approach**: Enable the 0029 patch (now renumbered as 0007) which
ports the full BSP shutdown/suspend/resume SLPPIN management. Wire up
all 4 DTS pinctrl states using SoC-side entries only (mainline has no
PMIC-internal pinctrl driver; the patch does register writes instead).

**Stock 4 states (decoded from phandles):**
```
pinctrl-0 = <pmic_int>;                              default
pinctrl-1 = <soc_slppin_slp  + rk817_slppin_slp>;    pmic-sleep
pinctrl-2 = <soc_slppin_gpio + rk817_slppin_pwrdn>;   pmic-power-off
pinctrl-3 = <soc_slppin_gpio + rk817_slppin_rst>;     pmic-reset
```

**ROCKNIX adaptation (SoC-side only):**
```
pinctrl-0 = <&pmic_int>, <&i2s1m0_mclk>;    default (IRQ + MCLK)
pinctrl-1 = <&soc_slppin_slp>;              pmic-sleep (PMU_SLEEP)
pinctrl-2 = <&soc_slppin_gpio>;             pmic-power-off (GPIO LOW)
pinctrl-3 = <&soc_slppin_gpio_idle>;        pmic-reset (GPIO pull-up)
```

Note: pinctrl-3 uses `soc_slppin_gpio_idle` (pull-up) instead of stock's
`soc_slppin_gpio` (output LOW) since after resume the PMIC has
SLPPIN_NULL (ignoring the pin), so pull-up is a safer idle state.

**Patch 0007 shutdown sequence:**
1. Mask all PMIC interrupts (INT_STS_MSK_REG0-2, RTC alarm)
2. SLPPIN = NULL_FUN (disarm pin)
3. SLPPOL = HIGH (high-active polarity)
4. Select pmic-power-off pinctrl → GPIO0_PA2 driven LOW
5. SLPPIN = DN_FUN (arm power-down on pin)
6. 2ms I2C sync delay
7. DEV_OFF (register power-off)

After DEV_OFF: SoC loses power, GPIO0_PA2 floats/pulled HIGH, PMIC
sees HIGH with SLPPOL_H + DN_FUN → stays in deep power-down.

---

## 17. Shutdown path ruled out — full PMIC register comparison (2026-04-04)

### 17a. Definitive test: manual BSP shutdown sequence via `i2cset`

The following commands were executed on ROCKNIX at runtime, replicating
the BSP kernel's exact PMIC shutdown sequence before calling `poweroff`:

```bash
# Mask all PMIC IRQs
i2cset -f -y 0 0x20 0xf8 0xff
i2cset -f -y 0 0x20 0xfb 0xff
i2cset -f -y 0 0x20 0xfd 0xff
# Disable RTC alarm IRQs
i2cset -f -y 0 0x20 0xd1 0x00
# NULL_FUN + SLPPOL_H
i2cset -f -y 0 0x20 0xf4 0x20
# DN_FUN + SLPPOL_H
i2cset -f -y 0 0x20 0xf4 0x30
sleep 0.1
poweroff
```

**Result: drain still ~8 mA.**

Post-boot register check:
- `ON_SOURCE (0xf5) = 0x80` → power-button / plug-in wake
- `OFF_SOURCE (0xf6) = 0x08` → bit 3 = **SLPPIN_DN** trigger

The PMIC **correctly received and acted on** the pin-based shutdown
signal. BL31 drove GPIO0_PA2 HIGH, the PMIC detected the transition
with DN_FUN + SLPPOL_H active, and powered off via the sleep pin.
Yet the off-state current remained at 8 mA.

**Conclusion: the shutdown path is NOT the root cause.** No
combination of SYS_CFG(3) writes at shutdown can fix the 8 mA drain.
The `0007` kernel patch (which modified `rk8xx_shutdown()` and
`rk808_power_off()`) was **deleted** — it addressed a non-existent
problem.

### 17b. Root-cause hypothesis update

The user's key observation: a hardware long-press (no kernel shutdown
code runs) after stock **boots** achieves 0.05 mA. This means:

1. Something stock configures **at boot time** persists in the PMIC's
   battery-backed (always-on) register domain through power-off.
2. This configuration affects how much current the PMIC (or its
   charger/gauge subsystem) draws in the off state.
3. ROCKNIX does not write these registers → hardware default → 8 mA.

### 17c. Full PMIC register comparison (stock vs ROCKNIX)

**Dumps used:**
- **Stock**: `i2cdump -f -y 0 0x20` on running stock firmware
  (file: `logs/Stock-dump.txt`, second clean dump at line 955)
- **ROCKNIX (new)**: `i2cget` loop on current ROCKNIX boot (inline)
- **ROCKNIX (old)**: `i2cdump` from earlier iteration (`logs/Rocknix-dump-Before-ChargerFIX.txt`)

**Total: 66 register differences, of which 21 are configuration registers.**

Excluding volatile registers (RTC time, ADC data, coulomb counter,
charger status, ON/OFF_SOURCE, interrupt status), the configuration
differences are:

| Reg | Stock | ROCKNIX | Name / Area | Notes |
|-----|-------|---------|-------------|-------|
| **0x55** | 0x80 | 0x30 | ADC/Gauge config | ADC_CONFIG area; unknown exact field |
| **0x92** | 0x25 | 0x1b | Gauge/BUCK config | Not in header; likely gas gauge calibration |
| **0x94** | 0x10 | 0x05 | Gauge/BUCK config | Same as above |
| **0x96** | 0xdb | 0xd0 | Gauge/BUCK config | Same as above |
| **0x98** | 0x25 | 0x1b | Gauge/BUCK config | Mirrors 0x92 |
| 0x9a | 0xa4 | 0x0e | SOC_REG0 (fuel gauge) | Battery SOC storage — volatile state |
| 0x9b | 0xb8 | 0xb3 | SOC_REG1 (fuel gauge) | Battery SOC storage — volatile state |
| 0x9d | 0x8a | 0x5f | Gauge config | Unknown |
| 0xb3 | 0x0f | 0x07 | POWER_EN_REG2 | LDO5-8 enable — kernel DTS driven |
| 0xb4 | 0x03 | 0x00 | POWER_EN_REG3 | LDO9/BOOST/OTG — kernel DTS driven |
| 0xb6 | 0x25 | 0x35 | POWER_SLP_EN_REG1 | LDO1-4 sleep enable — kernel driven |
| 0xbb | 0x1e | 0x20 | BUCK1_ON_VSEL | BUCK1 voltage — kernel DTS driven |
| 0xc6 | 0x6b | 0x64 | LDO voltage area | Between BUCK4 and LDO selectors |
| 0xd4 | 0x6c | 0x30 | LDO5_ON_VSEL | LDO5 voltage — kernel DTS driven |
| **0xe4** | **0xc1** | **0xb1** | **CHRG_OUT** | **Charger output config — see 17d** |
| **0xe5** | **0xd8** | **0xdb** | **CHRG_IN** | **USB input limits — see 17d** |
| **0xe6** | **0x42** | **0xc0** | **Charger ctrl** | **SYS_CAN_SD, USB_SYS_EN — see 17d** |
| **0xec** | **0x02** | **0x0a** | **Discharge config** | **BAT_DIS_ILIM — see 17d** |
| **0xf1** | **0xac** | **0x8c** | **SYS_CFG(0)** | **bit 5 differs — unknown function** |
| 0xf4 | 0x18 | 0x20 | SYS_CFG(3) SLPPIN | Already tested alone — not the fix |
| **0xfe** | **0x00** | **0x20** | **GPIO_INT_CFG** | **bit 5 differs** |

**Bold** = most promising candidates for off-state drain.
Non-bold = expected runtime differences (DTS-driven voltages, fuel gauge
state, regulator enables that reset on power-cycle).

### 17d. Charger register decode (from BSP `rk817_charger.c` reg_field map)

These registers are in the PMIC's charger subsystem, which is
**battery-powered** and operates independently of the SoC. They persist
through PMIC power-off and could draw current in the off state.

**0xE4 (RK817_CHRG_OUT):**

| Bit | Field | Stock (0xc1) | ROCKNIX (0xb1) |
|-----|-------|-------------|----------------|
| 7 | CHRG_EN | 1 (enabled) | 1 (enabled) |
| 6:4 | CHRG_VOL_SEL | 100 (4.2V?) | 011 (4.15V?) |
| 3 | CHRG_CT_EN | 0 | 0 |
| 2:0 | CHRG_CUR_SEL | 001 | 001 |

Difference: charge voltage selection. Both have charger enabled.

**0xE5 (RK817_CHRG_IN):**

| Bit | Field | Stock (0xd8) | ROCKNIX (0xdb) |
|-----|-------|-------------|----------------|
| 7 | USB_VLIM_EN | 1 | 1 |
| 6:4 | USB_VLIM_SEL | 101 | 101 |
| 3 | USB_ILIM_EN | 1 | 1 |
| 2:0 | USB_ILIM_SEL | 000 | 011 |

Difference: USB current limit selection. Minor.

**0xE6 (charger control):**

| Bit | Field | Stock (0x42) | ROCKNIX (0xc0) |
|-----|-------|-------------|----------------|
| 7 | **SYS_CAN_SD** | **0 (no)** | **1 (yes)** |
| 6 | USB_SYS_EN | 1 | 1 |
| 3 | BAT_OVP_EN | 0 | 0 |
| 2 | CHRG_TERM_ANA_DIG | 0 | 0 |
| 1:0 | CHRG_TERM_ANA_SEL | 10 | 00 |

**SYS_CAN_SD** controls whether the charger subsystem allows the system
power path to shut down. Stock = 0 (charger keeps system path alive??),
ROCKNIX = 1. Exact semantics unclear without datasheet.

**0xEC (discharge config):**

| Bit | Field | Stock (0x02) | ROCKNIX (0x0a) |
|-----|-------|-------------|----------------|
| 3 | BAT_DIS_ILIM_EN | 0 (disabled) | 1 (enabled) |
| 2:0 | BAT_DISCHRG_ILIM | 010 | 010 |

ROCKNIX has discharge current limiting enabled; stock does not.

### 17e. SYS_CFG(0) (0xf1) and GPIO_INT_CFG (0xfe)

**0xF1 — SYS_CFG(0):**
Stock = 0xac (1010_1100), ROCKNIX = 0x8c (1000_1100).
Difference: bit 5 (stock = 1, ROCKNIX = 0).

No BSP U-Boot or kernel code explicitly writes SYS_CFG(0). The
difference may come from BSP charger driver init, or the hardware
default differs from what mainline's probe sequence leaves it at.

**0xFE — GPIO_INT_CFG:**
Stock = 0x00, ROCKNIX = 0x20.
BSP kernel `rk817_pre_init_reg[]` writes `{GPIO_INT_CFG, 0x02, 0x02}`
(bit 1 = GPIO_INT_POL active-low). Stock shows 0x00 (bit 1 clear),
suggesting BSP's write was overridden or this dump was pre-probe.
ROCKNIX shows 0x20 (bit 5 set) — source unknown.

### 17f. Test plan — write stock values, measure drain

**Approach:** On a running ROCKNIX system, write all stock values for
the non-regulator persistent config registers that differ, then
`poweroff` and measure. If drain drops, binary-search to find which
register(s) matter.

**Group 1 — System config (safe, no crash risk):**
```bash
i2cset -f -y 0 0x20 0xf1 0xac   # SYS_CFG(0) bit 5
i2cset -f -y 0 0x20 0xfe 0x00   # GPIO_INT_CFG
```

**Group 2 — Charger config (safe, just charger params):**
```bash
i2cset -f -y 0 0x20 0xe4 0xc1   # CHRG_OUT (charge voltage)
i2cset -f -y 0 0x20 0xe5 0xd8   # CHRG_IN (USB limits)
i2cset -f -y 0 0x20 0xe6 0x42   # SYS_CAN_SD + term sel
i2cset -f -y 0 0x20 0xec 0x02   # discharge limit off
```

**Group 3 — ADC/Gauge config:**
```bash
i2cset -f -y 0 0x20 0x55 0x80   # ADC area config
```

**Skipped (unsafe or irrelevant):**
- 0xf4 (SYS_CFG3): already tested alone, RST_FUN dangerous without
  GPIO0_PA2 control → skip unless Groups 1-3 fail
- 0xbb, 0xc6, 0xd4 (regulator voltages): DTS-driven, changing could
  crash → skip
- 0xb3, 0xb4, 0xb6 (POWER_EN/SLP_EN): reset on power-cycle, won't
  persist → skip
- 0x9a-0x9d (SOC regs): fuel gauge state, not config → skip
- 0x92-0x98 (gauge calibration?): unknown risk → skip for now

**Test 1 — all groups combined:**
```bash
# Group 1: system config
i2cset -f -y 0 0x20 0xf1 0xac
i2cset -f -y 0 0x20 0xfe 0x00
# Group 2: charger
i2cset -f -y 0 0x20 0xe4 0xc1
i2cset -f -y 0 0x20 0xe5 0xd8
i2cset -f -y 0 0x20 0xe6 0x42
i2cset -f -y 0 0x20 0xec 0x02
# Group 3: gauge
i2cset -f -y 0 0x20 0x55 0x80
# Power off
poweroff
```

If 8 mA → add 0x92/0x94/0x96/0x98 in a second test.
If still 8 mA → the problem is outside the PMIC register set (board
hardware), or requires GPIO0_PA2 setup before writing RST_FUN to 0xf4.

---

## 18. Root cause identified — SYS_CAN_SD (one bit)

### 18a. Test results summary

| Test | Registers written | Charger? | Drain | Result |
|------|-------------------|----------|-------|--------|
| Test 1 (Groups 1+2+3) | 0xf1,0xfe,0xe4-0xe6,0xec,0x55 | No | 8 mA | FAIL |
| Test 1 + charger | same | Yes, then removed | 0.05 mA | PASS |
| Test A (charger only, no i2cset) | none | Yes, then removed | 8 mA | FAIL |
| Test B (0xe6 only + charger) | 0xe6 | Yes, then removed | 8 mA | FAIL |
| **Test C** (all + gauge) | 0xf1,0xfe,0xe4-0xe6,0xec,0x55,0x92,0x94,0x96,0x98 | No | **0.05 mA** | **PASS** |
| Test D (gauge only) | 0x92,0x94,0x96,0x98 | No | 8 mA | FAIL |
| Test E (gauge + ADC) | 0x55,0x92,0x94,0x96,0x98 | No | 8 mA | FAIL |
| **Test F** (charger group only) | 0xe4,0xe5,0xe6,0xec | No | **0.05 mA** | **PASS** |
| **Test G** (gauge reset + charger) | gauge→ROCKNIX, then 0xe4-0xe6,0xec→stock | No | **0.05 mA** | **PASS** |

Tests F/G appeared to show 4 charger registers were needed, but values
from earlier tests persisted in the battery-backed domain.

### 18b. Battery-disconnect isolation

Disconnecting the battery resets ALL PMIC registers to power-on-reset
(POR) defaults, removing any persisted state from prior tests.

| Test | After battery disconnect | Drain | Result |
|------|--------------------------|-------|--------|
| 0xe6+0xec only | `i2cset 0xe6 0x40; i2cset 0xec 0x02` | 8 mA | FAIL |
| + 0xf1 (Test I) | adds `i2cset 0xf1 0xac` | 0.05 mA | PASS |
| + 0xfe+0x55 (Test J) | adds `i2cset 0xfe 0x00; i2cset 0x55 0x80` | 0.05 mA | PASS |
| + 0xfe only (Test K) | adds `i2cset 0xfe 0x00` | 0.05 mA | PASS |
| + 0x55 only (Test L) | adds `i2cset 0x55 0x80` | 0.05 mA | PASS |
| + no-op write to 0xf1 (Test M) | adds `val=$(i2cget 0xf1); i2cset 0xf1 $val` | 0.05 mA | PASS |
| + i2cget 0xf1 only (Test N) | adds `i2cget 0xf1` | 0.05 mA | PASS |
| + no-op write to 0xe4 (Test O) | adds `val=$(i2cget 0xe4); i2cset 0xe4 $val` | 0.05 mA | PASS |

Tests M-O proved the "third register" was a red herring — ANY I2C bus
activity (even a read) after the 0xe6 write latches the configuration.
The two-command test failed because `poweroff` was the very next I2C
event and the shutdown path may race with the internal PMIC latch.

### 18c. Final isolation — single bit

| Test | After battery disconnect | Drain | Result |
|------|--------------------------|-------|--------|
| **Test P: 0xe6 only** | `i2cset 0xe6 0x40; i2cget 0xec` | **0.05 mA** | **PASS** |
| Test Q: 0xec only | `i2cset 0xec 0x02; i2cget 0xe6` | 8 mA | FAIL |
| **Test P inner: 0xe6 alone** | `i2cset 0xe6 0x40` | **0.05 mA** | **PASS** |

**Root cause: SYS_CAN_SD (bit 7 of register 0xe6) is the sole cause
of the ~8 mA off-state drain.**

BAT_DIS_ILIM_EN (0xec bit 3) is irrelevant.  All other register
differences (0xe4, 0xe5, 0xf1, 0xfe, 0x55, gauge) are irrelevant.

### 18d. BSP implementation

The BSP kernel (`rk3568_linux-rosa1337`) explicitly handles this:

```c
/* drivers/power/supply/rk817_charger.c (BSP) */
static void rk817_charge_sys_can_sd_disable(struct rk817_charger *charge)
{
    rk817_charge_field_write(charge, SYS_CAN_SD, DISABLE);
}

/* Called during rk817_charge_pre_init(): */
if (!charge->pdata->gate_function_disable)
    rk817_charge_sys_can_sd_disable(charge);
```

The DTS property `gate_function_disable` defaults to 0 (struct is
zero-initialized), so **the BSP unconditionally clears SYS_CAN_SD
unless a board explicitly opts out**.

The mainline `rk817_charger.c` driver has no equivalent — the bit is
never touched, leaving the PMIC hardware default (set) in place.

### 18e. Fix — kernel patch 0007

Patch: `0007-power-supply-rk817-disable-idle-charger-monitoring-f.patch`

Adds one `regmap_write_bits()` call to `rk817_battery_init()`:

```c
regmap_write_bits(rk808->regmap, RK817_PMIC_CHRG_TERM,
                  RK817_SYS_CAN_SD, 0);
```

Plus the `RK817_SYS_CAN_SD` define in `include/linux/mfd/rk808.h`.

This is a candidate for upstream submission — affects all RK817 boards,
not just Miyoo Flip.

