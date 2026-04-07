BL31 v1.45 — ROCKNIX rkbin
==========================

Source ELF:  rkbin commit 74213af1e952c4683d2e35952507133b61394862
             bin/rk35/rk3568_bl31_v1.45.elf
Origin:      https://github.com/rockchip-linux/rkbin (vendor ATF fork)
ATF version: v2.3-896-g70d3deb59
Build date:  Mar  4 2025
Size:        402,376 bytes
Builder:     huan.he (Rockchip engineer)

This is the BL31 used by ROCKNIX for all RK3566 devices (Miyoo Flip,
Powkiddy X55, Anbernic RG-DS, etc.).

Files
-----
bl31_v1.45_full.S           — Full disassembly (.text sections only)
bl31_v1.45_full_with_data.S — Full disassembly including data sections
bl31_v1.45_sections.txt     — ELF section headers
bl31_v1.45_symbols.txt      — Symbol table (stripped — minimal)
bl31_v1.45_strings.txt      — All printable strings
bl31_v1.45_readelf.txt      — Full readelf -a output

Differences from v1.44
----------------------
- 304 more lines of disassembly (31891 → 32195)
- 251 more Rockchip-internal ATF commits (645 → 896)
- Same binary size (402,376 bytes)
- Section 'ro' shrank from 0x29000 to 0x1a000 (code reorganization)
- .text_pmusram_reuse slightly smaller (0x1eec → 0x1e54)
- .data slightly larger (0x4f43 → 0x5103)
- String-identical for all power management messages
- Same function names in strings (suspend_mode_config, etc.)
- Both support virtual_poweroff, GPIO0 wakeup, PMIC_LP mode

Key functions to look for (same as v1.44)
-----------------------------------------
- "virtual_poweroff_en"     — virtual power-off SIP handler
- "suspend_mode_config"     — sleep-mode-config SIP handler
- "pmu_power_domain_ctr"    — power domain control
- "pmu_v0_sys_suspend_wfi"  — system suspend WFI entry
- "WAKEUP SOURCE"           — wakeup source reporting
- "rockchip_plat_sip_handler" — SIP call dispatcher
