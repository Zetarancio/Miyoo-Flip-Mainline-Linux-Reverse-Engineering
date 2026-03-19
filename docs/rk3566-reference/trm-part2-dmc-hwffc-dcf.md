# RK3568 TRM Part 2 — DMC, HWFFC & DCF

## 1. DMC (Dynamic Memory Interface) - Chapter 1

### 1.1 Overview
The DMC includes an enhanced memory controller (UMCTL2) and DDR PHY, providing a complete memory interface solution. Key frequency-related features listed:

- **Support LPDDR4/LPDDR3 frequency change** (both types explicitly mentioned)
- Support auto gated clock through DDRC power interface
- Support auto PHY entry/exit self-refresh (lower power interface)
- Support auto issue entry/exit: clock stop, power down, self-refresh, deep power down, power saving mode
- Support auto control entry/exit retention self-refresh

### 1.2 Block Diagram
The DMC consists of:
- **AXI2HIF** - Port0 bus interface
- **DDRC** (UMCTL2) - Memory controller, issues read/write commands, DRAM page management, maintenance commands
- **DDR PHY** - Physical interface supporting LPDDR4/LPDDR3/DDR3/DDR3L/DDR4 SDRAM

---

## 2. HWFFC (Hardware Fast Frequency Change) - Section 1.3.4

This is the most critical section for DDR frequency scaling. The RK3568 has a dedicated **HWFFC hardware block** that implements the fast frequency change protocol.

### HWFFC Timing Procedure

The full frequency change sequence is:

1. **System requests frequency change** by asserting:
   - `csysreq_ddrc` 
   - `csysmode_ddrc`
   - `csysfrequency_ddrc` 
   - `csysdiscamdrain_ddrc`
   - These must remain at constant values while `csysreq_ddrc` is asserted
   - `csysreq_ddrc` must be held asserted until `csysack_ddrc` is asserted

2. **DDRC issues SDRAMs into Self-Refresh** (without power down), then sends several commands to update timing parameters for the opposite FSP side from current, lastly switches to opposite FSP side

3. **DDRC asserts `dfi_cke`** to put SDRAMs into Powerdown

4. **DDRC requests frequency change** by asserting:
   - `dfi_init_start`
   - `dfi_frequency` (frequency value indicated by `csysfrequency_ddrc`)
   - Holds during `dfi_init_start`

5. **PHY responds** to frequency change request by asserting `dfi_init_complete`

6. **DDRC asserts `cactive_ddrc`**, then asserts `csysack_ddrc` ("Frequency change request accepted")

7. **System changes clock frequency**

8. **System asserts `csysreq_ddrc`** (stable clock required here)

9. **DDRC asserts `dfi_init_start`** again, PHY acknowledges by asserting `dfi_init_complete`

10. **DDRC asserts `cactive_ddrc`**, then `dfi_cke` to exit Powerdown

11. **DDRC sends command to program VRCG** if required

12. **DDRC asserts `csysack_ddrc` / `cactive_ddrc`** - starts to behave normally again

13. **DDRC issues exit self-refresh**

The `csys*_ddrc` signals are controlled by the HWFFC block during frequency change. The clock frequency is controlled by the HWFFC block under software control.

---

## 3. HWFFC Registers (DDRC)

### DDRC_HWFFCCTL (Offset 0x4C from DDRC operational base)

| Field | Description |
|-------|-------------|
| `target_vrcg` | Target value of VRCG. Used when HWFFC request has been issued. Programming Mode: Static |
| `init_vrcg` | Initial value of VRCG. Used when HWFFCCTL hwffc_en has been changed. Programming Mode: Static |
| `init_fsp` | Initial value of FSP. Used when HWFFCCTL hwffc_en has been changed. Programming Mode: Static |
| `hwffc_en` | Enable HWFFC through Hardware Power Interface. 0 = Disable HWFFC, 1 = Enable HWFFC (allowed). Programming Mode: Dynamic |

### DDRC_HWFFCSTAT (Offset 0x50 from DDRC operational base)

| Field | Description |
|-------|-------------|
| `current_vrcg` | Indicates current value of VRCG. Dynamic |
| `current_fsp` | Indicates current value of FSP. Dynamic |
| `current_frequency` | Indicates current frequency. 0 = Normal frequency, 1 = Frequency FREQ1. Dynamic |
| `hwffc_operating_mode` | Operating mode of HWFFC: 0 = Normal, 1 = Self-Refresh, 2 = Powerdown. Dynamic |
| `hwffc_in_progress` | Indicates HWFFC is in progress. Dynamic |

---

## 4. HWFFC Block Registers (Separate from DDRC)

Section 1.4.5/1.4.6 describes a **separate HWFFC register block**:

### HWFFC_HWFFC_EN
| Field | Description |
|-------|-------------|
| `hwffc_en` | 0 = Disable HWFFC function, 1 = Enable HWFFC function. Must be configured last in the software operations sequence |

### HWFFC_HWFFC_MODE
| Field | Description |
|-------|-------------|
| `hwffc_mode` | Choose HWFFC mode. Three modes: |
| | **Auto mode** - Send HWFFC request to DDRC and switch clock automatically |
| | **Semi-auto mode** - Send HWFFC request to DDRC automatically, but clock switch handled by software |
| | **Mode 2** - Software controls sending request to DDRC and clock switch |

### HWFFC_HWFFC_CTRL
| Field | Description |
|-------|-------------|
| `hwffc_clk_switch_sw` | Hardware clk_switch value (when HWFFC_CTRL bit set) |
| `clk_switch_sw_en` | Hardware clk_switch value equals hwffc_clk_switch_sw |
| `clk_switch_semi_en` | Hardware clock switch enabled in semi-auto mode |
| `clk_switch_auto_en` | Hardware clock switch enabled in auto mode |
| `ignore_phy_ready` | 0 = Wait for PHY ready signal after clock switch, 1 = Do not wait for PHY ready signal when HWFFC |
| `hwffc_clk_switch_load` | Only used in auto/semi-auto mode. Initial value of switch signal |
| `hwffc_clk_switch_init` | Only used in auto/semi-auto mode. Load initial value of switch signal, which selects clock switch |
| `csysreq_ddrc_sw` | Only used in SW mode. Configure this to send csysreq_ddrc request to controller |
| `csysdiscamdrain_ddrc` | Disable draining. When asserted, Self-Refresh is entered without draining. Only effective when HWFFC is requested |
| `csysfrequency_ddrc` | Target frequency for DDRC Hardware Fast Frequency Change. Only effective when HWFFC is requested |
| `csysmode_ddrc` | Mode for DDRC HWFFC. 0 = Hardware Power requested, 1 = Hardware Fast Frequency Change requested |

### HWFFC_HWFFC_INT_STATUS
| Field | Description |
|-------|-------------|
| `csysack_ddrc` | DDRC Hardware Power Request Acknowledgement from DDRC |
| `cactive_ddrc` | Indicates that DDRC requires clock signal |
| `hwffc_done_int` | HWFFC done interrupt detected |
| `hwffc_clk_switch_int` | Clock switch interrupt detected |

### HWFFC_HWFFC_CNT
| Field | Description |
|-------|-------------|
| `hwffc_cnt` | Only used in auto mode. How many DDRC clock cycles to wait during switch (in case of PLL lock issue) |

### HWFFC_HWFFC_INT_EN
| Field | Description |
|-------|-------------|
| `hwffc_done_int_en` | Enable/disable HWFFC done interrupt |
| `hwffc_clk_switch_int_en` | Enable/disable HWFFC clock switch interrupt |

---

## 5. DFI Interface

### DFI Signals Used During Frequency Change

The following DFI signals are critical to the frequency change protocol:

- **`dfi_init_start`** - DDRC asserts this to request frequency change to PHY
- **`dfi_init_complete`** - PHY asserts this to acknowledge frequency change completion
- **`dfi_cke`** - DDRC controls CKE to put SDRAMs into/out of Powerdown
- **`dfi_frequency`** - Frequency value communicated to PHY during `dfi_init_start`

### DDRC_DFISTAT (register for polling DFI status)
| Field | Description |
|-------|-------------|
| `dfi_lp_ack` | Stores the value of dfi_lp_ack input to controller |
| `dfi_init_complete` | Status flag that announces when initialization has been completed. After INIT is triggered by dfi_init_start signal, the dfi_init_complete flag is polled to know when initialization is done |

### DDRC_DFIPHYMSTR
| Field | Description |
|-------|-------------|
| `dfi_phymstr_en` | Enables DFI PHY Master Interface. 0 = Disabled, 1 = Enabled |

### DFI DQ Remapping (Section 1.5)

RK3568 supports a remap feature from DFI DQ byte to SDRAM DQ byte. By default, DRAM DQ0 maps to DFI DQ0, etc. Software can reconfigure this via `DDR_GRF_CON3` before DRAM access.

### Other DFI-Related DDRC Registers:
- `DDRC_DFITMG0` / `DDRC_DFITMG1` - DFI timing parameters
- `DDRC_DFILPCFG0` / `DDRC_DFILPCFG1` - DFI low power configuration
- `DDRC_DFIUPD0` / `DDRC_DFIUPD1` / `DDRC_DFIUPD2` - DFI update control
- `DDRC_DFIMISC` - DFI miscellaneous control
- `DDRC_DBICTL` - DBI (Data Bus Inversion) control

---

## 6. DCF (DDR Converter of Frequency) - Chapter 2

### 2.1 Overview

The DCF is used to implement frequency conversion **without CPU participation**. It is connected through AXI Master/Slave interfaces with DMAC, and has an internal instruction buffer. Software pre-loads instruction sequences into SRAM, and when started, DCF automatically reads and executes them.

Key features:
- AXI/AMB compliant
- Support operation from SRAM buffer (burst only, LLP supported)
- Support internal instruction registers
- **Supported instruction set:** IDL (delay), LDR (read register), STR (write register), ISB (write with flush), Bitwise AND/OR/XOR, LSR/LSL (shift), ADD, SUB, POLLEQ (poll register until value match), POLLNEQ, CMPEQ, CMPNEQ, JMP (jump)
- Support program constructs: if/else, while, for loops

### 2.2 Block Diagram

Components:
- AXI Master Interface (to SRAM)
- AXI Slave Interface/Controller
- Instruction Buffer
- Instruction Analyzer

### 2.3 DCF Registers

| Register | Offset | Description |
|----------|--------|-------------|
| `DCF_CTRL` | | DCF Control Register (start bit, timeout_en, vop_hw_en) |
| `DCF_STATUS` | | DCF Internal Status (dma_done_st, instr_done_st, dma_error_st, instr_error_st, dcf_timeout_st, dcf_edge_trigger_st, dcf_level_trigger_st, dcf_idle_st) |
| `DCF_ADDR` | | Instruction Start Address Register |
| `DCF_ISR` | | DCF Interrupt Status Register (dcf_error, dcf_done) |
| `DCF_TIMEOUT_CYC` | | Instruction Timeout Cycle Register (default: 0xffffffff) |
| `DCF_CURR_R0` / `DCF_CURR_R1` | | Current Internal Value registers |
| `DCF_CMD_COUNTER` | | Current Command Counter Value |
| `DCF_LAST_ADDR0-3` | | Last Instruction Address registers |

### 2.4 DCF Work Flow

1. Software opens a separate space in SRAM and loads a series of instructions in advance
2. Instructions should consist of:
   - Configure MSCH idle
   - Configure Memory Controller to move into power State
   - Reset DDRPHY if needed
   - **Configure Clock frequency, wait PLL lock**
   - Configure Timing relative registers
   - Assert DDRPHY reset if needed
   - **Initialize DDRPHY calibration**
   - Configure Memory Controller to move into Access State
3. Software configures start_addr and starts DCF
4. DCF transfers instructions via DMA from SRAM to internal buffer
5. Instruction analysis module reads/executes instructions (write/read registers, delay, arithmetic operations)
6. DCF configures uPCTL and DDRPHY module to implement the frequency conversion procedure
7. DCF recognizes last command and generates `dcf_done` interrupt

### 2.4.2 Instruction Format

Each instruction consists of: Command + Address + Data (encoded as `cmd[4:0]`, `addr[26:2]`, `data`)

---

## 7. Frequency Set Points (FSP) - DDR PHY Section

### FSP Blocks (FSP_0, FSP_1, FSP_2, FSP_3)

The DDR PHY has **4 Frequency Set Points** (FSP_0 through FSP_3). These are used by the command bus training module to control command skew for different frequency groups.

### Key FSP Control Registers:

**`reg_freq_choose_t`** (DDRPHY register):
- Used for Fast Frequency Changing
- Valid only when `reg_freq_choose_bypass` is high
- Values: 0 = Freq Point 0, 1 = Freq Point 1, 2 = Freq Point 2, 3 = Freq Point 3
- In normal mode, current frequency point is indicated by `dfi_frequency[1:0]` during initialization / frequency change
- User can update registers for other frequency points, then use this register to switch training results to the target freq point **quickly**

**`reg_freq_choose_b`** (DDRPHY bypass):
- When active high: will use `reg_freq_choose_t` to choose freq point
- When low: will choose freq point based on `dfi_frequency` during initialization / fast frequency change

**`reg_tfc`**: Used to control the frequency set point switching time (T_FC) delay

### FSP and Command Bus Training Flow:
1. When auto command bus train is enabled, FSP_n will control command skew according to `reg_freq_choose[1:0]` automatically
2. After auto command train completes, the train values are **locked** in FSP_n module
3. User can then use `reg_freq_choose[1:0]` (REGC[3:2]) to **switch frequency quickly** between locked FSP values
4. User can also use register to update FSP_n lock value after command train

### Modulation CS-train mode:
After frequency changes from FSP[X] to FSP[Y], the CS-train operates at 100% pulse width. A modulation mode allows compensation of train results across frequency points.

---

## 8. DDR Monitor - DFI Statistics (Section 1.4.3/1.4.4)

The DDR Monitor block contains registers useful for bandwidth utilization monitoring and devfreq:

| Register | Description |
|----------|-------------|
| `DDRMON_DFI_ACT_NUM` | DFI Active Command Number |
| `DDRMON_DFI_WR_NUM` | DFI Write Command Number |
| `DDRMON_DFI_RD_NUM` | DFI Read Command Number |
| `DDRMON_COUNT_NUM` | Timer Count Number |
| `DDRMON_DFI_ACCESS_NUM` | Read + Write Command Number |
| `DDRMON_TIMER_COUNT` | Timer Threshold for statistics |
| `DDRMON_DFI_SREX_NUM` | Self-Refresh Exit Number |
| `DDRMON_DFI_PDEX_NUM` | Power Down Exit Number |
| `DDRMON_DFI_CLKSTOP` | Clock Stop Number |
| `DDRMON_DFI_LP_NUM` | DFI LP Number |
| `DDRMON_DFI_PHY_LP_NUM` | DFI PHY LP Number |
| `DDRMON_CTRL` | Control register (software_en, hardware_en, lpddr4 enable, timer_cnt_en, rank select) |
| `DDRMON_FLOOR_NUMBER` / `DDRMON_TOP_NUMBER` | Threshold comparison for bandwidth |

These DFI counters are what the Linux `rockchip_dfi` driver reads to calculate memory bandwidth utilization for the devfreq governor.

---

## 9. Self-Refresh State Register (DDRC_STAT)

The `selfref_state` field in `DDRC_STAT`:
- Indicates self-refresh or self-refresh power down state (for LPDDR)
- **This register is used for frequency change** - access during self-refresh
- Values: 0 = SDRAM Self-Refresh, 1 = Self-Refresh, 2 = Self-Refresh Power Down, 3 = Self-Refresh

The `selfref_type` field indicates whether self-refresh was entered under automatic control.

---

## 10. Power Control (DDRC_PWRCTL)

The `DDRC_PWRCTL` register controls the power state transitions including:
- `hw_lp_idle_x` - Hardware low power idle period. After DDRC command channel is idle for this many cycles, `cactive_ddrc` output is driven low
- Self-refresh control transitions between self-refresh state and self-refresh power down state

---

## Summary: DDR Frequency Change Architecture

The RK3568 has **two mechanisms** for DDR frequency change:

1. **HWFFC (Hardware Fast Frequency Change)** - A hardware block that orchestrates the frequency change through the DDRC's power interface signals (`csysreq_ddrc`, `csysmode_ddrc`, etc.). It has 3 modes: full auto, semi-auto, and software-controlled. The DDRC handles self-refresh entry/exit, FSP switching, and VRCG programming internally.

2. **DCF (DDR Converter of Frequency)** - A programmable sequencer that executes pre-loaded instructions from SRAM without CPU involvement. It directly programs DDRC and PHY registers to perform frequency conversion, including PLL reconfiguration, timing updates, and PHY calibration.

**Note:** SIP (Secure Interface Protocol) calls or SMC (Secure Monitor Call) are typically implemented in the ARM Trusted Firmware (ATF/BL31) which wraps these hardware mechanisms.
