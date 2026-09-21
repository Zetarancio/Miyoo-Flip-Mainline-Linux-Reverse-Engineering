# Stock firmware

Vendor implementation. It is evidence for hardware and boot behavior, not a description of Zlyme or of the archived ROCKNIX fork.

| Tree in this repo | Firmware | What it is used for |
|-------------------|----------|---------------------|
| [`miyoo355_fw_20250527/`](../../miyoo355_fw_20250527/) | Official **May 2025** card package (kernel **5.10**). Raw `miyoo355_fw.img` is not stored here. | Primary 2025 DTS (`miyoo355_20250527_0.dts`), battery OCV, regulators, panel/DSI, `System.map` |
| [`spi_20241119160817/`](../../spi_20241119160817/) | SPI NAND dump, **November 2024** | Full SPI layout, older DTS, joystick study notes |

U-Boot in the 2025 package is **2017.09** (dated May 27 2025 in the investigated image). It builds `mtdparts` from the GPT already in flash. The OTA writes `mtd1`/`mtd2`/`mtd3` only, so a repaired preloader survives an official update.

Details, not repeated here:

- [Stock firmware and findings](../stock-firmware-and-findings.md)
- [BSP and DDR](../stock-firmware-and-findings/bsp-and-ddr-findings.md) — BSP `rockchip_dmc.c`, BL31, DDR blobs
- [SPI and boot chain](../stock-firmware-and-findings/spi-and-boot-chain.md)
- [OTA mechanism](../stock-firmware-and-findings/ota-update-mechanism.md)

The UART joypad path is a hardware fact: [Input](../hardware/input.md). This wiki does not document a stock userspace input program beyond the 2024 joystick study notes in the SPI unpack.
