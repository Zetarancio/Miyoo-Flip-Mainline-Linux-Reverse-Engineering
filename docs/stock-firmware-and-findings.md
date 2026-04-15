# Stock firmware and findings

Distro-agnostic reference: unpacked stock firmware images, BSP/DDR analysis findings, and SPI boot chain investigation for the Miyoo Flip.

---

## Stock firmware dumps

This repo includes **partially unpacked** Miyoo Flip stock firmware for comparison with mainline DTS and drivers. Both are **BSP 5.10**-era trees (not mainline). Not a full rootfs extraction; selected files are kept for reference.

**Large raw images:** `spi_20241119160817.img.zip` at the repo root of that folder (unzip to re-flash or re-extract). The **20250527** card image (`miyoo355_fw.img`, ~129 MiB) lives inside **`miyoo355_fw_20250527/`** under GitHub’s per-file size limit.

| Folder | Contents | Notes |
|--------|----------|--------|
| **`miyoo355_fw_20250527/`** | Official **May 2025** Miyoo 355 card-flash unpack: `miyoo355_fw.img`, `miyoo355.zip`, `unpack/` with **`miyoo355_20250527_0.dts`** / **`miyoo355_20250527_1.dts`** (two DTBs from `boot.img`), `bootimg.cfg`, `rootfs/` (squashfs tree), kernel 5.10 `config` / `System.map` under `rootfs/info/`, Miyoo UI and init. | Canonical **2025** reference for battery OCV, regulators, and panel/DSI when aligning mainline. Replaces an earlier **20250509213001** tree that was never shipped publicly. |
| **`spi_20241119160817/`** | Full SPI NAND dump from Nov 2024. `unpack/spi_20241119.dts`, `unpack/bootimg.cfg`, `unpack/userdata.img`, `unpack/rootfs/`, `unpack/joystick_study/` (notes and examples). | Older but **complete** SPI layout reference; joystick study material. |

**Latest stock DTS (primary board):** `miyoo355_fw_20250527/unpack/miyoo355_20250527_0.dts` — diff against mainline `rk3566-miyoo-flip.dts` for PMIC (`rk817`), SDMMC (`vqmmc`, speed caps), battery/OCV tables, and DSI/panel init. The **`_1`** file is the secondary appended DTB from the same `boot.img` (see `unpack/README_UNPACK.txt`).

**Typical use:** Rootfs under `unpack/rootfs/` shows how stock loads WiFi/BT and which kernel options were enabled (`info/config-5.10`).

---

## BSP and DDR findings

Analysis of the BSP kernel sources: DDR init binaries, DMC devfreq driver (`rockchip_dmc.c`), BL31/ATF firmware, power management regulators, relevant kernel config options, and the mainline status of each subsystem. Includes the out-of-tree `rk3568_dmc.c` driver implementing V2 SIP for mainline 6.18+.

**[Full BSP and DDR findings →](stock-firmware-and-findings/bsp-and-ddr-findings.md)**

---

## SPI image analysis and DDR scaling investigation

Deep analysis of the stock SPI NAND image: FIT image layout (ATF/OP-TEE/U-Boot segments with load addresses), BL31 DDR-related strings, SCMI clock configuration, U-Boot `dmc_fsp` driver analysis (compiled but never probed), stock kernel DDR/DMC DTS nodes and LPDDR4 timing parameters, the three-step SET_RATE protocol (V2 SIP + MCU/IRQ), and confirmation that DDR frequency scaling was active on stock firmware.

**[Full SPI and boot chain analysis →](stock-firmware-and-findings/spi-and-boot-chain.md)**

---

## Reverse-engineering artifacts (BL31, PMIC dumps)

Material at the **repository root** (not under `docs/`) is **versioned on GitHub** and supports comparing stock vs ROCKNIX firmware and validating RK817 behavior.

**Repository:** [Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering) (`main`).

| Local path | On GitHub (`main`) | Content |
|------------|-------------------|---------|
| `bl31_v1.44_stock_disasm/` | [tree](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/tree/main/bl31_v1.44_stock_disasm) | Stock-adjacent **BL31 v1.44**: README, disassembly (`.S`), readelf/sections/strings/symbols, `rk3568_bl31_v1.44.elf`. |
| `bl31_v1.45_rocknix_disasm/` | [tree](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/tree/main/bl31_v1.45_rocknix_disasm) | **BL31 v1.45** (ROCKNIX rk3566): same layout + `rk3568_bl31_v1.45.elf`. |
| `bl31_v1.44_vs_v1.45_diff.patch` | [blob](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/blob/main/bl31_v1.44_vs_v1.45_diff.patch) | Text diff between the two disassembly exports (large; for tooling / review). |
| `Stock-dump.txt` | [blob](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/blob/main/Stock-dump.txt) | Stock BSP: debugfs (GPIO, pinmux, regulators) and PMIC snippets. |
| `Rocknix-dump-Before-ChargerFIX.txt` | [blob](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/blob/main/Rocknix-dump-Before-ChargerFIX.txt) | ROCKNIX PMIC `i2cdump` and debugfs **before** kernel patch 0007 (SYS_CAN_SD). |

**Write-up:** [Miyoo Flip — power-off battery drain investigation](miyoo-flip-power-off-investigation.md) ties these together with ammeter tests and register binary search.
