# RK3566 Datasheet — DDR & Voltage Specs

Source: **Rockchip RK3566 Datasheet Rev 1.5** (2024-12-11)

---

## 1. SoC Overview

Quad-core ARM Cortex-A55 @ 1.8 GHz, Mali-G52 2EE @ 800 MHz, NPU @ 1.0 GHz.
Package: FCCSP565L (15.5 mm × 14.4 mm, 565 balls).

Five voltage domains: `VD_CORE`, `VD_LOGIC`, `VD_NPU`, `VD_GPU`, `VD_PMU`.
Fifteen individually gatable power domains.

---

## 2. Voltage Domains & Operating Conditions (Table 3-2)

| Rail | Symbol | Min | Typ | Max | Abs Max | Unit |
|------|--------|-----|-----|-----|---------|------|
| CPU core | VDD_CPU | 0.81 | 0.9 | — | 1.2 | V |
| GPU core | VDD_GPU | 0.81 | 0.9 | — | 1.2 | V |
| NPU core | VDD_NPU | 0.81 | 0.9 | — | 1.2 | V |
| **Core logic (DDR ctrl, VOP, …)** | **VDD_LOGIC** | **0.81** | **0.9** | **0.99** | **1.1** | **V** |
| PMU digital | PMU_VDD_LOGIC_0V9 | 0.81 | 0.9 | 0.99 | — | V |
| DDR PHY IO | DDRPHY_VDDQ | — | — | — | 1.65 | V |

Operating temperature: **0 … 80 °C** (T_A). Max junction: **125 °C**.

Thermal (4-layer PCB, T_A = 25 °C): θ_JA = 20.7 °C/W, θ_JC = 1.5 °C/W.

---

## 3. DDR Memory Interface

### 3.1 Supported Types

DDR3 / DDR3L / DDR4 / LPDDR3 / LPDDR4 / LPDDR4X (mutually exclusive, same pins).

### 3.2 Capabilities

- 32-bit data bus
- 2 ranks (DDR3/DDR3L/DDR4), 4 ranks (LPDDR3/4/4X)
- Max 8 GB addressing
- JEDEC-compatible up to **DDR3-2133 / LPDDR4-2133** (data rate)
  → max clock **1066 MHz** (actual PLL achieves **1056 MHz**)
- Low-power modes: power-down, self-refresh
- Programmable output impedance with dynamic PVT compensation
- DDR SDRAM data scrambling

### 3.3 Supported DDR Clock Frequencies (from rkbin tool)

RK3566 supports: **324, 396, 528, 630, 780, 920, 1056 MHz**.

The HWFFC mechanism uses up to 4 FSPs. Standard configuration for 1056 MHz boot:

| FSP | Frequency |
|-----|-----------|
| f1 (lowest) | 324 MHz |
| f2 | 528 MHz |
| f3 | 780 MHz |
| f0 (boot/max) | 1056 MHz |

### 3.4 DDR IO Voltages (Table 3-2)

| DDR Type | VDDQ (Min/Typ/Max) | VDDQL |
|----------|---------------------|-------|
| DDR3 | 1.425 / 1.5 / 1.575 V | Same as VDDQ |
| DDR3L | 1.283 / 1.35 / 1.417 V | Same as VDDQ |
| LPDDR3 | 0.994 / 1.2 / 1.3 V | Same as VDDQ |
| DDR4 | 0.994 / 1.2 / 1.3 V | Same as VDDQ |
| **LPDDR4** | **1.0 / 1.1 / 1.21 V** | **Same as VDDQ** |
| LPDDR4X | 1.0 / 1.1 / 1.21 V | **0.54 / 0.6 / 0.66 V** |

### 3.5 DDR IO DC Characteristics (Table 3-3)

All DDR modes: output impedance (Rtt) = **20 … 60 Ω**.
Input thresholds: Vih = Vref+0.1V, Vil = Vref−0.1V.

### 3.6 DDR IO Leakage (Table 3-8)

| Mode | Condition | Min | Max | Unit |
|------|-----------|-----|-----|------|
| DDR3 | @ 1.5 V, 125 °C | −80 | 6 | µA |
| DDR3L | @ 1.35 V, 125 °C | −65 | 5 | µA |
| DDR4 | @ 1.2 V, 125 °C | −50 | 4 | µA |
| LPDDR3 | @ 1.2 V, 125 °C | −50 | 4 | µA |
| **LPDDR4** | **@ 1.1 V, 125 °C** | **−45** | **3.5** | **µA** |
| LPDDR4X | @ 0.6 V, 125 °C | −20 | 1.5 | µA |

---

## 4. VDD_LOGIC Power Domain Detail

VDD_LOGIC powers: DDR controller, VOP2, interconnect, and other logic blocks.

- Operating: 0.81–0.99 V, typical 0.9 V
- Absolute max: 1.1 V
- **PD_CENTER** (within VD_LOGIC) contains: DDR_UMCTL, DDR_DFICTRL, DDR_MONITOR,
  DDR_SCRAMBLE, AXI_SPLIT, DDR_GRF, MSCH
- **DDRPHY** is in the **ALIVE** domain (always-on, not power-gated)

### VDD_LOGIC in Suspend — RESOLVED

vdd_logic is now set to `regulator-off-in-suspend` in the Miyoo Flip DTS, matching
stock firmware behavior. The `rk356x-suspend` driver (patch 1013) configures BL31
with `RKPM_SLP_ARMOFF_LOGOFF` so TF-A properly saves/restores the logic domain.

See `06-suspend-driver-and-vdd-logic.md` for details.

---

## 5. OPP Table Validation

| FSP | Freq (MHz) | Data Rate (MT/s) | VDD_LOGIC | DDRPHY_VDDQ (LPDDR4) | Source |
|-----|-----------|-------------------|-----------|----------------------|--------|
| f1 | 324 | 648 | 900 mV | 1.1 V | rkbin tool |
| f2 | 528 | 1056 | 900 mV | 1.1 V | rkbin tool |
| f3 | 780 | 1560 | 900 mV | 1.1 V | rkbin tool |
| f0 | 1056 | 2112 | 900 mV | 1.1 V | BSP rk3566.dtsi, datasheet |

VDD_LOGIC is flat 900 mV across all OPPs (frequency-only scaling) because:
- Shared rail with VOP2 and other logic blocks
- BSP uses `rockchip_monitor` for per-chip voltage binning (not available in mainline)
- Datasheet: VDD_LOGIC typical = 0.9 V, max = 0.99 V

DDRPHY_VDDQ is fixed at 1.1 V by board hardware (not software-controlled during DVFS).

---

## 6. PLLs

| Type | Fin | VCO Range | Fout Range | Lock Time |
|------|-----|-----------|------------|-----------|
| Frac PLL | 1–1200 MHz | 950–3800 MHz | 19–3800 MHz | ~250 ref cycles |
| Int PLL | 10–800 MHz | 475–1900 MHz | 9–1900 MHz | ~1000 ref cycles |

OSC input: **24 MHz**. 9 PLLs total in the SoC.
The DDR PLL (DPLL) derives DDR clocks. See `02-trm-part1-registers-and-dpll.md`.

---

## 7. DDR-Related Pin Details

| Pin | Name | Description |
|-----|------|-------------|
| 1D4 | DDR_AVSS | Analog ground for DDR |
| 1H3 | DDR_VREFOUT | DDR voltage reference output |
| 1F3 | DDR_RZQ | DDR reference impedance |
| 1D5–1G4 | DDRPHY_VDDQ | DDR PHY IO power (8 balls) |
| 1E6–1G5 | DDRPHY_VDDQL | DDR PHY IO power low-voltage (5 balls) |
| 1H7–1L7 | VDD_LOGIC | Core logic power (9 balls) |

---

## 8. RK3566 vs RK3568 DDR Differences

Based on datasheet comparison:
- DDR controller: identical (32-bit, same types, same ranks, same 8 GB)
- DDR PHY: identical voltages and impedance specs
- GPU: Mali-G52 **1-Core-2EE** (RK3568: **2-Core-2EE**)
- Ethernet: 1 GMAC (RK3568: 2)
- Package: same FCCSP565L

The DDR memory subsystem is **identical between RK3566 and RK3568**.
Any frequency differences come from the DDR init firmware, not hardware.

---

## 9. Relevant Non-DDR SoC Specs (for power analysis)

| Block | Key Specs |
|-------|-----------|
| CPU | 4× A55, 32KB L1I+L1D/core, 512KB shared L3, TrustZone |
| GPU | Mali-G52 2EE, 38.4 GFLOPS @ 800 MHz |
| NPU | 1 TOPS INT8 |
| I2C | ×6, up to 1 MHz (Fast-mode Plus) |
| UART | ×10, up to 4 Mbps |
| USB | 1× OTG, 2× Host 2.0, 1× Host 3.0 (shared w/ SATA via Multi-PHY) |
| Display | VOP2: 2 outputs, up to 4K60, MIPI DSI 2×4-lane, HDMI 2.0a |
| Audio | I2S ×4, TDM, PDM, SPDIF, VAD |
| On-chip mem | 32KB BootROM, 64KB SYSTEM_SRAM, 8KB PMU_SRAM |
