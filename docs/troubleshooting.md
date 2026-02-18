# Troubleshooting

## Boot Hang: fan53555 / VDD_CPU (Kernel 6.4+)

**Symptom:** Hard hang immediately after:
```
fan53555-regulator 0-0040: FAN53555 Option[8] Rev[1] Detected!
```

**Cause:** BSP DTS uses `rockchip,suspend-voltage-selector` but mainline
driver reads `fcs,suspend-voltage-selector`. Wrong name causes wrong VSEL
register selection, dropping VDD_CPU.

**Fix (applied in our DTS):**
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

Re-enable after display issues are resolved. Use `initcall_debug` in
bootargs to find the exact hang point.

## No "VFS: Mounted root" (Kernel Never Reaches rootfs)

The kernel is stuck in an initcall before mounting root. Serial getty
cannot run because init never starts.

1. Add `initcall_debug loglevel=8` to DTS bootargs.
2. Rebuild: `make build-kernel && make boot-img`.
3. The last "calling initcall" line in serial output is the culprit.
4. Try `init=/bin/sh` -- if you get a shell, the hang is in init, not
   the kernel.

## No Login Prompt (Kernel Boots, No Shell)

1. Confirm rootfs was built with serial overlay (`rootfs-overlay-serial/`).
2. Rebuild rootfs: `make clean-rootfs && make build-rootfs && make rootfs-img`.
3. Flash **both** boot and rootfs partitions.
4. Look for `=== init: serial inittab active ===` in serial output.
5. Verify overlay is in image: `unsquashfs -d /tmp/rootfs output/rootfs.squashfs && cat /tmp/rootfs/etc/inittab`

## PMIC Dependency Cycles

**Symptom:** `fw_devlink: Fixed dependency cycle(s)` at boot.

Two cycles exist in the BSP DTS that `fw_devlink` (mainline) cannot
resolve:

| Cycle | BSP | Fix |
|-------|-----|-----|
| BOOST | `vcc9-supply = <&dcdc_boost>` | Use `<&vccsys>` |
| Pinctrl | `pinctrl-1/2/3` (sleep/reset states) | Only use `pinctrl-0 = <&pmic_int>` |

## Power/Battery Status

| Status | Item |
|--------|------|
| Fixed | HDMI/speaker supplies (no dummy regulators) |
| Fixed | PM: genpd disables unused power domains |
| Fixed | GPU power domain resolved (mali_kbase binds) |
| Fixed | GPU devfreq active (200-800 MHz) |
| Cosmetic | fan53555 ghost probe at 0x1c (TCS4525 not populated) |
| Low priority | VPU/RGA/VEPU sync_state pending (no drivers) |

## Remaining Boot Log Warnings

| Message | Impact |
|---------|--------|
| `rockchip-pm-domain: sync_state() pending due to video-codec/rga/vepu` | None. No userspace consumer; domains eventually powered down |
| `fan53555-regulator 0-001c: error -ENXIO: Failed to get chip ID!` | Cosmetic. TCS4525 at 0x1c not populated; RK8600 at 0x40 works |
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

The project targets **mainline Linux 6.19** (default branch: `linux-6.6.y` LTS).
The fan53555 VSEL bug affects all kernels **6.4+** and was the primary
blocker for mainlining. Earlier kernels (6.1, 6.3) do not have this bug
but lack other improvements.

Change kernel branch:
```bash
KERNEL_BRANCH=linux-6.12.y make download-kernel
KERNEL_BRANCH=latest make download-kernel
```
