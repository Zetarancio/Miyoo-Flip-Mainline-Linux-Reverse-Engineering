# BSP File Listing & DDR Findings

## Complete file listing

### `/home/ale/Downloads/Steward-fu-FLIP/docs` (9 files)
- `rocknix.md`
- `dts-porting.md`
- `display.md`
- `README.md`
- `troubleshooting.md`
- `drivers.md`
- `flashing.md`
- `building.md`
- `hardware.md`

### `/home/ale/Downloads/Steward-fu-FLIP/Extra` (9865+ files)
Notable directories:
- `miyoo-flip-main/` (U-Boot sources)
- `XROCK/` (xrock flashing tool)
- `flip-sysroot/` (stock system root)
- `rockchip/` (device tree files)
- `System.map-5.10` (kernel symbol map)
- `kernel_config` (kernel configuration)

---

## DDR/DMC/BL31/ATF/power management findings

### 1. DDR initialization and firmware

**DDR init binaries:**
- Referenced: `rk3566_ddr_1056MHz_v1.18.bin` (from rkbin)
- Usage: `xrock extra maskrom --rc4 off --sram rk3566_ddr_1056MHz_v1.18.bin --delay 10`
- Location: Expected in rkbin repository (not present in Extra/)

**USB plug handler:**
- Referenced: `rk356x_usbplug_v1.17.bin` (from rkbin)
- Usage: `xrock extra maskrom --rc4 off --dram rk356x_usbplug_v1.17.bin --delay 10`

**ROCKNIX DDR:**
- From `rocknix.md`: Boot log shows `DDR ... typ 24/09/03 fwver: v1.23` (ROCKNIX DDR from SD)

### 2. DMC (Dynamic Memory Controller) configuration

**Device tree (BSP):**
```dts
&dfi {
	status = "okay";
};

&dmc {
	center-supply = <&vdd_logic>;
	status = "okay";
};
```

**Kernel configuration:**
From `kernel_config`:
- `CONFIG_ARM_ROCKCHIP_DMC_DEVFREQ=y`
- `CONFIG_DEVFREQ_EVENT_ROCKCHIP_DFI=y`
- `CONFIG_ROCKCHIP_DDRCLK=y`
- `CONFIG_ROCKCHIP_DDRCLK_SIP=y`
- `CONFIG_ROCKCHIP_DDRCLK_SIP_V2=y`

**DMC devfreq functions (from System.map-5.10):**
- `rockchip_dmcfreq_get_cur_freq`
- `rockchip_dmcfreq_target`
- `rockchip_dmcfreq_wait_complete`
- `rockchip_dmcfreq_vop_bandwidth_request`
- `rk3568_dmc_init`
- `devfreq_dmc_ondemand_func`
- `rockchip_dfi_probe`
- `rockchip_dfi_enable`

**Mainline status:**
From `dts-porting.md`:
> "DMC/DFI -- DDR frequency scaling (closed-source dependencies)" - BSP-only

Note: An out-of-tree `rk3568_dmc.c` driver has been implemented for [ROCKNIX](https://rocknix.org/) ([Zetarancio/distribution](https://github.com/Zetarancio/distribution), branch `flip`), using the same V2 SIP + MCU/IRQ protocol as the BSP `rockchip_dmc.c`.

### 3. BL31 and ATF firmware

**ATF memory reservation (U-Boot):**
From `miyoo-flip-main/u-boot/arch/arm/mach-rockchip/board.c`:
```c
/* ATF */
mem = param_parse_atf_mem();
ret = bidram_reserve(MEM_ATF, mem.base, mem.size);
```

**Boot partition layout:**
From `flashing.md`:
- Preloader (0x0-0x200000): DDR init + SPL
- U-Boot (0x300000): U-Boot FIT (ATF + OP-TEE + U-Boot)

**GammaOS bootloader:**
From `rocknix.md`:
- Preloader: Updated DDR init + GammaOS SPL
- U-Boot: GammaOS U-Boot with ATF + OP-TEE

**BL31 binary reference:**
- Found: `miyoo-flip-main/rkbin/bin/rv11/rv1126_mcu.bin` (RV11, not RK3566)

### 4. Power management

**Regulators (DTS):**
- `vdd_logic`: DCDC_REG1 (500-1350mV, center-supply for DMC)
- `vcc_ddr`: DCDC_REG3 (always-on, regulator-on-in-suspend)
- `vdd_cpu_rk860`: RK8600 regulator (712.5-1390mV)

**Devfreq configuration:**
- GPU devfreq: `CONFIG_MALI_DEVFREQ=y`, `CONFIG_MALI_BIFROST_DEVFREQ=y`
- DMC devfreq: `CONFIG_ARM_ROCKCHIP_DMC_DEVFREQ=y`
- Bus devfreq: `CONFIG_ARM_ROCKCHIP_BUS_DEVFREQ=y`
- Governors: `CONFIG_DEVFREQ_GOV_SIMPLE_ONDEMAND=y`

**Power management notes:**
- GPU devfreq active (200-800 MHz) per `troubleshooting.md`
- Thermal integration: `CONFIG_DEVFREQ_THERMAL=y`
- Requires `CONFIG_ROCKCHIP_THERMAL=y` (built-in) for GPU devfreq

### 5. Device tree files

**BSP DTS:**
- `/home/ale/Downloads/Steward-fu-FLIP/Extra/rk3566-miyoo-355-v10-linux.dts`
- `/home/ale/Downloads/Steward-fu-FLIP/Extra/rockchip/rk3566-miyoo-355-v10-linux.dts`

**Key DTS nodes:**
```dts
&bus_npu {
	bus-supply = <&vdd_logic>;
	pvtm-supply = <&vdd_cpu_rk860>;
	status = "okay";
};

&dfi {
	status = "okay";
};

&dmc {
	center-supply = <&vdd_logic>;
	status = "okay";
};
```

### 6. Kernel configuration

**Relevant configs from `kernel_config`:**
```
CONFIG_ARM_ROCKCHIP_DMC_DEVFREQ=y
CONFIG_DEVFREQ_EVENT_ROCKCHIP_DFI=y
CONFIG_ROCKCHIP_DDRCLK=y
CONFIG_ROCKCHIP_DDRCLK_SIP=y
CONFIG_ROCKCHIP_DDRCLK_SIP_V2=y
CONFIG_PM_DEVFREQ=y
CONFIG_DEVFREQ_GOV_SIMPLE_ONDEMAND=y
CONFIG_DEVFREQ_THERMAL=y
CONFIG_MALI_DEVFREQ=y
CONFIG_MALI_BIFROST_DEVFREQ=y
```

### 7. Build scripts and references

**U-Boot build:**
- `miyoo-flip-main/README.md` mentions DDR init binaries
- U-Boot sources in `miyoo-flip-main/u-boot/` contain ATF memory reservation code

**Flashing scripts:**
- References to DDR init in `flashing.md` and `rocknix.md`
- xrock tool usage for loading DDR init binaries

---

## Summary

**DDR frequency scaling:**
- BSP kernel has DMC devfreq driver (`CONFIG_ARM_ROCKCHIP_DMC_DEVFREQ=y`)
- DFI (DDR Frequency Interface) event monitoring enabled
- DDRCLK SIP (Secure IP) support for frequency control
- Mainline: no equivalent (closed-source dependencies)

**DMC configuration:**
- DTS enables `&dfi` and `&dmc` nodes
- DMC uses `vdd_logic` as center-supply
- Multiple DMC init functions for different Rockchip SoCs

**BL31/ATF:**
- ATF memory reserved in U-Boot via `bidram_reserve(MEM_ATF, ...)`
- U-Boot FIT includes ATF + OP-TEE + U-Boot
- BL31 binaries expected from rkbin (not found in Extra/)

**Power management:**
- DDR power: `vcc_ddr` regulator (always-on, on in suspend)
- DMC power: `vdd_logic` as center-supply
- Devfreq governors: simple_ondemand for DMC and GPU
- Thermal integration for devfreq

**Firmware binaries:**
- DDR init: `rk3566_ddr_1056MHz_v1.18.bin` (referenced, not present)
- USB plug: `rk356x_usbplug_v1.17.bin` (referenced, not present)
- Found: `rv1126_mcu.bin` (RV11, not RK3566)

**Documentation:**
- `dts-porting.md`: notes DMC/DFI as BSP-only
- `flashing.md`: DDR init process for MASKROM mode
- `rocknix.md`: DDR init in bootloader chain
- `building.md`: mentions `make build-dmc` target (requires BSP headers)

The DMC/DDR frequency scaling functionality is present in the BSP kernel via
`rockchip_dmc.c` (CONFIG_ARM_ROCKCHIP_DMC_DEVFREQ). It uses the proprietary
BL31 SIP interface (V2 shared-memory protocol with MCU-based DCF completion).
An out-of-tree `rk3568_dmc.c` driver implementing the same protocol is available in [ROCKNIX](https://rocknix.org/) ([Zetarancio/distribution](https://github.com/Zetarancio/distribution), branch `flip`) for mainline kernel 6.18+.
