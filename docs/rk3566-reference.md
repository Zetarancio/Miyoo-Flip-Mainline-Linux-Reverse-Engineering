# RK3566 / RK3568 SoC reference

Distro-agnostic hardware reference for the RK3566/RK3568 DDR memory subsystem, voltage domains, PLLs, and GPIO power-saving pins.

The RK3566 and RK3568 share an **identical DDR memory subsystem** (32-bit, same types/ranks/frequencies). Differences are GPU core count (1-Core-2EE vs 2-Core-2EE) and Ethernet (1 vs 2 GMAC). Any frequency differences come from the DDR init firmware, not hardware.

---

## Datasheet excerpts

Voltage domains (`VD_CORE`, `VD_LOGIC`, `VD_NPU`, `VD_GPU`, `VD_PMU`), DDR types (DDR3/DDR3L/DDR4/LPDDR3/LPDDR4/LPDDR4X up to 1056 MHz), DDR IO voltages and leakage, OPP validation, PLLs (9 total, DPLL for DDR), and non-DDR SoC specs.

**[Full datasheet specs →](rk3566-reference/datasheet-specs.md)**

---

## TRM Part 1 — DDR registers and DPLL

DDR controller block addresses (DDR_GRF, UPCTL2, DFICTRL, DFIMON, CRU), DPLL configuration registers and PLL frequency formula, DDR clock muxing/gating, DDR_GRF fields, PMU DDR power management (self-refresh, IO retention, DPLL power-down), and HWFFC controller clock enables.

**[Full TRM Part 1 →](rk3566-reference/trm-part1-registers-dpll.md)**

---

## TRM Part 2 — DMC, HWFFC, and DCF

DMC (UMCTL2 + PHY) overview, HWFFC hardware timing procedure (12-step frequency change), HWFFC registers (DDRC and standalone block), DFI interface signals, DCF programmable sequencer (instruction set and workflow), FSP blocks (4 frequency set points), DDR monitor/DFI statistics, and the two-mechanism architecture (HWFFC vs DCF).

**[Full TRM Part 2 →](rk3566-reference/trm-part2-dmc-hwffc-dcf.md)**

---

## Unused pins and power saving

Which GPIO pins can be put into a power-saving state (tied to a defined pull level) to reduce leakage current. Covers pull configuration rules per datasheet pad type, pin blocks safe to tie, pins that must NOT be tied, runtime verification, and a summary of safe vs in-use pins.

> **Note:** The pin tables below were modeled on the **Miyoo Flip** board. Other RK3566 devices in the same family share the same pad types but may use different pins for their peripherals. **Adapt the pin lists to your specific board** before applying unused-pin pinctrl groups.

**[Full unused pins guide →](rk3566-reference/unused-pins-power-saving.md)**

---

## External PDFs

See root [README.md](../README.md) → External references for links to the official RK3566 Datasheet and RK3568 TRM Part 1/Part 2 PDFs.
