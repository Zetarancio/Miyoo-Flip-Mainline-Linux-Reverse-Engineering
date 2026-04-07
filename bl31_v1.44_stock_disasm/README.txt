BL31 v1.44 — Stock Miyoo Flip rkbin (Steward-fu repository)
===========================================================

Source ELF:  Extra/miyoo-flip-main/rkbin/bin/rk35/rk3568_bl31_v1.44.elf
Origin:      https://github.com/rockchip-linux/rkbin (vendor ATF fork)
ATF version: v2.3-645-g8cea6ab0b
Build date:  Sep 19 2023
Size:        402,376 bytes
SHA256:      65110f822fdbdd0163ce2dabc60591e7a8a0ffbc9471780e29eef0062f9ed7b6

NOTE: The actual stock Miyoo Flip device runs an OLDER build:
  v2.3-607-gbf602aff1, Built: Jun 5 2023
This v1.44 is what Steward-fu's rkbin snapshot contains for building
custom U-Boot images; the factory SPI flash has a slightly earlier blob.

Files
-----
bl31_v1.44_full.S           — Full disassembly (.text sections only)
bl31_v1.44_full_with_data.S — Full disassembly including data sections
bl31_v1.44_sections.txt     — ELF section headers
bl31_v1.44_symbols.txt      — Symbol table (stripped — minimal)
bl31_v1.44_strings.txt      — All printable strings
bl31_v1.44_readelf.txt      — Full readelf -a output

Key functions to look for (by string references)
-------------------------------------------------
- "virtual_poweroff_en"     — virtual power-off SIP handler
- "suspend_mode_config"     — sleep-mode-config SIP handler
- "pmu_power_domain_ctr"    — power domain control
- "pmu_v0_sys_suspend_wfi"  — system suspend WFI entry
- "WAKEUP SOURCE"           — wakeup source reporting
- "GPIO%dA%d" etc           — GPIO state logging
- "RKPM_SLP_PMIC_LP"        — PMIC low-power mode flag
- "rockchip_plat_sip_handler" — SIP call dispatcher

PMIC_SLEEP pin (GPIO0_PA2) constants from open-source TF-A pmu.h:
  PMIC_SLEEP_FUN       = 0x07000100  (mux to PMU_SLEEP)
  PMIC_SLEEP_GPIO      = 0x07000000  (mux to GPIO mode)
  PMIC_SLEEP_HIGH_LEVEL= 0x00040004  (GPIO output HIGH)
  PMU_GRF_GPIO0A_IOMUX_L = 0x00 offset from PMUGRF_BASE (0xfdc20000)
