# ROCKNIX & GammaOS Loader

## Overview

This project's mainline kernel and DTS work was used to create a
[ROCKNIX](https://rocknix.org/) device port for the Miyoo Flip:
[Zetarancio/distribution](https://github.com/Zetarancio/distribution).

ROCKNIX boots from an **SD card** using mainline U-Boot with extlinux.
The internal SPI NAND bootloader determines whether the device boots
from SD or internal storage.

## Boot Scenarios

| SPI NAND State | SD Card | Result |
|---------------|---------|--------|
| Stock preloader + U-Boot | No SD | Boots stock Miyoo OS |
| Stock preloader + U-Boot | ROCKNIX SD | Boots stock (boot_android finds kernel first) |
| GammaOS preloader + U-Boot | ROCKNIX SD | Boots stock (same issue) |
| Zeroed preloader | ROCKNIX SD | **Boots ROCKNIX** (bootrom falls through to SD) |
| Zeroed preloader | No SD | Sits in bootrom/MASKROM (not a brick) |

## GammaOS Bootloader

The [GammaOS bootloader](https://github.com/TheGammaSqueeze/GammaOSCore/releases)
(`GammaLoaderMiyooFlip.zip`) writes:

1. **Preloader** (0x0-0x200000): Updated DDR init + GammaOS SPL
2. **U-Boot** (0x300000): GammaOS U-Boot with ATF + OP-TEE

### Problem 1: boot_android Boots Stock Kernel

GammaOS U-Boot uses `boot_android` which reads the internal boot
partition. If a valid boot image exists there (stock kernel), it boots
immediately without checking the SD card.

**Fix:** Erase the boot partition:
```bash
xrock flash erase 14336 77824
```

### Problem 2: GammaOS SPL MMC Timeout

The GammaOS SPL gives SD cards only ~9 ms for voltage negotiation.
Most cards need 50-250 ms, causing:
```
Card did not respond to voltage select!
mmc_init: -95, time 9
```

The SPL fails on MMC, then fails on MTD (U-Boot erased), then resets
to bootrom -- which eventually loads from SD, but with a delay.

### Problem 3: Preloader Erase Doesn't Work

`xrock flash erase 0 4096` reports success but the preloader persists.
The IDBLOCK is stored at raw NAND blocks below xrock's logical erase
layer.

**Fix:** Write zeros instead:
```bash
dd if=/dev/zero of=/tmp/zeros.img bs=512 count=4096
xrock flash write 0 /tmp/zeros.img
```

## Full Procedure: Boot ROCKNIX on Normal Power-On

### Prerequisites

- xrock installed and working
- ROCKNIX SD card with `rk3566-miyoo-flip.dtb`
- SPI NAND backup (see [flashing.md](flashing.md))

### Steps

```bash
# 1. Enter MASKROM, load loader
xrock download output/rk356x_spl_loader_v1.23.114.bin
sleep 1 && xrock flash && sleep 1

# 2. Erase boot partition (remove stock kernel)
xrock flash erase 14336 77824

# 3. Erase uboot partition (remove GammaOS/stock U-Boot)
xrock flash erase 6144 8192

# 4. Zero the preloader (kill GammaOS SPL)
dd if=/dev/zero of=/tmp/zeros.img bs=512 count=4096
xrock flash write 0 /tmp/zeros.img

# 5. Insert ROCKNIX SD, disconnect USB, power on
```

### Expected Boot Log

```
DDR ... typ 24/09/03 fwver: v1.23           <-- ROCKNIX DDR from SD
U-Boot SPL 2026.01 ...                       <-- ROCKNIX SPL from SD
Trying to boot from MMC2
U-Boot 2026.01 ...                           <-- ROCKNIX U-Boot
Scanning bootdev 'mmc@fe2b0000.bootdev':
  0  extlinux ... /extlinux/extlinux.conf
** Booting bootflow ... with extlinux
1:  ROCKNIX
Retrieving file: /KERNEL
Retrieving file: /device_trees/rk3566-miyoo-flip.dtb
Starting kernel ...
```

## Restoring Stock/GammaOS Boot

```bash
# From backup
xrock flash write 0 preloader_backup.img
xrock flash write 6144 uboot_backup.img

# From stock dump
xrock flash write 0 Extra/spi_20241119160817.img
```

## Important Notes

- **Without an SD card**, a zeroed preloader means no boot. The device
  stays in bootrom/MASKROM mode. This is **not a brick** -- insert a
  ROCKNIX SD card or use xrock to restore the preloader.

- **`xrock flash erase`** works for uboot/boot/rootfs but **not** for
  the preloader area. Always use write-zeros for sectors 0-4095.

- The ROCKNIX idbloader loads from MMC2 (left SD slot). U-Boot finds
  extlinux.conf on `mmc@fe2b0000` (MMC1, right slot). Which physical
  slot is which depends on your SD card placement.
