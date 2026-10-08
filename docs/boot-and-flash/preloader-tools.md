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

After a verified write it removes `miyoo355_fw.img` and leaves stock's updater running. It does not reboot, and it does not decide which physical slot its own card is in. Power the Flip off before changing cards. A bootable card in the right-hand slot is the normal next boot.

On 2026-10-08 both paths of this image were hardware-accepted on one Flip. The already-repaired path started at `ed10591f62ae0b8845ac9bd6cf80c896a2b172d32c7c4ef6564d305e8662c13d`. One write read back as `f7d9a25255080ac19e88df88d1232bf45a90bdf2e86c9f7e23b73d32a003f367`, bad blocks stayed 0, and Zlyme then booted from the right-hand slot with recovery armed. The raw card log is [the repaired-path helper log](../../logs/zlyme-fw-maskrom-repaired-20261008.txt). That run still logged a reboot because its card node matched `/dev/mmcblk1p*`. The helper built after that no longer reboots. The direct-from-stock path started from the independently read original `dfdd7d20d6fd3beb18350dcf8fa58740b40b4baaf39467d45076f949053a2922`. Apommel's `/pinctrl` repair grew the tree `6058 -> 6238 (+180)`. The helper did not take the `already has properties` branch. One write read back as the same `f7d9a25255080ac19e88df88d1232bf45a90bdf2e86c9f7e23b73d32a003f367` image, bad blocks stayed 0, the helper removed itself, and it did not reboot. The raw card log is [the direct-stock helper log](../../logs/zlyme-fw-maskrom-direct-stock-20261008.txt). Zlyme then booted from the physical right-hand slot and read that same recovery image, with `mode=recovery` and `recovery=armed`. Those recovery bytes are the [recovery preloader](recovery-preloader.md) measurement. No new no-card serial capture was taken.

Stock's block-device index is not a physical slot. On stock `20250527210639`, one ordinary boot with only the physical left card inserted mounted that card as `/dev/mmcblk2p1` at `/media/sdcard1`. The raw record is [the launch probe](../../logs/zlyme-fw-launch-probe-20261008.txt). The earlier repaired-path helper, also with the card in the physical left slot, classified its node as `/dev/mmcblk1p*`. A later Zlyme boot of the right-hand OS card showed only `/dev/mmcblk0`, with `/boot` on `/dev/mmcblk0p2` and `/storage` on `/dev/mmcblk0p3`. That is Zlyme's numbering. None of these indexes is a universal map. The helpers do not use the block-device index as a physical slot.

Once this preloader is installed, stock itself does not start. Boot a supported OS card in the right-hand slot and use Settings → System → Advanced → Recovery → Disarm MASKROM recovery. The restore image in the next section is not that exit. This arming helper runs only when stock is what boots.

## 3. Restore this unit's original preloader

`miyoo355_fw-restore.img`, renamed to `miyoo355_fw.img`.

This is the stock-side undo of the normal multiboot repair. Stock has to be running. Under that repaired preloader, internal stock still starts when the right-hand slot has no bootable card, so stock can run this file and write back this unit's saved `mtd5-original-<sha256>.img`. The name's hash has to match the file. The DDR blob has to match the installed preloader, and the file has to be the original that produced that installed image.

This is not the normal way to leave an armed recovery preloader. After that preloader is installed, a bootable card in the right-hand slot starts that card, and no bootable card there goes to the boot ROM. Stock does not start, so putting this file on a plain card does not undo recovery. Boot a supported OS card in the right-hand slot, start Zlyme, and use Settings → System → Advanced → Recovery → Disarm MASKROM recovery. If that card is not available, the physical MASKROM button and [xrock](flashing.md) are the recovery path.

If stock is already running through some other arrangement, the helper can still recognize a recovery derivative of the saved original and write that original back. That check is defensive. It is not the ordinary path.

It refuses when there is no such file, more than one, a bad name, or a bad image. It does not take a path to some other file. It does not flash a generic stock blob from a release, and it is not Zlyme's bundled stock fallback. A `preloader-current-*.img` saved as a rollback copy is not the original.

It saves the preloader that is installed now, then writes. If that write does not read back, it tries to put the saved current image back. Those two outcomes are different: a restored previous image is a failed restore; a rollback that cannot be checked is a critical failure.

After a verified write it removes `miyoo355_fw.img` and leaves stock's updater running. It does not reboot. Power the Flip off before changing cards.

On 2026-10-08 this image was hardware-accepted on the same Flip. The live preloader was the repaired image `ed10591f62ae0b8845ac9bd6cf80c896a2b172d32c7c4ef6564d305e8662c13d`. The card held that unit's saved original `mtd5-original-dfdd7d20d6fd3beb18350dcf8fa58740b40b4baaf39467d45076f949053a2922.img`. One write read back as `dfdd7d20d6fd3beb18350dcf8fa58740b40b4baaf39467d45076f949053a2922`, bad blocks stayed 0, and there was no rollback and no critical failure. The helper removed itself and did not reboot. The raw card log is [the restore helper log](../../logs/zlyme-fw-restore-20261008.txt). A later stock-side read of `/dev/mtd5ro` returned that same hash, size 2097152, erase size 131072, and `bad_blocks=0`. The raw record is [the read-only verifier](../../logs/zlyme-preloader-readback-20261008.txt). That verifier was a one-off engineering check. It is not an install step. This acceptance is this unit's saved original. It is not a restore of another Flip's backup, and it is not the ordinary way out of an armed recovery preloader.

## Hardware accepted on this unit

These paths were measured on one Miyoo Flip on 2026-10-08. The hashes are that unit's images. The helpers still refuse a preloader that fails their structure, fingerprint, DDR, and source-pair checks.

| Path | Result |
|------|--------|
| Restore of this unit's saved original | `ed10591f62ae0b8845ac9bd6cf80c896a2b172d32c7c4ef6564d305e8662c13d` to `dfdd7d20d6fd3beb18350dcf8fa58740b40b4baaf39467d45076f949053a2922` |
| MASKROM helper from the repaired preloader | `ed10591f62ae0b8845ac9bd6cf80c896a2b172d32c7c4ef6564d305e8662c13d` to `f7d9a25255080ac19e88df88d1232bf45a90bdf2e86c9f7e23b73d32a003f367` |
| MASKROM helper from the original stock preloader | `dfdd7d20d6fd3beb18350dcf8fa58740b40b4baaf39467d45076f949053a2922`, then the `/pinctrl` repair, then `f7d9a25255080ac19e88df88d1232bf45a90bdf2e86c9f7e23b73d32a003f367` |
| Right-slot Zlyme boot from that recovery image | Zlyme read `f7d9a25255080ac19e88df88d1232bf45a90bdf2e86c9f7e23b73d32a003f367`, `mode=recovery`, `recovery=armed` |
| Zlyme disarm | `f7d9a25255080ac19e88df88d1232bf45a90bdf2e86c9f7e23b73d32a003f367` back to `ed10591f62ae0b8845ac9bd6cf80c896a2b172d32c7c4ef6564d305e8662c13d`, `mode=normal`, `recovery=ready` |

The 2026-10-08 hardware runs used the helper build from immediately before the fail-closed readback change. The release helper then requires each NAND readback to be a new full 2 MiB read. A failed or short read is not a verified write. The target transformations and the erase/write sequence were not changed. Another NAND cycle was not run for that correction.

### Not claimed

This record does not accept every Miyoo Flip vendor SPL revision, an arbitrary unknown preloader, another unit's original backup, Restore-from-recovery as the ordinary exit, erase-preloader as deterministic MASKROM, or a generic `mmcblkN` number for a physical slot.

The temporary packed probe and the read-only verifier were engineering checks. They are not part of installing Zlyme or of the three helpers above.

## What these are not

| Thing | What it is |
|-------|------------|
| Physical MASKROM button | Last-resort boot-ROM entry. Then [xrock](flashing.md) from a PC. |
| Stock U-Boot `rbrom` | Sets the download flag and resets. Does not erase or replace the preloader. |
| [Recovery preloader](recovery-preloader.md) | The right-slot-only SPL boot order. Section 2 above is the stock-side way to install that behavior. The page itself is the measurement. |
| [Erase the preloader](stock-rocknix-without-disassembly.md) | Removes the SPI preloader. A blank preloader is not USB MASKROM while another loader, including a card idbloader, can still boot. |
| Removed Zlyme experiments | A Linux restart and a boot-file marker were tried and removed. They are not a product path. |

The archived ROCKNIX fork used the erase method and an on-device restore script. That record stays on [its implementation page](../implementations/rocknix.md) and on [SD multiboot](sd-multiboot-apommel.md). It is not the install path for Zlyme.
