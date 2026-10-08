# Recovery preloader

Measured on 2026-10-08 on one Miyoo Flip. The hashes below are that unit's images. They are not an allowlist for every Flip. A stock-side helper that derives this behavior on the device, instead of flashing these hashes, is [preloader tools](preloader-tools.md). These two serial logs are the hardware record for the recovery preloader produced inside Zlyme, and they were not rewritten later. The standalone MASKROM helper then wrote this same recovery image twice: once from the repaired preloader `ed10591f62ae0b8845ac9bd6cf80c896a2b172d32c7c4ef6564d305e8662c13d`, and once from the saved original stock image `dfdd7d20d6fd3beb18350dcf8fa58740b40b4baaf39467d45076f949053a2922`. The stock path applied the `/pinctrl` repair (`6058 -> 6238`, +180) and did not take the `already has properties` branch. Each helper write was one verified write, bad blocks stayed 0, and there was no rollback. Zlyme then booted from the physical right-hand slot and read `f7d9a25255080ac19e88df88d1232bf45a90bdf2e86c9f7e23b73d32a003f367`, with `mode=recovery` and `recovery=armed`. `disarm-recovery` restored `ed10591f62ae0b8845ac9bd6cf80c896a2b172d32c7c4ef6564d305e8662c13d`, with `mode=normal` and `recovery=ready`. No second no-card serial capture was taken. The raw helper records are [repaired path](../../logs/zlyme-fw-maskrom-repaired-20261008.txt), [direct from stock](../../logs/zlyme-fw-maskrom-direct-stock-20261008.txt), [restore](../../logs/zlyme-fw-restore-20261008.txt), and [stock readback](../../logs/zlyme-preloader-readback-20261008.txt).

The image is the stock November 02 2024 SPL (`U-Boot SPL 2017.09 (Nov 02 2024 - 15:59:04)`) after the usual `/pinctrl` repair, with one further change: the SPL device tree boot order is only

```text
/dwmmc@fe2b0000
```

That is the right-hand SD controller. The vendor SPL logs it as MMC2. Linux calls the same controller MMC1. The DDR payload is the unit's own DDR blob. The SPL executable before the DTB is unchanged. The `/pinctrl` repair stays. Both RKNS copies match. The change is resealed SPL hashes, not a second loader.

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
| Saved original stock preloader | `dfdd7d20d6fd3beb18350dcf8fa58740b40b4baaf39467d45076f949053a2922` |
| Normal / repaired source preloader | `ed10591f62ae0b8845ac9bd6cf80c896a2b172d32c7c4ef6564d305e8662c13d` |
| Recovery derivative | `f7d9a25255080ac19e88df88d1232bf45a90bdf2e86c9f7e23b73d32a003f367` |

A full 2 MiB readback matched after arming, after the right-slot boot, and again after restoring the source. Bad blocks stayed 0. There was no ECC or I/O failure on those NAND transactions.

## Serial records

These two captures are the 2026-10-08 closure logs, taken at 1,500,000 8N1, receive only:

- [Recovery preloader, no right card](../../logs/boot_log_ZLYME_recovery-preloader-maskrom-20261008.txt)
- [Recovery preloader, right-slot Zlyme boot](../../logs/boot_log_ZLYME_right-slot-normal-20261008.txt)

```text
recovery preloader + right bootable card
→ MMC2 → normal OS boot

recovery preloader + no bootable right card
→ MMC2 failure → all devices failed → reset to BootROM/MASKROM
```

The no-card log shows the vendor DDR blob, `U-Boot SPL 2017.09 (Nov 02 2024 - 15:59:04)`, `Trying to boot from MMC2`, `Card did not respond to voltage select!`, `mmc_init: -95`, `SPL: failed to boot from all boot devices`, and `# Reset the board to bootrom #`. This unit printed that sequence three times. No other boot source was attempted. While that log was at the BootROM line, the host enumerated USB `2207:350a`.

The right-slot log shows the same DDR and SPL, a successful FIT handoff, production Zlyme U-Boot (`U-Boot 2026.01`) with no countdown, extlinux, the kernel, and `zlyme login:`.

The recovery image is a deterministic device-tree-only derivative of this unit's patched preloader. The DDR payload and the SPL executable are preserved. Only the boot order changes. The hashes above are this unit's evidence, not a universal allowlist.

These are not the physical MASKROM button, not stock U-Boot `rbrom`, and not the removed Zlyme reset-marker experiments. Those are separate. The button and `xrock` procedure stay in [Flashing](flashing.md). The failed marker experiments are not a product path.
