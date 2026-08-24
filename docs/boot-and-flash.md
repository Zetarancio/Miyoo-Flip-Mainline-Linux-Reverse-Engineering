# Boot and flash

How the Miyoo Flip boots, where distribution images come from, how to flash the SPI NAND, and how to boot from SD.

---

## Stock ↔ ROCKNIX (no disassembly)

**Without** removing screws for MASKROM:

| | |
|--|--|
| **Both at once (recommended)** | **Repair** the SPI preloader so the SPL can read a card: no card → **stock**, bootable card → **SD**. Method by [apommel](https://github.com/apommel/baseos-my355) — [SD multiboot](boot-and-flash/sd-multiboot-apommel.md). |
| **MASKROM access** | SD-card app **erases** the SPI **preloader** → with no card the device powers on in **MASKROM**. Removes internal stock boot. |
| **Back to stock only** | **`restore-preloader.sh`** on ROCKNIX writes a stock preloader back → reboot → **stock** from NAND. |

**Articles:** [SD multiboot via a repaired preloader](boot-and-flash/sd-multiboot-apommel.md) · [Stock ↔ ROCKNIX without disassembly](boot-and-flash/stock-rocknix-without-disassembly.md). Images: [Zetarancio/distribution](https://github.com/Zetarancio/distribution) branch **`flip`**. Helper files: [`preloader-stock-rocknix/`](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/tree/main/preloader-stock-rocknix).

Multiboot puts U-Boot **on the card**, so each distro must ship one built for this board: ROCKNIX does, cards made for **GammaLoader** (Knulli, GammaOS) do not — [why](boot-and-flash/sd-multiboot-apommel.md#distro-compatibility).

**Not a brick:** you can **always** recover with **USB MASKROM** (and, if needed, **disassemble** and use the hardware MASKROM button) + **`xrock`** — [Flashing](boot-and-flash/flashing.md).

---

## Hardware overview

| Component | Detail |
|-----------|--------|
| SoC | Rockchip RK3566 (quad Cortex-A55 @ 1.8 GHz) |
| GPU | Mali-G52 2EE (Bifrost), 200–800 MHz |
| RAM | LPDDR4 |
| Storage | SPI NAND 128 MB (**ESMT**, via SFC) — 128 KiB blocks, 2 KiB pages, 64 B OOB. Stock and mainline both log `esmt SPI NAND was found`; earlier wiki text said Winbond, which the boot logs do not support. |
| SD slots | 2× MicroSD (MMC1 @ fe2b0000, MMC2 @ fe2c0000) |
| Display | **LMY35120-20p** (**2503x** on flex). Sure: 640×480, 2-lane DSI, RGB888 video mode (stock DTS). Presumed: FT8006M — [Display](drivers-and-dts/display.md#module-name-vs-what-is-proven) |
| Backlight | PWM4 |
| WiFi/BT | RTL8733BU (USB combo) |
| Audio | RK817 codec, I2S, speaker amplifier |
| PMIC | RK817 (main) |
| Battery | Miyoo **755060**, **3.7 V** nominal, **3000 mAh**, **11.1 Wh** (typical pack marking) |
| VDD_CPU (I2C0) | **RK8600 @ 0x40** only. **TCS4525 @ 0x1c** was removed from the DTS after **Miyoo officially confirmed** there is **no second CPU-regulator variant**. The 2025 stock DTS still lists both addresses, but that is BSP legacy rather than evidence of two SKUs. See [Board DTS / PMIC / DDR — I2C0 CPU regulator](drivers-and-dts/board-dts-pmic-ddr-updates.md#i2c0-cpu-regulator). |
| USB | USB 2.0 OTG |
| UART | ttyS2 (fe660000), 1,500,000 baud, 3.3V |

Pinout and board photos: [steward-fu pin mapping](https://steward-fu.github.io/website/handheld/miyoo_flip_pin.htm), [specs](https://steward-fu.github.io/website/handheld/miyoo_flip_spec.htm). SD slot mapping is in [Serial — SD card slot mapping](serial.md).

---

## Where to get images

Use **[Zetarancio/distribution](https://github.com/Zetarancio/distribution)** (branch `flip`) for GitHub Actions image artifacts.

- **Generic** and **device-specific** builds are published.
- For Miyoo Flip, use the **device-specific** image.

The [stock ↔ ROCKNIX](#stock--rocknix-no-disassembly) procedure and typical SD tests use the **device-specific** Miyoo Flip artifacts from that repository.

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

**Prefer not to open the device?** Best option is [**SD multiboot**](boot-and-flash/sd-multiboot-apommel.md), which keeps stock bootable. The **Preloader Eraser** app remains the way to reach **MASKROM** from software: [**stock-rocknix-without-disassembly.md**](boot-and-flash/stock-rocknix-without-disassembly.md).

---

## steward-fu assets

- [steward-fu website — Miyoo Flip](https://steward-fu.github.io/website/handheld/miyoo_flip_uart.htm)
- [steward-fu release (miyoo-flip)](https://github.com/steward-fu/website/releases/tag/miyoo-flip)

---

## Legacy note

This `main` branch is wiki-focused. Legacy local build scripts are kept in branch **`buildroot`**.
