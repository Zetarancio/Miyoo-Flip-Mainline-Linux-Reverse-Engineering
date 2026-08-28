# Troubleshooting

Distro-agnostic notes on boot failures, display hangs, and kernel debugging for the Miyoo Flip.

## Boot Hang: fan53555 / VDD_CPU (Kernel 6.4+)

**Symptom:** Hard hang immediately after:
```
fan53555-regulator 0-0040: FAN53555 Option[8] Rev[1] Detected!
```

**Cause:** BSP DTS uses `rockchip,suspend-voltage-selector` but mainline
driver reads `fcs,suspend-voltage-selector`. Wrong name causes wrong VSEL
register selection, dropping VDD_CPU.

**Fix (in mainline DTS):**
```dts
vdd_cpu_rk860: rk8600@40 {
    fcs,suspend-voltage-selector = <1>;  /* NOT rockchip,... */
};
```

**Diagnostic:** Add `initcall_blacklist=fan53555_regulator_driver_init` to
bootargs. If boot proceeds, this is the cause.

## Boot Hang: Display Pipeline

**Symptom:** Kernel stops during VOP/DSI/panel init. Last serial output
is an initcall related to display.

**Fix:** Disable display in DTS to reach root mount:
```dts
&vop { status = "disabled"; };
&vop_mmu { status = "disabled"; };
&dsi0 { status = "disabled"; };
&dsi_dphy0 { status = "disabled"; };
```



## PMIC Dependency Cycles

**Symptom:** `fw_devlink: Fixed dependency cycle(s)` at boot.

Two cycles exist in the BSP DTS that `fw_devlink` (mainline) cannot
resolve:

| Cycle | BSP | Fix |
|-------|-----|-----|
| BOOST | `vcc9-supply = <&dcdc_boost>` | Use `<&vccsys>` |
| Pinctrl | `pinctrl-1/2/3` (sleep/reset states) | Only use `pinctrl-0 = <&pmic_int>` |

## Power-off / battery drain (~8 mA while “off”) — fixed in kernel

**Symptom:** After `poweroff`, the battery still loses charge quickly (ammeter ~**8 mA** vs stock ~**0.05 mA**).

**Root cause (2026-04):** Bit **SYS_CAN_SD** (bit 7 of RK817 register **0xe6**, `CHRG_TERM`). The BSP charger driver clears it at probe; mainline `rk817_charger.c` did not, leaving the hardware default. With the bit set, the PMIC **charger monitoring block stays active** after system-off.

**Fix:** Kernel patch **`0007-power-supply-rk817-disable-idle-charger-monitoring-f.patch`** — clears `SYS_CAN_SD` during `rk817_battery_init()`. Landed as [560a99c](https://github.com/Zetarancio/distribution/commit/560a99cbe1d6b2a3760639ca0e8e730f101e9abb). **No DTS change is required** for this fix. Re-checked 2026-08-27 with the multiboot preloader restored: 0xe6 bit 7 clear on stock and ROCKNIX; **~20 h off, battery unchanged**.

**Full narrative:** [Power-off investigation](miyoo-flip-power-off-investigation.md) (lab notebook) and [2026-08-27 re-verification](miyoo-flip-power-off-investigation.md#re-verification-2026-08-27).

**If `poweroff` comes back on by itself:** that was an 8733bu **panic** (`ON_SOURCE = 0x02` = warm reboot), not a charger. Current `flip` has patches **003/004**. A real off is **`ON_SOURCE = 0x80`**. Gauge % after a long off is not an ammeter — the charger re-seeds OCV.

**Bluetooth scan empty in EmulationStation:** the agent died after the dbussy bump (`get_running_loop` NameError). Fixed by [86de663](https://github.com/Zetarancio/distribution/commit/86de6632e5) — pass an explicit event loop.

**Historical note (superseded for drain):** Earlier wiki text blamed **`system-power-controller`** / DEV_OFF “racing” PSCI for drain. The **~8 mA** leak is **SYS_CAN_SD**. Prefer **`ON_SOURCE`** over **`OFF_SOURCE`** when reading the old notebook.

## Power/Battery Status

| Status | Item |
|--------|------|
| Fixed | HDMI/speaker supplies (no dummy regulators) |
| Fixed | PM: genpd disables unused power domains |
| Fixed | GPU power domain resolved (mali_kbase binds) |
| Fixed | GPU devfreq active (200-800 MHz) |
| Historical | `fan53555-regulator` probe **-ENXIO** at `0x1c`. Only appeared while the DTS enabled both TCS4525 and RK8600 like stock. Current **`flip`** describes **RK8600 @ 0x40** only, so this should no longer be logged — see [I2C0 CPU regulator](drivers-and-dts/board-dts-pmic-ddr-updates.md#i2c0-cpu-regulator). |
| Low priority | VPU/RGA/VEPU sync_state pending until first use (mainline drivers: hantro-vpu, rockchip-rga) |

## Remaining Boot Log Warnings

| Message | Impact |
|---------|--------|
| `rockchip-pm-domain: sync_state() pending due to video-codec/rga/vepu` | Harmless. Mainline VPU/RGA drivers present; domains power down when idle; sync_state clears when a consumer opens the device |
| `fan53555-regulator 0-001c: error -ENXIO: Failed to get chip ID!` | **Only in older logs.** It came from the DTS describing both CPU regulators while only RK8600 is populated; the failed probe was ignored and VDD_CPU came up regardless. **`TCS4525 @ 0x1c`** has since been removed ([1f129e89df](https://github.com/Zetarancio/distribution/commit/1f129e89df)), so a current build should not log it. |
| `gpio gpiochip0: Static allocation of GPIO base is deprecated` | None. Upstream will fix |
| `Waiting for interface eth0... timeout!` | Harmless. No Ethernet on handheld |
| `seedrng: can't create directory: Read-only file system` | squashfs is read-only; use tmpfs overlay |
| `mali: error -ENXIO: IRQ JOB/MMU/GPU not found` | Harmless. Uppercase vs lowercase interrupt names; falls back |
| `fw_devlink: Fixed dependency cycle(s)` | Auto-resolved by kernel |

## GPU devfreq Disabled

**Symptom:**
```
Error -19 getting thermal zone 'gpu-thermal', not yet ready?
IPA initialization failed
Continuing without devfreq
```

**Cause:** `CONFIG_ROCKCHIP_THERMAL=m` (module). The tsadc driver hadn't
loaded when mali_kbase probed.

**Fix:** `CONFIG_ROCKCHIP_THERMAL=y` (built-in). Rebuild kernel.

## Debug Bootargs

Add these to DTS `chosen` bootargs for debugging:

| Bootarg | Effect |
|---------|--------|
| `initcall_debug` | Log every initcall; shows where boot stops |
| `loglevel=8` | Maximum kernel log verbosity |
| `regulator.debug=1` | Regulator enable/disable and voltage changes |
| `fw_devlink=permissive` | Relax dependency enforcement |
| `fw_devlink.sync_state=timeout` | Stop waiting for unbound consumers |
| `drm.debug=0x1ff` | Verbose DRM/display logging |
| `initcall_blacklist=<func>` | Skip a specific initcall |
| `init=/bin/sh` | Boot to single-user shell (bypass init) |

## Kernel Version Notes

The DTS targets **mainline Linux 7.0+** on current ROCKNIX `flip` builds (older notes used 6.18+). The fan53555 VSEL bug affects all kernels **6.4+** and was the primary blocker for mainlining. Earlier kernels (6.1, 6.3) do not have this bug but lack other improvements. Legacy build helpers live on branch `buildroot`.
