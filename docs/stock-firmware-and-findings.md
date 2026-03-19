# Stock firmware and findings

Distro-agnostic reference: unpacked stock firmware images, BSP/DDR analysis findings, and SPI boot chain investigation for the Miyoo Flip.

---

## Stock firmware dumps

This repo includes **partially unpacked** Miyoo Flip stock firmware for comparison with mainline DTS and drivers. Both are **BSP 5.10**-era trees (not mainline). Not a full rootfs extraction; selected files are kept for reference.

**Large raw images (GitHub ~100 MB file limit):** shipped as **zip** at repo root of each folder — `miyoo355_fw.img.zip`, `spi_20241119160817.img.zip`. Unzip if you need the original `.img` to re-flash or re-extract.

| Folder | Contents | Notes |
|--------|----------|--------|
| **`miyoo355_fw_20250509213001/`** | Newer card-flash image (May 2025). `unpack/miyoo355_2025.dts`, `unpack/bootimg.cfg`, `unpack/rootfs/` (kernel 5.10 config, System.map, init scripts, Miyoo UI). | Use for **2025** battery OCV, regulator, and panel/DSI expectations when aligning mainline. |
| **`spi_20241119160817/`** | Full SPI NAND dump from Nov 2024. `unpack/spi_20241119.dts`, `unpack/bootimg.cfg`, `unpack/userdata.img`, `unpack/rootfs/`, `unpack/joystick_study/` (notes and examples). | Older but **complete** SPI layout reference; joystick study material. |

**Latest stock DTS:** `miyoo355_fw_20250509213001/unpack/miyoo355_2025.dts` — diff this against your mainline `rk3566-miyoo-flip.dts` for PMIC (`rk817`), SDMMC (`vqmmc`, speed caps), battery/OCV tables, and DSI/panel init alignment.

**Typical use:** Rootfs under `unpack/rootfs/` shows how stock loads WiFi/BT and which kernel options were enabled (`info/config-5.10`).

---

## BSP and DDR findings

Analysis of the BSP kernel sources: DDR init binaries, DMC devfreq driver (`rockchip_dmc.c`), BL31/ATF firmware, power management regulators, relevant kernel config options, and the mainline status of each subsystem. Includes the out-of-tree `rk3568_dmc.c` driver implementing V2 SIP for mainline 6.18+.

**[Full BSP and DDR findings →](stock-firmware-and-findings/bsp-and-ddr-findings.md)**

---

## SPI image analysis and DDR scaling investigation

Deep analysis of the stock SPI NAND image: FIT image layout (ATF/OP-TEE/U-Boot segments with load addresses), BL31 DDR-related strings, SCMI clock configuration, U-Boot `dmc_fsp` driver analysis (compiled but never probed), stock kernel DDR/DMC DTS nodes and LPDDR4 timing parameters, the three-step SET_RATE protocol (V2 SIP + MCU/IRQ), and confirmation that DDR frequency scaling was active on stock firmware.

**[Full SPI and boot chain analysis →](stock-firmware-and-findings/spi-and-boot-chain.md)**
