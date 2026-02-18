// SPDX-License-Identifier: GPL-2.0-only
/*
 * RK3568/RK3566 DDR devfreq driver (out-of-tree module).
 *
 * DDR frequency scaling via the TF-A shared-memory SIP v2 interface.
 * Based directly on the BSP clk-ddr.c "rockchip_ddrclk_sip_ops_v2" and
 * the mainline rk3399_dmc.c devfreq pattern.
 *
 * The mainline kernel's clk-ddr.c only has SIP v1 (direct rate in SMC args,
 * used by RK3399).  RK3568/RK3566 use SIP v2 which writes the target rate
 * to a shared memory page before issuing the SMC.  Since mainline lacks v2,
 * this out-of-tree module handles the SIP calls directly.
 *
 * The in-kernel rockchip-dfi driver provides DDR bandwidth monitoring
 * (devfreq-event) for the simple_ondemand governor.
 *
 * Copyright (c) 2025
 * Based on: BSP drivers/clk/rockchip/clk-ddr.c (SIP v2 ops)
 *           BSP drivers/devfreq/rk3328_dmc.c
 *           mainline drivers/devfreq/rk3399_dmc.c
 */

#include <linux/arm-smccc.h>
#include <linux/clk.h>
#include <linux/delay.h>
#include <linux/devfreq.h>
#include <linux/devfreq-event.h>
#include <linux/kthread.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/pm_opp.h>
#include <linux/suspend.h>

#include <soc/rockchip/pm_domains.h>

/*
 * SIP (Secure Interface Protocol) constants — must match TF-A.
 * Values taken from the BSP include/soc/rockchip/rockchip_sip.h.
 */
#define ROCKCHIP_SIP_DRAM_FREQ			0x82000008
#define ROCKCHIP_SIP_SHARE_MEM			0x82000009

/* DRAM_FREQ sub-commands (a3 argument) */
#define ROCKCHIP_SIP_CONFIG_DRAM_INIT		0x00
#define ROCKCHIP_SIP_CONFIG_DRAM_SET_RATE	0x01
#define ROCKCHIP_SIP_CONFIG_DRAM_ROUND_RATE	0x02
#define ROCKCHIP_SIP_CONFIG_DRAM_SET_AT_SR	0x03
#define ROCKCHIP_SIP_CONFIG_DRAM_GET_VERSION	0x04
#define ROCKCHIP_SIP_CONFIG_DRAM_GET_RATE	0x05

/* Shared memory page types (passed to SHARE_MEM and DRAM_FREQ as a1) */
#define SHARE_PAGE_TYPE_DDR			2

/*
 * Shared memory page layout between kernel and TF-A (from BSP clk-ddr.c).
 * TF-A reads hz/lcdc_type/wait_flags before performing a DDR rate change.
 */
struct share_params {
	u32 hz;
	u32 lcdc_type;
	u32 vop;
	u32 vop_dclk_mode;
	u32 sr_idle_en;
	u32 addr_mcu_el3;
	u32 wait_flag1;
	u32 wait_flag0;
	u32 complt_hwirq;
};

struct rk3568_dmcfreq {
	struct device *dev;
	struct devfreq *devfreq;
	struct devfreq_dev_profile profile;
	struct devfreq_simple_ondemand_data ondemand_data;
	struct devfreq_event_dev *edev;
	struct mutex lock;

	struct share_params __iomem *params;
	phys_addr_t params_phys;
	unsigned long rate;		/* current DDR rate in Hz */
	bool can_scale;			/* true if SET_RATE is available */
};

/* ---- SIP helpers (matching BSP clk-ddr.c v2 exactly) ---- */

static int rk3568_dmc_alloc_share_page(struct rk3568_dmcfreq *dmcfreq)
{
	struct arm_smccc_res res;

	arm_smccc_smc(ROCKCHIP_SIP_SHARE_MEM,
		      1, SHARE_PAGE_TYPE_DDR, 0,
		      0, 0, 0, 0, &res);

	/* #region agent log */
	dev_info(dmcfreq->dev,
		 "[DBG] SHARE_MEM SMC: a0=0x%lx a1=0x%lx a2=0x%lx\n",
		 res.a0, res.a1, res.a2);
	/* #endregion */

	if (res.a0) {
		dev_warn(dmcfreq->dev,
			 "TF-A shared page alloc failed (0x%lx)\n", res.a0);
		return -ENODEV;
	}

	dmcfreq->params_phys = (phys_addr_t)res.a1;
	dmcfreq->params = ioremap(dmcfreq->params_phys, PAGE_SIZE);
	if (!dmcfreq->params) {
		dev_err(dmcfreq->dev, "Failed to ioremap shared page\n");
		return -ENOMEM;
	}

	dev_info(dmcfreq->dev, "TF-A shared page at phys %pa\n",
		 &dmcfreq->params_phys);
	return 0;
}

static int rk3568_dmc_dram_init(struct rk3568_dmcfreq *dmcfreq)
{
	struct arm_smccc_res res;

	/*
	 * BSP: sip_smc_dram(SHARE_PAGE_TYPE_DDR, 0, ROCKCHIP_SIP_CONFIG_DRAM_INIT)
	 * This tells TF-A to initialize its DDR DVFS state machine.
	 * Must be called before SET_RATE.
	 */
	arm_smccc_smc(ROCKCHIP_SIP_DRAM_FREQ,
		      SHARE_PAGE_TYPE_DDR, 0,
		      ROCKCHIP_SIP_CONFIG_DRAM_INIT,
		      0, 0, 0, 0, &res);

	/* #region agent log */
	dev_info(dmcfreq->dev,
		 "[DBG] DRAM_INIT SMC: a0=0x%lx a1=0x%lx\n",
		 res.a0, res.a1);
	/* #endregion */

	return (int)res.a0;
}

static unsigned long rk3568_dmc_get_rate(struct rk3568_dmcfreq *dmcfreq)
{
	struct arm_smccc_res res;

	arm_smccc_smc(ROCKCHIP_SIP_DRAM_FREQ,
		      SHARE_PAGE_TYPE_DDR, 0,
		      ROCKCHIP_SIP_CONFIG_DRAM_GET_RATE,
		      0, 0, 0, 0, &res);

	if (!res.a0)
		return (unsigned long)res.a1;
	return 0;
}

static long rk3568_dmc_round_rate(struct rk3568_dmcfreq *dmcfreq,
				  unsigned long rate)
{
	struct arm_smccc_res res;

	if (!dmcfreq->params)
		return 0;

	writel((u32)rate, &dmcfreq->params->hz);

	arm_smccc_smc(ROCKCHIP_SIP_DRAM_FREQ,
		      SHARE_PAGE_TYPE_DDR, 0,
		      ROCKCHIP_SIP_CONFIG_DRAM_ROUND_RATE,
		      0, 0, 0, 0, &res);

	if (!res.a0)
		return (long)res.a1;
	return 0;
}

static int rk3568_dmc_set_rate(struct rk3568_dmcfreq *dmcfreq,
			       unsigned long rate_hz)
{
	struct arm_smccc_res res;

	if (!dmcfreq->params)
		return -ENODEV;

	/*
	 * BSP clk-ddr.c v2 SET_RATE sequence:
	 * - hz = target rate
	 * - lcdc_type = 0 (SCREEN_NULL)
	 * - wait_flag1 = 0, wait_flag0 = 0:
	 *   Tell TF-A NOT to wait for VOP vblank synchronization.
	 *   The BSP sets these to 1 because it has the full VOP driver
	 *   signaling vblank readiness to TF-A.  In mainline, without
	 *   that signaling, TF-A times out (-6) waiting for VOP.
	 *   Setting to 0 = perform rate change immediately (may cause
	 *   brief display glitch during transition, but won't timeout).
	 */
	writel((u32)rate_hz, &dmcfreq->params->hz);
	writel(0, &dmcfreq->params->lcdc_type);
	writel(0, &dmcfreq->params->wait_flag1);
	writel(0, &dmcfreq->params->wait_flag0);

	arm_smccc_smc(ROCKCHIP_SIP_DRAM_FREQ,
		      SHARE_PAGE_TYPE_DDR, 0,
		      ROCKCHIP_SIP_CONFIG_DRAM_SET_RATE,
		      0, 0, 0, 0, &res);

	/* #region agent log */
	dev_info(dmcfreq->dev,
		 "[DBG] SET_RATE(%lu): a0=0x%lx a1=0x%lx\n",
		 rate_hz, res.a0, res.a1);
	/* #endregion */

	if ((int)res.a1 == -6)
		dev_err(dmcfreq->dev, "SET_RATE timeout for %lu Hz\n", rate_hz);

	return (int)res.a0;
}

/* ---- devfreq callbacks ---- */

static int rk3568_dmcfreq_target(struct device *dev, unsigned long *freq,
				 u32 flags)
{
	struct rk3568_dmcfreq *dmcfreq = dev_get_drvdata(dev);
	struct dev_pm_opp *opp;
	unsigned long old_rate, target_rate, new_rate;
	int err;

	if (!dmcfreq->can_scale) {
		*freq = dmcfreq->rate;
		return 0;
	}

	opp = devfreq_recommended_opp(dev, freq, flags);
	if (IS_ERR(opp))
		return PTR_ERR(opp);

	target_rate = dev_pm_opp_get_freq(opp);
	dev_pm_opp_put(opp);

	if (dmcfreq->rate == target_rate)
		return 0;

	mutex_lock(&dmcfreq->lock);

	old_rate = dmcfreq->rate;

	/* Validate with TF-A before committing */
	{
		long rounded = rk3568_dmc_round_rate(dmcfreq, target_rate);
		if (rounded != (long)target_rate) {
			dev_dbg(dev, "ROUND_RATE rejected %lu Hz\n",
				target_rate);
			err = -EINVAL;
			goto out_unlock;
		}
	}

	err = rockchip_pmu_block();
	if (err) {
		dev_err(dev, "Failed to block PMU: %d\n", err);
		goto out_unlock;
	}

	err = rk3568_dmc_set_rate(dmcfreq, target_rate);
	if (err) {
		dev_err(dev, "SET_RATE(%lu) failed: %d\n", target_rate, err);
		goto out_pmu;
	}

	/* Read back actual rate to confirm the change */
	new_rate = rk3568_dmc_get_rate(dmcfreq);
	if (new_rate)
		dmcfreq->rate = new_rate;

	/* #region agent log */
	if (dmcfreq->rate != old_rate)
		dev_info(dev, "[DBG] DDR rate changed: %lu -> %lu MHz\n",
			 old_rate / 1000000, dmcfreq->rate / 1000000);
	/* #endregion */

	/*
	 * If SET_RATE returned success but the rate didn't change,
	 * disable scaling to avoid spamming TF-A every poll cycle.
	 */
	if (dmcfreq->rate == old_rate && target_rate != old_rate) {
		dev_warn(dev,
			 "SET_RATE succeeded but rate unchanged (%lu MHz). "
			 "Disabling scaling.\n", old_rate / 1000000);
		dmcfreq->can_scale = false;
	}

out_pmu:
	rockchip_pmu_unblock();
out_unlock:
	mutex_unlock(&dmcfreq->lock);
	return err;
}

static int rk3568_dmcfreq_get_dev_status(struct device *dev,
					 struct devfreq_dev_status *stat)
{
	struct rk3568_dmcfreq *dmcfreq = dev_get_drvdata(dev);
	struct devfreq_event_data edata;
	int ret;

	ret = devfreq_event_get_event(dmcfreq->edev, &edata);
	if (ret < 0)
		return ret;

	stat->current_frequency = dmcfreq->rate;
	stat->busy_time = edata.load_count;
	stat->total_time = edata.total_count;

	return 0;
}

static int rk3568_dmcfreq_get_cur_freq(struct device *dev,
				       unsigned long *freq)
{
	struct rk3568_dmcfreq *dmcfreq = dev_get_drvdata(dev);

	*freq = dmcfreq->rate;
	return 0;
}

static int rk3568_dmcfreq_suspend(struct device *dev)
{
	struct rk3568_dmcfreq *dmcfreq = dev_get_drvdata(dev);
	int ret;

	ret = devfreq_event_disable_edev(dmcfreq->edev);
	if (ret < 0)
		return ret;

	return devfreq_suspend_device(dmcfreq->devfreq);
}

static int rk3568_dmcfreq_resume(struct device *dev)
{
	struct rk3568_dmcfreq *dmcfreq = dev_get_drvdata(dev);
	int ret;

	ret = devfreq_event_enable_edev(dmcfreq->edev);
	if (ret < 0)
		return ret;

	return devfreq_resume_device(dmcfreq->devfreq);
}

static SIMPLE_DEV_PM_OPS(rk3568_dmcfreq_pm, rk3568_dmcfreq_suspend,
			 rk3568_dmcfreq_resume);

/* #region agent log — VOP signal simulation for DDR DFS debug */
static volatile int vop_sim_active;
static struct share_params __iomem *vop_sim_p;

static int vop_sim_thread_fn(void *data)
{
	udelay(100);
	while (READ_ONCE(vop_sim_active)) {
		writel(0, &vop_sim_p->wait_flag1);
		writel(0, &vop_sim_p->wait_flag0);
		udelay(50);
	}
	return 0;
}
/* #endregion */

/* ---- probe ---- */

static int rk3568_dmcfreq_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct rk3568_dmcfreq *data;
	struct dev_pm_opp *opp;
	unsigned long freq;
	int ret;

	data = devm_kzalloc(dev, sizeof(*data), GFP_KERNEL);
	if (!data)
		return -ENOMEM;

	data->dev = dev;
	mutex_init(&data->lock);

	/* Get DFI event device for bandwidth monitoring */
	data->edev = devfreq_event_get_edev_by_phandle(dev,
							"devfreq-events", 0);
	if (IS_ERR(data->edev))
		return dev_err_probe(dev, PTR_ERR(data->edev),
				     "Cannot get devfreq-event device (DFI)\n");

	ret = devfreq_event_enable_edev(data->edev);
	if (ret < 0) {
		dev_err(dev, "Failed to enable devfreq-event\n");
		return ret;
	}

	/* Step 1: Allocate TF-A shared memory page */
	ret = rk3568_dmc_alloc_share_page(data);
	if (ret) {
		dev_warn(dev, "Shared page alloc failed, monitor-only mode\n");
		goto monitor_only;
	}

	/* #region agent log — H2: check GET_VERSION */
	{
		struct arm_smccc_res vres;

		arm_smccc_smc(ROCKCHIP_SIP_DRAM_FREQ,
			      0, 0, ROCKCHIP_SIP_CONFIG_DRAM_GET_VERSION,
			      0, 0, 0, 0, &vres);
		dev_info(dev, "[DBG] GET_VERSION: a0=0x%lx a1=0x%lx (ver=0x%lx)\n",
			 vres.a0, vres.a1, vres.a1);
	}
	/* #endregion */

	/*
	 * Step 2: Skip DRAM_INIT.
	 * Hypothesis H1: on RK3568, the BSP clock driver (clk-ddr.c)
	 * never calls DRAM_INIT — only the old RK3328 DMC driver does.
	 * DRAM_INIT may reset TF-A's DDR DFS state, breaking SET_RATE.
	 */

	/* Step 3: Get current DDR rate from TF-A */
	data->rate = rk3568_dmc_get_rate(data);

	/* #region agent log */
	dev_info(dev, "[DBG] GET_RATE (no INIT): %lu Hz (%lu MHz)\n",
		 data->rate, data->rate / 1000000);
	/* #endregion */

	if (!data->rate)
		goto fallback_clk;

	/*
	 * Step 4: Build OPP table by validating each candidate with ROUND_RATE.
	 * We add OPPs manually (dev_pm_opp_add) instead of using
	 * devm_pm_opp_of_add_table() because removing invalid OPPs from a
	 * DT-managed table crashes the OPP core (kref underflow).
	 */
	{
		static const unsigned long candidate_hz[] = {
			324000000, 528000000, 780000000, 1056000000,
		};
		int i, valid = 0;

		for (i = 0; i < ARRAY_SIZE(candidate_hz); i++) {
			long rounded = rk3568_dmc_round_rate(data, candidate_hz[i]);

			/* #region agent log */
			dev_info(dev, "[DBG] OPP %lu Hz -> ROUND_RATE=%ld\n",
				 candidate_hz[i], rounded);
			/* #endregion */

			if (rounded == (long)candidate_hz[i]) {
				dev_pm_opp_add(dev, candidate_hz[i], 900000);
				valid++;
			} else {
				dev_info(dev, "OPP %lu Hz not supported by TF-A\n",
					 candidate_hz[i]);
			}
		}
		dev_info(dev, "Added %d validated OPPs\n", valid);
	}

	/* #region agent log — H1/H3: SET_RATE without DRAM_INIT, with lcdc_type */
	{
		struct arm_smccc_res tres;
		void __iomem *cru;
		u32 __iomem *sp = (u32 __iomem *)data->params;

		cru = ioremap(0xfdd20000, 0x100);

#define DUMP_DPLL(tag) do { \
	u32 _c0 = 0, _c1 = 0, _div; \
	unsigned long _dpll = 0; \
	if (cru) { \
		_c0 = readl(cru + 0x20); \
		_c1 = readl(cru + 0x24); \
		_div = ((_c1) & 0x3f) * (((_c0) >> 12) & 0x7) * (((_c1) >> 6) & 0x7); \
		if (_div) \
			_dpll = 24000000UL * (_c0 & 0xfff) / _div; \
	} \
	dev_info(dev, "[DBG] %s: DPLL=%lu Hz  SIP_GET=%lu\n", \
		 tag, _dpll, rk3568_dmc_get_rate(data)); \
} while (0)

		/* Dump initial shared page state from TF-A */
		dev_info(dev,
			 "[DBG] SHMEM init[0..8]: %08x %08x %08x %08x %08x %08x %08x %08x %08x\n",
			 readl(&sp[0]), readl(&sp[1]), readl(&sp[2]), readl(&sp[3]),
			 readl(&sp[4]), readl(&sp[5]), readl(&sp[6]), readl(&sp[7]),
			 readl(&sp[8]));

		DUMP_DPLL("BEFORE");

		/*
		 * Probing the two-phase SET_RATE mechanism.
		 * BSP's clk-ddr.c set_rate_v2 uses:
		 *   hz=rate(Hz), lcdc_type=0, wait_flag1=1, wait_flag0=1
		 * and expects a1=-6 (timeout). Then calls wait_complete().
		 * We need to find what wait_complete does.
		 */

		/* Dump more of shared page to find hidden fields */
		dev_info(dev,
			 "[DBG] SHMEM[0..15]: %08x %08x %08x %08x %08x %08x %08x %08x\n"
			 "                    %08x %08x %08x %08x %08x %08x %08x %08x\n",
			 readl(&sp[0]),  readl(&sp[1]),  readl(&sp[2]),  readl(&sp[3]),
			 readl(&sp[4]),  readl(&sp[5]),  readl(&sp[6]),  readl(&sp[7]),
			 readl(&sp[8]),  readl(&sp[9]),  readl(&sp[10]), readl(&sp[11]),
			 readl(&sp[12]), readl(&sp[13]), readl(&sp[14]), readl(&sp[15]));

		/*
		 * T1: BSP-convention SET_RATE, then poll shared memory flags.
		 *     If TF-A's SET_RATE is async, flags should change over time.
		 */
		writel(528000000, &data->params->hz);
		writel(0, &data->params->lcdc_type);
		writel(1, &data->params->wait_flag1);
		writel(1, &data->params->wait_flag0);
		arm_smccc_smc(ROCKCHIP_SIP_DRAM_FREQ,
			      SHARE_PAGE_TYPE_DDR, 0,
			      ROCKCHIP_SIP_CONFIG_DRAM_SET_RATE,
			      0, 0, 0, 0, &tres);
		dev_info(dev, "[DBG] T1 SET(BSP): a0=0x%lx a1=0x%lx\n",
			 tres.a0, tres.a1);
		/* Immediate flag check */
		dev_info(dev, "[DBG] T1 flags after: wf1=%u wf0=%u hz=%u complt=%u\n",
			 readl(&data->params->wait_flag1),
			 readl(&data->params->wait_flag0),
			 readl(&data->params->hz),
			 readl(&data->params->complt_hwirq));
		DUMP_DPLL("AFTER T1 immed");
		mdelay(50);
		dev_info(dev, "[DBG] T1 flags +50ms: wf1=%u wf0=%u\n",
			 readl(&data->params->wait_flag1),
			 readl(&data->params->wait_flag0));
		DUMP_DPLL("AFTER T1 +50ms");

		/*
		 * T2: BSP-convention SET_RATE, then CLEAR wait_flag1.
		 *     Hypothesis: TF-A background polls wait_flag1;
		 *     clearing it signals "VOP ready, proceed".
		 */
		writel(528000000, &data->params->hz);
		writel(0, &data->params->lcdc_type);
		writel(1, &data->params->wait_flag1);
		writel(1, &data->params->wait_flag0);
		arm_smccc_smc(ROCKCHIP_SIP_DRAM_FREQ,
			      SHARE_PAGE_TYPE_DDR, 0,
			      ROCKCHIP_SIP_CONFIG_DRAM_SET_RATE,
			      0, 0, 0, 0, &tres);
		/* Immediately clear flags to simulate VOP ready */
		writel(0, &data->params->wait_flag1);
		writel(0, &data->params->wait_flag0);
		dev_info(dev, "[DBG] T2 SET+clear: a0=0x%lx a1=0x%lx\n",
			 tres.a0, tres.a1);
		mdelay(50);
		DUMP_DPLL("AFTER T2 +50ms");

		/*
		 * T3: SET_AT_SR (Set At Self-Refresh) then SET_RATE.
		 *     Maybe the DDR needs to be in self-refresh first.
		 */
		arm_smccc_smc(ROCKCHIP_SIP_DRAM_FREQ,
			      SHARE_PAGE_TYPE_DDR, 0,
			      ROCKCHIP_SIP_CONFIG_DRAM_SET_AT_SR,
			      0, 0, 0, 0, &tres);
		dev_info(dev, "[DBG] SET_AT_SR: a0=0x%lx a1=0x%lx\n",
			 tres.a0, tres.a1);

		/*
		 * T4: Try sub-commands 6, 7, 8 to discover any
		 *     undocumented "trigger" or "execute" command.
		 */
		arm_smccc_smc(ROCKCHIP_SIP_DRAM_FREQ,
			      SHARE_PAGE_TYPE_DDR, 0,
			      0x06, 0, 0, 0, 0, &tres);
		dev_info(dev, "[DBG] SUB6(CLK_STOP): a0=0x%lx a1=0x%lx\n",
			 tres.a0, tres.a1);
		arm_smccc_smc(ROCKCHIP_SIP_DRAM_FREQ,
			      SHARE_PAGE_TYPE_DDR, 0,
			      0x07, 0, 0, 0, 0, &tres);
		dev_info(dev, "[DBG] SUB7(SET_MSCH_RL): a0=0x%lx a1=0x%lx\n",
			 tres.a0, tres.a1);
		arm_smccc_smc(ROCKCHIP_SIP_DRAM_FREQ,
			      SHARE_PAGE_TYPE_DDR, 0,
			      0x08, 0, 0, 0, 0, &tres);
		dev_info(dev, "[DBG] SUB8(DEBUG): a0=0x%lx a1=0x%lx\n",
			 tres.a0, tres.a1);

		/*
		 * T5: VOP simulation — kthread on CPU1 clears wait_flag
		 *     while SET_RATE executes on this CPU. This simulates
		 *     the BSP VOP driver signaling "safe to switch DDR."
		 */
		{
			struct task_struct *vthread;

			vop_sim_p = data->params;
			WRITE_ONCE(vop_sim_active, 1);

			vthread = kthread_create(vop_sim_thread_fn,
						 NULL, "vop_sim");
			if (!IS_ERR(vthread)) {
				kthread_bind(vthread, 1);
				wake_up_process(vthread);
				msleep(2);

				writel(528000000, &data->params->hz);
				writel(0, &data->params->lcdc_type);
				writel(1, &data->params->wait_flag1);
				writel(1, &data->params->wait_flag0);
				mb();
				arm_smccc_smc(ROCKCHIP_SIP_DRAM_FREQ,
					      SHARE_PAGE_TYPE_DDR, 0,
					      ROCKCHIP_SIP_CONFIG_DRAM_SET_RATE,
					      0, 0, 0, 0, &tres);

				WRITE_ONCE(vop_sim_active, 0);
				msleep(1);

				dev_info(dev,
					 "[DBG] T5 VOP-SIM SET(528M): a0=0x%lx a1=0x%lx\n",
					 tres.a0, tres.a1);
				dev_info(dev,
					 "[DBG] T5 flags: wf1=%u wf0=%u\n",
					 readl(&data->params->wait_flag1),
					 readl(&data->params->wait_flag0));
				DUMP_DPLL("AFTER T5 VOP-SIM");
			} else {
				dev_info(dev,
					 "[DBG] T5 SKIP: kthread_create failed\n");
			}
		}

		/*
		 * T6: VOP sim + 324 MHz target (different from current).
		 *     Rules out "same frequency" confusion.
		 */
		{
			struct task_struct *vthread;

			WRITE_ONCE(vop_sim_active, 1);
			vthread = kthread_create(vop_sim_thread_fn,
						 NULL, "vop_sim2");
			if (!IS_ERR(vthread)) {
				kthread_bind(vthread, 1);
				wake_up_process(vthread);
				msleep(2);

				writel(324000000, &data->params->hz);
				writel(0, &data->params->lcdc_type);
				writel(1, &data->params->wait_flag1);
				writel(1, &data->params->wait_flag0);
				mb();
				arm_smccc_smc(ROCKCHIP_SIP_DRAM_FREQ,
					      SHARE_PAGE_TYPE_DDR, 0,
					      ROCKCHIP_SIP_CONFIG_DRAM_SET_RATE,
					      0, 0, 0, 0, &tres);

				WRITE_ONCE(vop_sim_active, 0);
				msleep(1);

				dev_info(dev,
					 "[DBG] T6 VOP-SIM SET(324M): a0=0x%lx a1=0x%lx\n",
					 tres.a0, tres.a1);
				DUMP_DPLL("AFTER T6 VOP-SIM");
			}
		}

		/* Final DPLL and shared page dump */
		DUMP_DPLL("FINAL");
		dev_info(dev,
			 "[DBG] SHMEM final[0..15]: %08x %08x %08x %08x %08x %08x %08x %08x\n"
			 "                         %08x %08x %08x %08x %08x %08x %08x %08x\n",
			 readl(&sp[0]),  readl(&sp[1]),  readl(&sp[2]),  readl(&sp[3]),
			 readl(&sp[4]),  readl(&sp[5]),  readl(&sp[6]),  readl(&sp[7]),
			 readl(&sp[8]),  readl(&sp[9]),  readl(&sp[10]), readl(&sp[11]),
			 readl(&sp[12]), readl(&sp[13]), readl(&sp[14]), readl(&sp[15]));

		/* Final shared page state */
		dev_info(dev,
			 "[DBG] SHMEM final[0..8]: %08x %08x %08x %08x %08x %08x %08x %08x %08x\n",
			 readl(&sp[0]), readl(&sp[1]), readl(&sp[2]), readl(&sp[3]),
			 readl(&sp[4]), readl(&sp[5]), readl(&sp[6]), readl(&sp[7]),
			 readl(&sp[8]));

		data->rate = rk3568_dmc_get_rate(data);

#undef DUMP_DPLL
		if (cru)
			iounmap(cru);
	}
	/* #endregion */

	data->can_scale = true;
	goto setup_devfreq;

monitor_only:
	data->can_scale = false;
fallback_clk:
	if (!data->rate) {
		struct clk *ddr_clk = devm_clk_get_optional(dev, "dmc_clk");

		if (!IS_ERR_OR_NULL(ddr_clk))
			data->rate = clk_get_rate(ddr_clk);
	}
	if (!data->rate) {
		dev_err(dev, "Cannot determine current DDR frequency\n");
		ret = -EINVAL;
		goto err_edev;
	}
single_opp:
	/* Add current rate as the sole OPP for monitoring */
	dev_pm_opp_add(dev, data->rate, 900000);

setup_devfreq:
	/* Ensure current rate is a valid OPP */
	opp = devfreq_recommended_opp(dev, &data->rate, 0);
	if (IS_ERR(opp)) {
		dev_info(dev, "Adding current rate %lu as OPP\n", data->rate);
		dev_pm_opp_add(dev, data->rate, 900000);
		opp = devfreq_recommended_opp(dev, &data->rate, 0);
		if (IS_ERR(opp)) {
			ret = PTR_ERR(opp);
			goto err_edev;
		}
	}
	data->rate = dev_pm_opp_get_freq(opp);
	dev_pm_opp_put(opp);

	data->ondemand_data.upthreshold = 40;
	data->ondemand_data.downdifferential = 20;

	data->profile = (struct devfreq_dev_profile) {
		.polling_ms	= 200,
		.target		= rk3568_dmcfreq_target,
		.get_dev_status	= rk3568_dmcfreq_get_dev_status,
		.get_cur_freq	= rk3568_dmcfreq_get_cur_freq,
		.initial_freq	= data->rate,
	};

	data->devfreq = devm_devfreq_add_device(dev,
						&data->profile,
						DEVFREQ_GOV_SIMPLE_ONDEMAND,
						&data->ondemand_data);
	if (IS_ERR(data->devfreq)) {
		ret = PTR_ERR(data->devfreq);
		dev_err(dev, "Cannot create devfreq device: %d\n", ret);
		goto err_edev;
	}

	devm_devfreq_register_opp_notifier(dev, data->devfreq);

	platform_set_drvdata(pdev, data);

	dev_info(dev, "DDR devfreq ready: %lu MHz, scaling=%s\n",
		 data->rate / 1000000,
		 data->can_scale ? "enabled" : "monitor-only");

	return 0;

err_edev:
	devfreq_event_disable_edev(data->edev);
	if (data->params)
		iounmap(data->params);
	return ret;
}

static void rk3568_dmcfreq_remove(struct platform_device *pdev)
{
	struct rk3568_dmcfreq *dmcfreq = dev_get_drvdata(&pdev->dev);

	devfreq_event_disable_edev(dmcfreq->edev);
	if (dmcfreq->params)
		iounmap(dmcfreq->params);
}

static const struct of_device_id rk3568_dmcfreq_of_match[] = {
	{ .compatible = "rockchip,rk3568-dmc" },
	{ },
};
MODULE_DEVICE_TABLE(of, rk3568_dmcfreq_of_match);

static struct platform_driver rk3568_dmcfreq_driver = {
	.probe	= rk3568_dmcfreq_probe,
	.remove = rk3568_dmcfreq_remove,
	.driver = {
		.name	= "rk3568-dmc-freq",
		.pm	= &rk3568_dmcfreq_pm,
		.of_match_table = rk3568_dmcfreq_of_match,
	},
};
module_platform_driver(rk3568_dmcfreq_driver);

MODULE_LICENSE("GPL v2");
MODULE_DESCRIPTION("RK3568/RK3566 DDR devfreq driver (SIP v2)");
