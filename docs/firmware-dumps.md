# Stock firmware dumps (reference)

This repo includes **unpacked** Miyoo Flip stock firmware for comparison with mainline DTS and drivers. Both are **BSP 5.10**–era trees (not mainline).

**Large raw images (GitHub ~100 MB file limit):** shipped as **zip** at repo root of each folder — `miyoo355_fw.img.zip`, `spi_20241119160817.img.zip`. Unzip if you need the original `.img` to re-flash or re-extract.

| Folder | Contents | Notes |
|--------|----------|--------|
| **`miyoo355_fw_20250509213001/`** | Newer card-flash image (May 2025). `unpack/miyoo355_2025.dts`, `unpack/bootimg.cfg`, `unpack/rootfs/` (kernel 5.10 config, System.map, init scripts, Miyoo UI). | Use for **2025** battery OCV, regulator, and panel/DSI expectations when aligning mainline. |
| **`spi_20241119160817/`** | Full SPI NAND dump from Nov 2024. `unpack/spi_20241119.dts`, `unpack/bootimg.cfg`, `unpack/userdata.img`, `unpack/rootfs/`, `unpack/joystick_study/` (notes and examples). | Older but **complete** SPI layout reference; joystick study material. |

**Typical use:** diff stock DTS vs `rk3566-miyoo-flip.dts` for PMIC (`rk817`), SDMMC (`vqmmc`, speed caps), battery/OCV tables, and DSI/panel init. Rootfs under `unpack/rootfs/` shows how stock loads WiFi/BT and which kernel options were enabled (`info/config-5.10`).
