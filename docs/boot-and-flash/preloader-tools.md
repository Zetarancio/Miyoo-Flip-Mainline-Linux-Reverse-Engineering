# Stock-side preloader tools

Three card images stock can run. They change this unit's own preloader. They do not install an operating system, and they do not contain a universal preloader image.

A normal Zlyme install does not need this page. Write `zlyme.img`, put the card in the right-hand slot, and boot stock once. The card already contains `miyoo355_fw.img`. Stock runs it, repairs this unit's preloader for SD boot, and the next start can boot Zlyme. Steps: [Zlyme's install guide](https://github.com/Zetarancio/zlyme#install).

Use the files below when you need the same jobs without writing a full Zlyme card, or when Zlyme itself is not what is running.

## What stock actually runs

Stock looks for a file named exactly **`miyoo355_fw.img`**. Any other name is ignored. That is `runmiyoo.sh` on the 20250527 firmware, and the same name on the 20241119 firmware. The check is described in [OTA update mechanism](../stock-firmware-and-findings/ota-update-mechanism.md).

The release names are therefore descriptive. Before the card goes into the Flip, rename the one file you chose to `miyoo355_fw.img`. Put that file where stock can see it (the root of a FAT volume on either card). Do not put more than one of these images on the card under that name.

Until a zlyme44.2 release publishes the files, use the [Zlyme releases page](https://github.com/Zetarancio/zlyme/releases). This page does not link a file that is not published yet. The names to expect are:

| Release file | Role |
|--------------|------|
| `miyoo355_fw-multiboot.img` | Enable SD boot. Same bytes as the `miyoo355_fw.img` inside a fresh `zlyme.img`. |
| `miyoo355_fw-maskrom.img` | Arm the right-slot recovery preloader. |
| `miyoo355_fw-restore.img` | Write back this unit's saved original preloader. |

Each published file has a `.sha256` beside it. Check it before you rename.

A fresh `zlyme.img` contains only the multiboot installer. A Zlyme update contains none of these files.

## 1. Enable SD boot

`miyoo355_fw-multiboot.img`, renamed to `miyoo355_fw.img`.

Stock runs apommel's installer. It reads the preloader in this unit, saves `mtd5-original-<sha256>.img` on the card, repairs `/pinctrl` in the SPL device tree, checks the write, and leaves the DDR blob and the SPL program alone. How that repair works, and the older on-device app, stay on [SD multiboot](sd-multiboot-apommel.md).

After it succeeds, a bootable card in the right-hand slot starts that card. With no card, stock still starts from NAND. On 2026-10-07 a development Zlyme card that already contained this installer was booted from stock, the installer ran, and Zlyme came up.

## 2. Arm the recovery preloader

`miyoo355_fw-maskrom.img`, renamed to `miyoo355_fw.img`.

This does not ask you to hold the physical MASKROM button. It changes the preloader already in the Flip:

- it keeps that unit's DDR blob;
- it keeps the vendor SPL program, including the `/pinctrl` repair the right-hand slot needs;
- if the preloader is still an original supported stock image, it applies that repair in memory first;
- it sets the SPL boot order to only `/dwmmc@fe2b0000` (the right-hand slot; the vendor SPL logs this as MMC2);
- it refuses a preloader it cannot check, before it erases anything.

Result, measured on one Flip on 2026-10-08 and recorded in [Recovery preloader](recovery-preloader.md): a bootable Zlyme card in the right slot still boots Zlyme. With no bootable card there, the SPL fails that one device and resets to the boot ROM, which enumerates as USB MASKROM (`2207:350a`). There is no fall-through to the left slot, NAND, eMMC, or SPI.

The standalone image derives that preloader on the device. It does not carry one Flip's recovery image for every other Flip. The 2026-10-08 hashes on the evidence page are that unit's pair.

The helper saves this unit's original preloader on the card before it writes, when it starts from an unrepaired stock preloader. If the preloader is already repaired, it requires the `mtd5-original-<sha256>.img` already saved by the multiboot installer, and it refuses when that file is missing, ambiguous, or does not match.

This download is host-tested. It is not a separate hardware acceptance of the standalone file. The 2026-10-08 captures accepted the recovery preloader produced inside Zlyme, not this card image.

Once this preloader is installed, stock itself does not start unless the right-hand slot boots an OS that then runs stock. To put the saved original back from Zlyme, use Settings → System → Advanced → Recovery. This card helper runs when stock is what boots.

## 3. Restore this unit's original preloader

`miyoo355_fw-restore.img`, renamed to `miyoo355_fw.img`.

This writes the one `mtd5-original-<sha256>.img` that the multiboot or recovery helper saved on the card. The name's hash has to match the file. The DDR blob has to match the preloader that is installed, and the file has to be the original that produced that installed image, whether the installed image is the repaired preloader or the right-slot recovery preloader.

It refuses when there is no such file, more than one, a bad name, or a bad image. It does not take a path to some other file. It does not flash a generic stock blob from a release. A `preloader-current-*.img` saved as a rollback copy is not the original.

It saves the preloader that is installed now, then writes. If that write does not read back, it tries to put the saved current image back. Those two outcomes are different: a restored previous image is a failed restore; a rollback that cannot be checked is a critical failure.

Host-tested. Not hardware-accepted as this standalone file.

## What these are not

| Thing | What it is |
|-------|------------|
| Physical MASKROM button | Last-resort boot-ROM entry. Then [xrock](flashing.md) from a PC. |
| Stock U-Boot `rbrom` | Sets the download flag and resets. Does not erase or replace the preloader. |
| [Recovery preloader](recovery-preloader.md) | The right-slot-only SPL boot order. Section 2 above is the stock-side way to install that behavior. The page itself is the measurement. |
| [Erase the preloader](stock-rocknix-without-disassembly.md) | Removes the SPI preloader. A blank preloader is not USB MASKROM while another loader, including a card idbloader, can still boot. |
| Removed Zlyme experiments | A Linux restart and a boot-file marker were tried and removed. They are not a product path. |

The archived ROCKNIX fork used the erase method and an on-device restore script. That record stays on [its implementation page](../implementations/rocknix.md) and on [SD multiboot](sd-multiboot-apommel.md). It is not the install path for Zlyme.
