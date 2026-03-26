# Boot and flash

How the Miyoo Flip boots, how to obtain images, flash the SPI NAND, and boot from SD.

---

## Hardware overview

| Component | Detail |
|-----------|--------|
| SoC | Rockchip RK3566 (quad Cortex-A55 @ 1.8 GHz) |
| GPU | Mali-G52 2EE (Bifrost), 200–800 MHz |
| RAM | LPDDR4 |
| Storage | SPI NAND 128 MB (Winbond, via SFC) |
| SD slots | 2× MicroSD (MMC1 @ fe2b0000, MMC2 @ fe2c0000) |
| Display | **LMY35120-20p** (**2503x** on flex). Sure: 640×480, 2-lane DSI, RGB888 video mode (stock DTS). Presumed: FT8006M — [Display](drivers-and-dts/display.md#module-name-vs-what-is-proven) |
| Backlight | PWM4 |
| WiFi/BT | RTL8733BU (USB combo) |
| Audio | RK817 codec, I2S, speaker amplifier |
| PMIC | RK817 (main) |
| Battery | Miyoo **755060**, **3.7 V** nominal, **3000 mAh**, **11.1 Wh** (typical pack marking) |
| VDD_CPU (I2C0) | **TCS4525 @ 0x1c** and **RK8600 @ 0x40** are both described in DTS with `status = "okay"`, like 2025 stock. **Two hardware revisions** (only one regulator populated) are **inferred from firmware, not proven**. The empty address fails probe and is ignored; the populated rail supplies VDD_CPU and the device boots. See [Board DTS / PMIC / DDR — I2C0 CPU regulator](drivers-and-dts/board-dts-pmic-ddr-updates.md#i2c0-cpu-regulator-tcs4525-and-rk8600). |
| USB | USB 2.0 OTG |
| UART | ttyS2 (fe660000), 1,500,000 baud, 3.3V |

Pinout and board photos: [steward-fu pin mapping](https://steward-fu.github.io/website/handheld/miyoo_flip_pin.htm), [specs](https://steward-fu.github.io/website/handheld/miyoo_flip_spec.htm). SD slot mapping is in [Serial — SD card slot mapping](serial.md).

---

## Where to get images

Use **[Zetarancio/distribution](https://github.com/Zetarancio/distribution)** (branch `flip`) for current code/images.

- GitHub Actions creates **generic** and **device-specific** images.
- For Miyoo Flip testing, use the **device-specific** image.

---

## Boot chain

| Region | SPI Offset | Content |
|--------|------------|---------|
| Preloader | 0x000000–0x200000 | IDBLOCK + DDR init blob + stock SPL |
| U-Boot FIT | 0x300000+ | FIT image: ATF (BL31) + **OP-TEE (BL32)** + U-Boot + FDT |

**Any U-Boot for this board must include OP-TEE (BL32) in the FIT image.** The boot chain expects ATF + OP-TEE + U-Boot; omitting OP-TEE is not supported by the stock BL31/loader design. Recent versions of BL31 actually include BL32.

Boot flow: **Bootrom** reads IDBLOCK on SPI NAND, loads DDR init + SPL. **SPL** tries boot sources (MMC2 → MMC1 → MTD) and loads U-Boot. **U-Boot** reads the boot partition (Android boot image: kernel + DTB). **Kernel** mounts rootfs from `/dev/mtdblock3`.

For deep analysis (FIT segment addresses, BL31 DDR strings, DDR scaling), see [SPI image analysis](stock-firmware-and-findings/spi-and-boot-chain.md).

---

## Flashing

The 128 MB SPI NAND is flashed via **xrock** over USB in MASKROM mode. The full guide covers the MTD partition table, xrock setup, entering MASKROM, loading the DDR init, backup/restore commands, flashing U-Boot/boot/rootfs, boot.img format, erasing the preloader, and the mtdparts string.

**[Full flashing guide →](boot-and-flash/flashing.md)**

---

## Booting from SD

To boot the Miyoo Flip from an SD card (e.g. ROCKNIX) instead of internal SPI NAND, use xrock to erase the boot and uboot partitions and zero the preloader so the bootrom falls through to SD.

Quick steps: (1) enter MASKROM, load loader, `xrock flash`. (2) Erase boot and uboot. (3) Zero the preloader. (4) Insert SD, power on.

**Backup first.** Restore internal boot by reflashing preloader and uboot.

**[Full SD boot procedure →](boot-and-flash/boot-from-sd.md)**

---

## steward-fu assets

- [steward-fu website — Miyoo Flip](https://steward-fu.github.io/website/handheld/miyoo_flip_uart.htm)
- [steward-fu release (miyoo-flip)](https://github.com/steward-fu/website/releases/tag/miyoo-flip)

---

## Legacy note

This `main` branch is wiki-focused. Legacy local build scripts are kept in branch **`buildroot`**.
