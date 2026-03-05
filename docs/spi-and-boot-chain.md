# SPI Image Analysis & Boot Chain DDR Scaling Investigation

## Source
- SPI dump: project `Extra/` (e.g. `Extra/spi_*.img`, 128 MB)
- BSP U-Boot source: `Extra/miyoo-flip-main/u-boot/`
- Stock kernel DTB: `Extra/rockchip/rk3566-miyoo-355-v10-linux.dtb`

---

## 1. SPI Image Layout

| Region | SPI Offset | Size | Content |
|--------|-----------|------|---------|
| Preloader | 0x000000-0x200000 | 2 MB | IDBLOCK + DDR init blob (v1.18) + Stock SPL |
| U-Boot FIT | 0x300000+ | ~2 MB | FIT Image with ATF/OP-TEE/U-Boot/MCU |

### FIT Image Components (at 0x300000)

| Segment | Load Address | Size | Description |
|---------|-------------|------|-------------|
| uboot | 0x00a00000 | 1.3 MB | U-Boot proper |
| atf-1 | 0x00040000 | 164 KB | BL31 main code (TF-A v2.3-607-gbf602aff1) |
| atf-2 | 0xfdcc1000 | 40 KB | BL31 SRAM code (hardware registers) |
| atf-3 | 0x0006b000 | 20 KB | **SCMI clock configuration data** (NOT code) |
| atf-4 | 0xfdcce000 | 8 KB | BL31 SRAM code |
| atf-5 | 0xfdcd0000 | 8 KB | BL31 SRAM code |
| atf-6 | 0x00069000 | 8 KB | BL31 exception vectors |
| optee | - | ~450 KB | OP-TEE (BL32) |
| fdt | - | 14 KB | U-Boot device tree |

**Note:** Any U-Boot for this board must include OP-TEE (BL32) in the FIT image; the boot chain expects ATF + OP-TEE + U-Boot.

---

## 2. BL31 DDR-Related Strings (from atf-1)

Found at file offset 0x26xxx within atf-1 (runtime addresses 0x66xxx):

```
0x267af: "(ddr dmc_fsp already initialized in loader."
0x267dd: "dfs get fsp_param[%d] error, 0x%x != 0x%x"
0x26808: "(dfs DDR fsp_param[%d].freq_mhz= %dMHz"
0x26831: "loader&trust unmatch!!! Please update trust if need enable dmc"
0x26872: "loader&trust unmatch!!! Please update loader if need enable dmc"
0x26906: "ddr_fsp_init_params"
```

**Key insight:** BL31 checks if the DDR init blob (loader) version matches BL31 (trust).
If they match, it reads FSP params from the loader. If not, DMC is disabled.

---

## 3. ROCKNIX vs Stock BL31 Comparison

| Property | Stock BL31 | ROCKNIX BL31 (rkbin v1.44) |
|----------|-----------|---------------------------|
| TF-A version | v2.3-607-gbf602aff1 | v2.3-645-g8cea6ab0b |
| Rockchip version | Unknown | v1.44 |
| DMC FSP strings | All present | **Identical** |
| `clk_scmi_ddr` | Present | Present |
| DDR scaling SIP | Implemented | Implemented |

**Both BL31 binaries have identical DDR scaling capabilities.** They're from the same
Rockchip proprietary TF-A fork, just different commits.

---

## 4. SCMI Clock Configuration (atf-3 data blob)

The atf-3 segment contains SCMI clock descriptors (not ARM64 code):

| Entry | Name | SCMI Index | PLL Base | Notes |
|-------|------|-----------|----------|-------|
| 0 | clk_scmi_cpu | 0 | 0xFDD40000 | Has rate table, direct PLL control |
| 1 | clk_scmi_gpu | 1 | None | |
| 2 | clk_scmi_npu | 2 | None | |
| 3 | **clk_scmi_ddr** | **3** | **None** | No PLL base = needs special handler |

**DDR clock has no PLL register base**, confirming that SCMI `clk_set_rate` for DDR
cannot use direct PLL manipulation. DDR frequency changes require the HWFFC sequence,
which is only triggered via the V2 SIP shared-memory protocol (`SIP_DRAM_CONFIG`).

This explains why mainline SCMI `clk_set_rate(scmi_clk 3, rate)` is effectively
a no-op -- the SCMI agent doesn't know how to change DDR frequency via PLL registers.

### CPU Frequency Table (from atf-3)

216, 312, 408, 816, 1008, 1200, 1416, 1608, 1800, 1992 MHz

### GPU Frequency Table (from atf-3)

100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 1100, 1200 MHz

---

## 5. U-Boot `dmc_fsp` Driver Analysis

### Source: `drivers/ram/rockchip/dmc_fsp.c`

This driver binds to `compatible = "rockchip,rk3568-dmc-fsp"` and performs:
1. Checks ATF version >= 0x102 via `ROCKCHIP_SIP_CONFIG_DRAM_GET_VERSION`
2. Reads DRAM type from PMUGRF OS_REG2/OS_REG3
3. Parses `lpddr4_params` phandle from DTS for DDR timing parameters
4. Requests shared memory via `sip_smc_request_share_mem(N, SHARE_PAGE_TYPE_DDRFSP)`
5. Fills shared memory with timing/ODT/drive-strength parameters
6. Calls `sip_smc_dram(SHARE_PAGE_TYPE_DDRFSP, 0, ROCKCHIP_SIP_CONFIG_DRAM_FSP_INIT)`

### SIP Constants (from `rockchip_smccc.h`)

```c
SIP_DRAM_CONFIG          = 0x82000008
SIP_SHARE_MEM            = 0x82000009

// SIP_DRAM_CONFIG sub-commands:
DRAM_INIT                = 0x00
DRAM_SET_RATE            = 0x01
DRAM_ROUND_RATE          = 0x02
DRAM_SET_AT_SR           = 0x03
DRAM_GET_BW              = 0x04
DRAM_GET_RATE            = 0x05
DRAM_CLR_IRQ             = 0x06
DRAM_SET_PARAM           = 0x07
DRAM_GET_VERSION         = 0x08
DRAM_POST_SET_RATE       = 0x09
DRAM_SET_NOC_RL          = 0x0a
DRAM_DEBUG               = 0x0b
DRAM_MCU_START           = 0x0c
DRAM_ECC                 = 0x0d
DRAM_GET_FREQ_INFO       = 0x0e
DRAM_FSP_INIT            = 0x0f

// Share memory page types:
SHARE_PAGE_TYPE_INVALID  = 0
SHARE_PAGE_TYPE_UARTDBG  = 1
SHARE_PAGE_TYPE_DDR      = 2
SHARE_PAGE_TYPE_DDRDBG   = 3
SHARE_PAGE_TYPE_DDRECC   = 4
SHARE_PAGE_TYPE_DDRFSP   = 5
SHARE_PAGE_TYPE_DDR_ADDRMAP = 6
SHARE_PAGE_TYPE_LAST_LOG = 7
SHARE_PAGE_TYPE_HDCP     = 8
```

### CRITICAL: The `dmc_fsp` driver was NEVER PROBED on stock Miyoo Flip

The stock U-Boot DTB (extracted from the SPI FIT image) is a generic
"Rockchip RK3568 Evaluation Board" DTB with **no `dmc-fsp` node**.
Therefore the U-Boot `dmc_fsp` driver was compiled but never probed.

---

## 6. Stock Kernel DTB DDR Nodes

### `dmc` node

```
dmc {
    compatible = "rockchip,rk3568-dmc";
    interrupts = <0 10 4>;           // DCF completion IRQ (SPI #10)
    interrupt-names = "complete";
    devfreq-events = <&dfi0 &dfi1>;
    clocks = <&scmi_clk 3>;         // SCMI DDR clock (index 3)
    clock-names = "dmc_clk";
    operating-points-v2 = <&dmc_opp_table>;
    center-supply = <&vdd_logic>;
    auto-freq-en = <1>;
    auto-min-freq = <324000>;        // 324 MHz minimum
    upthreshold = <40>;
    downdifferential = <20>;
    status = "okay";
};
```

### `dmc-fsp` node (present but unused -- no matching U-Boot DTB node)

```
dmc-fsp {
    compatible = "rockchip,rk3568-dmc-fsp";
    debug_print_level = <0>;
    lpddr4_params = <&lpddr4_params_node>;
    lpddr4x_params = <&lpddr4x_params_node>;
    status = "okay";
};
```

### `dmc-opp-table`

Only ONE OPP entry in the stock DTB:

```
dmc-opp-table {
    compatible = "operating-points-v2";
    rockchip,max-volt = <1000000>;   // 1.0V max
    opp-1560000000 {
        opp-hz = <0 0x5cfbb600>;     // 1,560,000,000 Hz (780 MHz clock, DDR-1560)
        opp-microvolt = <900000 900000 1000000>;
    };
};
```

Note: Only one OPP is defined in the DTS, but BSP `auto-freq-en=1` with
`auto-min-freq=324000` means the BSP devfreq driver queries ATF via
`GET_FREQ_INFO` (0x0e) for the actual 4 FSPs (324/528/780/1056 MHz) and
dynamically adds/adjusts OPPs. The DTS entry is just a voltage reference.

### Stock LPDDR4 Timing Parameters

```
lpddr4-params {
    version = <0x100>;
    freq_0 = <1056>;    // 1056 MHz (boot/final)
    freq_1 = <324>;     // 324 MHz
    freq_2 = <528>;     // 528 MHz
    freq_3 = <780>;     // 780 MHz
    freq_4 = <0>;
    freq_5 = <0>;
    pd_idle = <13>;
    sr_idle = <93>;
    pd_dis_freq = <1066>;
    sr_dis_freq = <800>;
    dram_dll_dis_freq = <0>;
    phy_dll_dis_freq = <0>;
    // Drive strengths
    phy_dq_drv_odten = <30>;
    phy_ca_drv_odten = <38>;
    phy_clk_drv_odten = <38>;
    dram_dq_drv_odten = <40>;
    // ODT
    dram_odt = <80>;
    phy_odt = <60>;
    dram_dq_odt_en_freq = <800>;
    phy_odt_en_freq = <800>;
    // LP4 specific
    lp4_ca_odt = <120>;
    lp4_ca_odt_en_freq = <800>;
    lp4_odte_ck_en = <1>;
    lp4_odte_cs_en = <1>;
    byte_map = <0xe4>;
};
```

---

## 7. DDR Frequency Scaling Flow

```
DDR init blob (v1.18/v1.23)    BL31 (proprietary TF-A v1.44)
        |                              |
  1. Train PHY for 4 FSPs        2. Read FSP params from
     (1056, 324, 528, 780 MHz)      DDR blob shared data
        |                           "already initialized
        |                            in loader"
        v                              |
  Store training data                  v
  in BL31 memory               3. Expose V2 SIP interface
                                   (0x82000008/0x82000009)
                                       |
          U-Boot                       |
               |                       |
  NO dmc_fsp probe                     |
  (no DTS node in U-Boot DTB)         |
               |                       |
               v                       v
          Kernel                   BL31 handles
               |                  SIP_DRAM_CONFIG
  rk3568-dmc devfreq driver       SET_RATE via
  uses V2 SIP shared-memory       MCU + HWFFC
  protocol + MCU+IRQ completion
```

**Conclusion:** The U-Boot `dmc_fsp` driver is dead code for this device.
DDR scaling relies on: DDR init blob (trains FSPs) + BL31 (HWFFC via SIP) +
kernel `rk3568-dmc` devfreq driver (MCU+IRQ completion protocol).

### Mainline implementation

An out-of-tree driver implementing the BSP `rockchip_dmc.c` protocol exists for mainline kernel 6.18+ (V2 SIP shared-memory + MCU/IRQ completion).

**Runtime test results (when using that driver):**
- ATF version 0x102 detected, shared memory and completion IRQ registered
- All 4 FSPs available: 324, 528, 780, 1056 MHz
- `simple_ondemand` governor auto-scales based on DDR bandwidth
- Manual governor tests pass: powersave=324 MHz, performance=1056 MHz
- Transition stats confirm the device idles at 324 MHz with brief spikes during load

---

## 8. Preloader Zeroing: No Impact on DDR Scaling

When the preloader (sectors 0-4095) is zeroed on SPI NAND:
- Bootrom finds no valid IDBLOCK on SPI
- Falls through to SD card
- A full boot chain can be loaded from SD (e.g. DDR init blob v1.23, BL31 v1.44, mainline U-Boot with ATF + OP-TEE). DDR scaling works the same (BL31 + V2 SIP); U-Boot does not need dmc_fsp (same as stock behavior).

The stock SPI preloader is irrelevant when booting from SD.

---

## 9. Why Mainline SCMI `clk_set_rate` Is a No-Op for DDR

The SCMI clock data in BL31 shows `clk_scmi_ddr` has **no PLL register base**
(unlike CPU/GPU/NPU which have CRU register addresses). The SCMI agent handles
CPU/GPU/NPU by directly reprogramming PLL registers, but for DDR it cannot do
this because DDR frequency changes require the HWFFC hardware sequence.

The BSP kernel solves this by replacing the SCMI clock implementation with
`clk-ddr.c`, which bypasses SCMI and uses the V2 SIP shared-memory protocol
(`SIP_DRAM_CONFIG` 0x82000008) directly.

An out-of-tree DMC devfreq driver correctly implements this V2 protocol for mainline.

---

## 10. Stock DDR Frequency Scaling — Confirmed Working

The stock boot log (`boot_log_STOCK_INCLUDE_SLEEP_POWEROFF.txt` in this repo) confirms
DDR frequency scaling was active on the Miyoo Flip. For current mainline boot log see `boot_log_ROCKNIX.txt` in this repo.

### Stock Boot Log Evidence

```
[Line 143] INFO:    ddr dmc_fsp already initialized in loader.
```
BL31 reads FSP params trained by the DDR init blob (preloader/SPL).
The U-Boot `dmc_fsp.c` driver was not needed because the preloader
already did the initialization.

```
[4.996145] rockchip-dmc dmc: bin=0
[4.996200] rockchip-dmc dmc: leakage=60
[4.996467] rockchip-dmc dmc: current ATF version 0x102
[4.997027] rockchip-dmc dmc: normal_rate = 780000000
[4.997036] rockchip-dmc dmc: reboot_rate = 1056000000
[4.997042] rockchip-dmc dmc: suspend_rate = 324000000
[4.997060] rockchip-dmc dmc: boost_rate = 1056000000
[4.997065] rockchip-dmc dmc: fixed_rate(isp|cif0|cif1|dualview) = 1056000000
[4.997071] rockchip-dmc dmc: performance_rate = 1056000000
```
The `rockchip-dmc` devfreq driver probes successfully with multiple
rate profiles: idle at 324 MHz, normal at 780 MHz, boost at 1056 MHz.

Stock sleep/resume also works (lines 1343-1361), involving DDR
self-refresh and frequency transitions.

---

## 11. BSP Driver: `rockchip_dmc.c`

The BSP kernel tree at `linux-5.10.y-3b916183b...` is incomplete --
it does not include the main devfreq driver. The full 3500+ line
generic Rockchip DMC devfreq driver is at:

    https://github.com/rockchip-linux/kernel/blob/develop-5.10/drivers/devfreq/rockchip_dmc.c

Stock kernel config: `CONFIG_ARM_ROCKCHIP_DMC_DEVFREQ=y`

`System.map-5.10` confirms it is built-in with exported symbols:
`rockchip_dmcfreq_wait_complete`, `rockchip_dmcfreq_lock`,
`rockchip_dmcfreq_vop_bandwidth_request`, etc.

### `rk3568_dmc_init()` Sequence

```c
static int rk3568_dmc_init(struct platform_device *pdev,
                           struct rockchip_dmcfreq *dmcfreq)
{
    // 1. Check ATF version >= 0x101
    res = sip_smc_dram(0, 0, ROCKCHIP_SIP_CONFIG_DRAM_GET_VERSION);

    // 2. Request 2 pages of shared memory from ATF
    res = sip_smc_request_share_mem(2, SHARE_PAGE_TYPE_DDR);
    ddr_psci_param = (struct share_params *)res.a1;
    memset_io(ddr_psci_param, 0x0, 4096 * 2);

    // 3. Set MCU-based DCF mode
    wait_ctrl.dcf_en = 2;

    // 4. Register "complete" IRQ (GIC_SPI 10) with wait_dcf_complete_irq
    complt_irq = platform_get_irq_byname(pdev, "complete");
    devm_request_irq(&pdev->dev, complt_irq, wait_dcf_complete_irq, ...);
    disable_irq(complt_irq);

    // 5. Initialize DRAM scaling in ATF
    res = sip_smc_dram(SHARE_PAGE_TYPE_DDR, 0, ROCKCHIP_SIP_CONFIG_DRAM_INIT);

    // 6. Get supported frequencies from ATF
    rockchip_get_freq_info(dmcfreq);   // calls DRAM_GET_FREQ_INFO (0x0e)
    dmcfreq->is_set_rate_direct = true;

    return 0;
}
```

### Three-Step SET_RATE Protocol

The `-6` return from `SET_RATE` is expected (`SIP_RET_SET_RATE_TIMEOUT`).
It means "started, wait for MCU completion":

```c
static int rockchip_ddr_set_rate(unsigned long target_rate)
{
    ddr_psci_param->hz = target_rate;
    ddr_psci_param->lcdc_type = rk_drm_get_lcdc_type();
    ddr_psci_param->wait_flag1 = 1;
    ddr_psci_param->wait_flag0 = 1;

    // Step 1: Start frequency change (returns -6 = "wait for MCU")
    res = sip_smc_dram(SHARE_PAGE_TYPE_DDR, 0, ROCKCHIP_SIP_CONFIG_DRAM_SET_RATE);

    // Step 2: Complete via MCU + IRQ
    if ((int)res.a1 == SIP_RET_SET_RATE_TIMEOUT)
        rockchip_dmcfreq_wait_complete();

    return res.a0;
}

int rockchip_dmcfreq_wait_complete(void)
{
    wait_ctrl.wait_flag = -1;
    enable_irq(wait_ctrl.complt_irq);
    cpu_latency_qos_update_request(&pm_qos, 0);  // prevent deep CPU idle

    // Start MCU to perform the HWFFC
    sip_smc_dram(0, 0, ROCKCHIP_SIP_CONFIG_MCU_START);  // sub-cmd 0x0c

    // Wait up to 85ms for completion IRQ
    wait_event_timeout(wait_ctrl.wait_wq, (wait_ctrl.wait_flag == 0), 85ms);

    // If timeout, force cleanup
    if (wait_ctrl.wait_flag != 0)
        sip_smc_dram(SHARE_PAGE_TYPE_DDR, 0, ROCKCHIP_SIP_CONFIG_DRAM_POST_SET_RATE);

    disable_irq(wait_ctrl.complt_irq);
    return 0;
}

// IRQ handler: MCU completed the frequency change
static irqreturn_t wait_dcf_complete_irq(int irqno, void *dev_id)
{
    sip_smc_dram(SHARE_PAGE_TYPE_DDR, 0, ROCKCHIP_SIP_CONFIG_DRAM_POST_SET_RATE);
    ctrl->wait_flag = 0;
    wake_up(&ctrl->wait_wq);
    return IRQ_HANDLED;
}
```

### BSP `clk-ddr.c` V2 vs BSP `rockchip_dmc.c`

The `clk-ddr.c` file is a lower-level clock provider, not the devfreq driver.
Its `TODO: rockchip_dmcfreq_wait_complete()` calls the exported function
from `rockchip_dmc.c`.

When `is_set_rate_direct = true` (as for RK3568), the devfreq driver
calls `rockchip_ddr_set_rate()` directly, bypassing `clk-ddr.c` entirely.

### Stock DTS `dmc` Node (from `rk3568.dtsi`)

```dts
dmc: dmc {
    compatible = "rockchip,rk3568-dmc";
    interrupts = <GIC_SPI 10 IRQ_TYPE_LEVEL_HIGH>;
    interrupt-names = "complete";
    devfreq-events = <&dfi>, <&nocp_cpu>;
    clocks = <&scmi_clk 3>;
    clock-names = "dmc_clk";
    operating-points-v2 = <&dmc_opp_table>;
    auto-min-freq = <324000>;
    auto-freq-en = <1>;
    status = "disabled";
};
```

---

## 12. BL31 Variants Available

All same size: 402,376 bytes.

| Variant | File | Notes |
|---------|------|-------|
| Standard | rk3568_bl31_v1.44.elf | Currently used |
| Ultra | rk3568_bl31_ultra_v2.17.elf | Adds ddrdbg_* functions |
| RT | rk3568_bl31_rt_v1.02.elf | Real-time variant |
| CPU3 | rk3568_bl31_cpu3_v1.01.elf | 3-CPU variant |
| ECC | rk3568_bl31_l3_part_ecc_v1.00.elf | L3 cache ECC |
