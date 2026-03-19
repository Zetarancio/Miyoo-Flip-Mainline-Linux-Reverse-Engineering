# RK3568 TRM Part 1 — DDR Registers & DPLL

### 1. SIP / SMC / BL31 / ATF / TF-A / SHARE_MEM

**Not found in this document.** The TRM Part 1 is a pure hardware register reference. It contains zero mentions of SIP function IDs, SMC calls, BL31, ATF, TF-A, trusted firmware, or shared memory interfaces. These are software-level abstractions documented in Rockchip's BL31/TF-A source code, not in the hardware TRM.

---

### 2. DDR-Related Hardware Blocks and Address Map

The following DDR subsystem peripherals are documented:

| Block | Base Address | Size | Description |
|---|---|---|---|
| **DDR_GRF** | `0xFDC40000` | 64KB | DDR General Register File |
| **DDR_SCRAMBLE_KEY** | `0xFDDC0000` | 64KB | DDR scramble key storage |
| **FIREWALL_DDR** | `0xFE200000` | 64KB | DDR firewall |
| **DMA2DDR** | `0xFE220000` | 64KB | DMA to DDR |
| **DFIMON** | `0xFE230000` | 64KB | DFI Monitor |
| **DFICTRL** | `0xFE240000` | 64KB | DFI Controller |
| **UPCTL2** | `0xFE250000` | 64KB | DDR Controller (Synopsys uPCTL2/UMCTL2) |
| **CRU** | `0xFDD20000` | 64KB | Clock Reset Unit (contains DPLL) |

---

### 3. DPLL (DDR PLL) Configuration - CRU Chapter

The DDR PLL (DPLL) is the primary clock source for DDR. Registers at CRU base `0xFDD20000`:

**CRU_DPLL_CON0** (offset `0x0020`):
- `fbdiv` [11:0]: Feedback Divide Value (16-2500 integer, 20-500 fractional)
- `postdiv1` [14:12]: First Post Divider (1-7)
- `bypass` [15]: PLL bypass (FREF bypasses PLL to FOUTPOSTDIV)

**CRU_DPLL_CON1** (offset `0x0024`):
- `refdiv` [5:0]: Reference Clock Divide Value (1-63)
- `postdiv2` [8:6]: Second Post Divider (1-7)
- `pll_lock` [10]: PLL lock status (0=Unlock, 1=Lock)
- `pllpd0` [13]: PLL power down request
- `pllpd1` [14]: PLL power down request
- `pllpdsel` [15]: PLL power down source selection

**CRU_DPLL_CON2** (offset `0x0028`):
- `fracdiv` [23:0]: Fractional feedback divide (fraction = FRAC/2^24)

**CRU_DPLL_CON3** (offset `0x002C`): Spread spectrum control (SSMOD)
**CRU_DPLL_CON4** (offset `0x0030`): Spread spectrum ext wave

**PLL frequency formula:**
- Integer mode: `FOUTVCO = FREF/REFDIV * FBDIV`, `FOUTPOSTDIV = FOUTVCO / POSTDIV1 / POSTDIV2`
- Fractional mode: `FOUTVCO = FREF/REFDIV * (FBDIV + FRAC/2^24)`

---

### 4. DDR Clock Muxing and Gating - CRU Chapter

**CRU_CLKSEL_CON09** (offset `0x0124`) - DDR PHY clock selection:
- `clk_ddrphy1x_sel` [15]: 0=clk_ddrphy1x_src, 1=clk_dpll_ddr
- `clk_ddrphy1x_src_sel` [7:6]: 00=clk_dpll_mux, 01=clk_gpll_mux, 10=clk_cpll_mux
- `clk_ddrphy1x_src_div` [4:0]: Divider (div_con + 1)

**CRU_MODE_CON** - DPLL mode:
- `clk_dpll_mode` [1:0]: 00=xin_osc0_func_mux (24MHz), 01=clk_dpll, 10=clk_rtc_32k

**CRU_MISC_CON0** (offset `0x00C4`):
- `hwffc_clk_switch2cru_ena` [13]: **DDR HWFFC (Hardware Fast Frequency Change) clock switch enable**

**DDR clock gating signals** (in CRU_GATE registers):
- `clk_hwffc_ctrl_en` - HWFFC controller clock
- `clk_ddrphy1x_en` - DDR PHY 1x source clock
- `clk_dpll_ddr_en` - DPLL DDR clock
- `clk_ddrdfi_ctl_en` - DDR DFI controller clock
- `aclk_ddrsplit_en` - DDR AXI split clock
- `clk_ddr_alwayson_en` - DDR always-on clock
- `clk_ddrmon_en` / `clk24_ddrmon_en` - DDR monitor clocks
- `aclk_msch_en` / `aclk_msch_div2_en` - Memory scheduler clocks
- `aclk_ddrscramble_en` - DDR scramble clock
- `clk_ddrphy_en` / `pclk_ddrphy_en` - DDR PHY clocks

---

### 5. DDR_GRF Registers (at `0xFDC40000`)

**Register summary:**
- `DDR_GRF_CON0` (0x0000): AXI poison/urgent, PA write/read mask, DFI init start, UPCTL slave error enable
- `DDR_GRF_CON1` (0x0004): DDRC auto self-refresh delay, DDR clock gating (PDSR, SYSREQ, self-refresh, core, APB, AXI)
- `DDR_GRF_CON2` (0x0008): DDRC LPI auto-gating, **DFI PHY Master CS State** control, DDR clock gate controls
- `DDR_GRF_CON3` (0x000C): DFI DQ swap controls
- `DDR_GRF_CON4` (0x0010): Additional DQ swap, DQ swap enable, csysreq_ddrc selection
- `DDR_GRF_SPLIT_CON` (0x0014): DDR AXI Split control
- `DDR_GRF_LP_CON` (0x0018): DDR PHY Low Power Control
- `DDR_GRF_STATUS0-STATUS12` (0x0020-0x004C): DDR status readback

Key field - **DFI PHY Master CS State** (`dfi_phymstr_cs_state`) in DDR_GRF_CON2:
> "DFI PHY Master CS State - Indicates the state of the DRAM when the PHY becomes the master"

---

### 6. PMU DDR Power Management Registers

These are critical for DDR self-refresh entry/exit during suspend/resume:

**PMU_DDR_PWR_CON** (offset `0x0034`):
- `ddr_sref_ena`: Enable DDR self-refresh by PMU
- `ddrio_ret_ena`: Enable DDR IO retention asserted by PMU
- `ddrphy_auto_gating_ena`: Enable DDR PHY auto clock gating by PMU when DDR enters self-refresh state

**PMU_DDR_PWR_SFTCON** (offset `0x0038`):
- `sw_ddr_sref_req`: DDR self-refresh request by software
- `sw_ddrio_ret_req`: DDR IO retention enter request by software
- `sw_ddrio_ret_exit`: DDR IO retention exit request by software
- `ddctl_active_wait`: DDR controller waits for c_active high after c_sysack high

**PMU_DDR_PWR_STATE** (offset `0x003C`):
- `ddr_power_state` - DDR power state machine:
  - `0x0`: Normal state
  - `0x1`: Self-refresh enter state
  - `0x2`: IO retention state
  - `0x3`: Sleep state
  - `0x4`: IO retention exit state
  - `0x5`: Self-refresh exit state

**PMU_DDR_PWR_ST** (offset `0x0040`):
- `ddrio_ret`: DDR IO retention active/inactive
- `ddctl_c_active`: DDR controller c_active state
- `ddctl_c_sysack`: DDR controller c_sysack state

---

### 7. PMU PLL Power Down (DPLL control during suspend)

**PMU_PLLPD_CON** (offset `0x00C0`) - PMU-managed PLL power down:
- `dpll_pd_ena`: **DPLL power down by PMU** (Enable/Disable)
- Also controls: apll, gpll, cpll, mpll, npll, hpll, ppll, vpll

**PMU_PLLPD_SFTCON** (offset `0x00C4`) - Software-triggered PLL power down:
- Same fields but triggered by software writes directly

---

### 8. HWFFC (Hardware Fast Frequency Change) Controller

The TRM documents a dedicated HWFFC controller block for DDR frequency switching:
- `clk_hwffc_ctrl_en` / `pclk_hwffc_ctrl_en`: Clock gating
- `resetn_hwffc_ctrl` / `presetn_hwffc_ctrl`: Reset controls
- `hwffc_clk_switch2cru_ena` in CRU_MISC_CON0: DDR HWFFC clock switch enable
- The HWFFC interrupt is interrupt #212

However, the **HWFFC controller's own register set is not documented** in this TRM Part 1.

---

### 9. Power Domain Partition for DDR

From the PMU chapter (Section 7.3.1):
- **PD_CENTER** power domain contains: DDR_UMCTL, DDR_DFICTRL, DDR_MONITOR, DDR_SCRAMBLE, AXI_SPLIT, DDR_GRF, MSCH
- DDR is in the **VD_LOGIC** voltage domain
- **DDRPHY** is in the **ALIVE** domain (always-on, not power-gated)

---

### 10. PMU Low Power Mode Operation Flow

From Section 7.3.2 and 7.6.1:
1. Software configures power settings in PMU registers
2. Set `PMU_PWR_CON[0]` to enable PMU FSM
3. All CPUs execute **WFI** (Wait For Interrupt)
4. PMU detects all CPUs in WFI, then FSM runs
5. In low power mode, PMU can automatically:
   - Put DDR into self-refresh
   - Assert DDR IO retention
   - Gate DDR PHY clock
   - Power down DPLL
6. Wakeup: reverse the sequence, exit self-refresh, re-lock DPLL

---

### Summary / Implications for DDR Frequency Scaling

1. **SIP function IDs** for DDR frequency change SMC calls
2. **The SHARE_MEM structure** used to pass DDR timing parameters between Linux and BL31
3. **The actual frequency change sequence** (put DRAM in self-refresh, switch clock, retrain PHY, exit self-refresh)
4. **The HWFFC controller register set** (not documented in this TRM)
5. **DDR PHY training register details** (likely in a separate PHY TRM)

The hardware building blocks identified here (DPLL reconfiguration, clock mux switching, PMU self-refresh control, HWFFC controller) are all orchestrated by BL31 firmware during a DDR frequency change, typically invoked via an SMC/SIP call from the Linux `rockchip-dmc` devfreq driver.
