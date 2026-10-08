# Recovery preloader

Measured on 2026-10-08 on one Miyoo Flip. The hashes below are that unit's pair. They are not an allowlist for every Flip.

The image is the stock November 02 2024 SPL (`U-Boot SPL 2017.09 (Nov 02 2024 - 15:59:04)`) after the usual `/pinctrl` repair, with one further change: the SPL device tree boot order is only

```text
/dwmmc@fe2b0000
```

That is the right-hand SD controller. The DDR payload is the unit's own DDR blob. The SPL executable before the DTB is unchanged. The `/pinctrl` repair stays. Both RKNS copies match. The change is resealed SPL hashes, not a second loader.

## Right-hand card present

With that preloader in NAND and a known-good Zlyme card in the right slot, serial showed:

```text
vendor DDR/SPL
Trying to boot from MMC2
Zlyme U-Boot
Zlyme Linux
```

NAND was not rewritten by that boot.

## Right-hand card absent

With the same preloader and the right card removed, serial showed only MMC2:

```text
Trying to boot from MMC2
Card did not respond to voltage select
mmc_init: -95
SPL: failed to boot from all boot devices
# Reset the board to bootrom #
```

No MMC1, NAND, MTD, or SPI boot source was attempted. The host then saw USB `2207:350a`, Rockchip download mode.

A later `xrock extra maskrom` loaded an RK3566 DDR helper and `rk356x_usbplug_v1.17` into RAM. `xrock flash` identified the NAND (Samsung, 128 MB, 128 KB blocks, 2 KB pages) and did not write it. The usbplug lines `Boot1 ... UsbBoot` are that RAM loader, not the preloader.

## Rescue

The right-hand Zlyme card is the boot path back to a system that can restore the saved normal preloader. The saved image has to be the exact source whose derivative is the image in NAND. Another unit's backup is not that source.

Erasing the preloader is a different operation. With a bootable card installed, the boot ROM can load that card's own idbloader. A blank preloader is not this one-entry SPL.

## This unit

| Image | SHA-256 |
| --- | --- |
| Normal / source preloader | `ed10591f62ae0b8845ac9bd6cf80c896a2b172d32c7c4ef6564d305e8662c13d` |
| Recovery derivative | `f7d9a25255080ac19e88df88d1232bf45a90bdf2e86c9f7e23b73d32a003f367` |

A full 2 MiB readback matched after arming, after the right-slot boot, and again after restoring the source. Bad blocks stayed 0. There was no ECC or I/O failure on those NAND transactions.
