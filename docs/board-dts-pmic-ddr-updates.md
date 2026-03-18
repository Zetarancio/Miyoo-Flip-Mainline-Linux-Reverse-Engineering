# Miyoo Flip board DTS, PMIC, DDR — recent evolution

Distro-agnostic summary of **what changed** on the Miyoo Flip port since early mainline bring-up. Full history: [Zetarancio/distribution commits on branch `flip`](https://github.com/Zetarancio/distribution/commits/flip/). Align mainline DTS and kernel patches with **2025 stock firmware** where noted in [firmware dumps](firmware-dumps.md).

---

## RK817 / suspend / power-off

| Topic | Notes |
|-------|--------|
| **rk8xx suspend/resume** | Kernel patches align RK817 sleep/resume with BSP ordering (e.g. `SLPPIN_SLP_FUN`, resume path). DTS may use `pmic-reset` tied to sleep-pin GPIO for reliable resume. |
| **Full power-off** | Do **not** use `system-power-controller` on RK817: mainline `DEV_OFF` can race PSCI `SYSTEM_OFF`, leaving the PMIC partly on and draining the battery. Without it, shutdown uses `rk8xx_shutdown()` + BL31. See [troubleshooting](troubleshooting.md). |
| **Deep sleep** | Still requires **rk3568-suspend** (BL31 deep-sleep flags) + sensible `vdd_logic` / regulator-off-in-suspend where used. See [suspend and vdd_logic](suspend-and-vdd-logic.md). |
| **vcc9 / BOOST** | Document clearly that RK817 `vcc9` needs the correct supply (e.g. avoid fw_devlink cycles vs `dcdc_boost`). |

---

## DDR / DMC (devfreq)

| Topic | Notes |
|-------|--------|
| **Out-of-tree DMC** | Same V2 SIP + MCU/IRQ model as BSP; still the path for DDR frequency scaling on RK3566 mainline. |
| **Driver tuning** | Recent trees add stability tweaks (e.g. self-refresh idle, ratelimit on transitions, regulator handling) — review the DMC devfreq patch in your kernel tree if scaling misbehaves after suspend. |

---

## Battery / OCV

| Topic | Notes |
|-------|--------|
| **2025 stock curve** | Mainline DTS battery node was aligned to stock 2025 limits (e.g. max/min voltage, charge current, multi-point OCV). |
| **OCV table order** | **Descending** voltage order is required for the fuel-gauge binding; wrong order breaks gauge behaviour. |

---

## SD / eMMC PHY

| Topic | Notes |
|-------|--------|
| **Shared vqmmc** | Both MicroSD slots can share one `vqmmc` rail; cap modes accordingly (e.g. avoid SDR50 on the second slot if hardware sharing limits it). Match stock 2025 speed limits where possible. |
| **Revisions** | I2C0 may see either TCS4525 or RK8600 on VDD_CPU depending on board revision — DTS comments / compatible handling should reflect both. |

---

## Display / WiFi (brief)

| Topic | Notes |
|-------|--------|
| **DSI / panel** | Panel init sequences and DSI flags were aligned with **2025** stock where they diverged from 2024 dumps. |
| **RTL8733BU** | GPIO power rail, disable USB autosuspend when the chip is power-gated, and several driver patches for suspend/resume and power. Optional **rtl8733bu-power**-style driver for full cut-off. See [drivers](drivers.md), [WiFi/BT power-off](wifi-bt-power-off.md). |

---

## Bootloader

| Topic | Notes |
|-------|--------|
| **BL31 / OP-TEE** | U-Boot FIT may track newer rkbin BL32; some trees adjust reserved-memory for OP-TEE. Always match **DDR init blob ↔ BL31** version expectations (see [SPI and boot chain](spi-and-boot-chain.md)). |

---

## Joypad / serial

Stock uses Miyoo-specific userspace and/or kernel input paths. Mainline may use a **UART joypad** driver and DTS `miyoo,*` nodes — compare with [firmware dumps](firmware-dumps.md) and your distribution’s DTS.
