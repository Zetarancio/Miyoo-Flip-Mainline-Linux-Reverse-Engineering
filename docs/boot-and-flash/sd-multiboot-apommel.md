# SD multiboot via a repaired preloader

Run an SD distro **and** keep stock on internal SPI NAND, with no card swap ritual and nothing erased. The device decides at power-on:

| Card in the right-hand slot | Result |
|------|--------|
| none | **stock** from internal SPI NAND |
| card with a U-Boot the stock SPL can load | **that OS** from SD |
| card the SPL cannot load a U-Boot from | falls through to **stock** |

This supersedes the erase-based method for dual boot. The [Preloader Eraser](stock-rocknix-without-disassembly.md#preloader-eraser--maskrom-access) is now only for reaching **MASKROM**.

## Credits

**The method is apommel's.** It was researched, documented and published at **[apommel/baseos-my355](https://github.com/apommel/baseos-my355)**:

| Source | What it is |
|--------|-----------|
| [`docs/02-sd-boot.md`](https://github.com/apommel/baseos-my355/blob/main/docs/02-sd-boot.md) | the analysis and rationale |
| `tools/mkpreloader.py` | reference patcher, derives the fix from a unit's own dump |

apommel found that Miyoo's **`fdtgrep`** run left **`/pinctrl`** in the SPL device tree as an empty skeleton. No pinctrl driver binds to it, so **`dwmmc@fe2b0000`**'s `pinctrl-0` is never applied, the SD pins are never muxed, and the SPL cannot read a card — even though its code is perfectly capable of doing so. Restoring **nine properties** on that node fixes it.

What makes it worth adopting is what it leaves alone. The **DDR blob, the SPL code and the boot order all stay exactly as Miyoo shipped them.** It repairs the vendor's own preloader rather than replacing it, which is why internal stock boot survives — and why the official OTA survives it too.

Thanks to apommel for doing the hard part, and for writing it up clearly enough that it could be reproduced and verified independently.

---

## Instructions

The tool is the **[`apommel-multiboot`](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/tree/main/preloader-stock-rocknix/App/apommel-multiboot)** app in this repo. Copy the **whole folder** to a card — the scripts read the images beside them.

### It can only write from ROCKNIX

| System | Preloader as MTD? | Can write? |
|--------|-------------------|-----------|
| **ROCKNIX** | yes — `mtd0` = `preloader`, 2 MiB | yes |
| **stock** | no | no — writes nothing, leaves `mtd-report.txt` |

Both systems can *run* the app; only ROCKNIX exposes the region the patch has to land in. Why, and why stock cannot simply be given that node, is under [technical evidence](#why-stock-cannot-write-the-preloader).

### Install

On **ROCKNIX**, pick a script in the file manager and choose **Execute** (cards appear under **`games-external`**):

| Script | Does | Writes? |
|--------|------|---------|
| **`check-preloader.sh`** | report board, flash geometry, current preloader and DRAM blob | **no** |
| **`install-multiboot.sh`** | patch the preloader → SD multiboot on | yes |
| **`restore-preloader.sh`** | put a stock preloader back → multiboot off | yes |

Run **`check-preloader.sh`** first. It is the same code path as install, stopped before the first write, so a clean run there means install has already passed every safety gate — including the only check that matters per unit, whether this device's DRAM blob matches the bundled image.

Each script writes its own log beside itself (`install-log.txt`, `restore-log.txt`, `backup-log.txt`), which matters because a file manager usually shows no console. From a shell the same thing is `sh launch.sh [install|restore|backup]`. For the ROCKNIX **Ports** menu, copy the three scripts in `rocknix-ports/` to `/storage/roms/ports/`.

**From a stock-only device** it takes two steps and two reboots: run the [Preloader Eraser](stock-rocknix-without-disassembly.md#preloader-eraser--maskrom-access) on stock, boot ROCKNIX from a card, then run the app there. In between, the device is exactly where the eraser has always left it — SD-only boot, MASKROM reachable without disassembly — so stopping halfway breaks nothing new.

### Restore

**`restore-preloader.sh`**, or `sh launch.sh restore [FILE]`. The image is chosen in this order:

1. a path given as an argument
2. the newest **valid** `preloader-backup-*.img` in the folder
3. the bundled **`preloader-stock.img`**

The app validates the image, saves the current contents first, verifies the readback and rolls back if it does not match.

### A backup is not automatically a restore point

If the preloader was **already erased** when a backup was taken — which is the case for anyone who used the eraser to get to ROCKNIX — that backup is **2 MiB of `0xff`** (md5 `b23b5d09162b92c0284923a7f628d2a5`). Writing it back erases rather than restores. The app deletes such files instead of leaving them looking like a safety net, but verify your own:

```sh
md5sum preloader-backup-*.img                            # b23b5d09... means blank
dd if=preloader-backup-X.img bs=1 skip=131072 count=4    # must print RKNS
```

The patched image is skipped too. Every check or install saves whatever it found, so after installing, the newest backup on the card *is* the patched preloader — and restore has to mean undo.

### Distro compatibility

Once patched, **the card owns U-Boot proper.** Each distro must therefore ship a U-Boot FIT that is (a) reachable at sector 16384 or in a GPT `uboot` partition, and (b) built for this board and loadable by the *stock* SPL.

| Distro | Works? | Why |
|--------|--------|-----|
| **stock** (internal NAND, no card) | yes, tested | the patch repairs Miyoo's own preloader, so internal boot is unchanged |
| **ROCKNIX** | yes, tested | ships a Miyoo Flip `u-boot.itb` at sector 16384 |
| **SpruceOS** | yes, tested | card U-Boot the stock SPL can load |
| **apommel's MinUI base** ([baseos-my355](https://github.com/apommel/baseos-my355)) | yes | the method's own target; card built for the repaired SPL |
| **Knulli** | no | ships an **rk3568-evb** U-Boot intended for its own SPL |
| **GammaOS** | expected no | same model — expects **GammaLoader** in NAND |

Only the "yes" rows have been exercised on real hardware. Anything not listed is untested rather than known-good.

What the other two would need to change is small and entirely on their side: ship a **Miyoo Flip** U-Boot FIT in the card's `uboot` partition (or at sector 16384), built so the stock SPL can load it — ROCKNIX's `flip` build is a working reference. Nothing in NAND changes and no user-side flashing is involved. Until then, users of those distros keep the [erase method](stock-rocknix-without-disassembly.md#preloader-eraser--maskrom-access), which boots the card's own idbloader from sector 64, at the cost of internal stock boot. The measured failure is dissected [below](#why-knulli-fails).

### Official firmware updates survive the patch

The stock OTA (`miyoo355_fw.img`) rewrites **only** `mtd1`/`mtd2`/`mtd3` — uboot, boot, rootfs. It never touches the preloader, so the patch and SD multiboot both survive an update. Verified on the 20250527 package; details and the update script itself are in [OTA update mechanism](../stock-firmware-and-findings/ota-update-mechanism.md).

---

## Technical evidence

### Independent verification

Checked against this project's own unit (`spi_20241119160817.img`, stock preloader `1d525e6e6c89bd788b5245c90c97833b`):

| Claim | Result |
|-------|--------|
| `/pinctrl` in the SPL FDT is an empty skeleton | confirmed |
| its `phandle` is referenced but the node carries no driver-usable properties | confirmed (dangling reference) |
| there is enough slack in the FDT to add the properties in place | confirmed |
| DDR blob and SPL code are untouched by the patch | confirmed byte-for-byte |
| boot order is the vendor's | confirmed |

The patched image differs from stock in **4360 bytes**, all between **`0x200e8`** and **`0xc9e1c`**, and both IDB copies still carry `RKNS` at `0x20000` and `0x80000`.

Tested end state on that unit: **stock boots with no card, ROCKNIX boots with its card inserted.** SpruceOS and apommel's MinUI base cards also boot under the same repaired SPL — [distro compatibility](#distro-compatibility).

### Where the SPL looks for U-Boot on the card

Two places, in this order:

1. a **GPT partition named `uboot`**
2. raw **sector 16384** (byte offset `0x800000`)

ROCKNIX works because its build writes `u-boot.itb` to absolute sector 16384. (`uboot.bin` goes to sector 64, with `u-boot.itb` at seek 16320 inside it.)

**One nuance about the fallback.** "Falls through to stock" applies when the SPL **cannot load** a U-Boot from the card. Once it has loaded one and jumped into it, there is no going back — a card whose U-Boot loads but then dies leaves the device hanging, not booting stock. That distinction is what identifies the Knulli failure below.

### Why stock cannot write the preloader

Stock's partitions come from `mtdparts=` on the kernel command line and begin at `vnvm` (`0x200000`), so nothing maps `0x000000`–`0x200000`, and `CONFIG_MTD_PARTITIONED_MASTER` is not set. Erase can bypass the kernel through the SFC because **erase needs no ECC** — that is how the eraser works. A write cannot: NAND pages need correct ECC and only the MTD layer produces it.

Nor can stock be given a node. Its `mtdparts=` is not hardcoded — stock U-Boot derives it from the **GPT in flash**, whose first entry (`vnvm`) starts at LBA 4096. Adding an entry that covers the preloader is the obvious fix, and it fails circularly:

```
0x000000  protective MBR (0x1c2 = 0xee)
0x000200  GPT header          first usable LBA 34, entries at LBA 2
0x000400  GPT entry array     128 x 128 B, ends 0x004400
0x020000  RKNS                IDB copy 1
0x080000  RKNS                IDB copy 2
0x0e0000  end of content      remainder of the 2 MiB is 0xff
```

**The partition table you would have to edit lives inside the region you cannot write.** ROCKNIX escapes this only because it takes its partitions from its device tree rather than the GPT, which is the root of the asymmetry.

(A one-time GPT edit *from ROCKNIX* would add the entry permanently, after which stock could patch and restore itself natively. It cannot help bootstrapping, since it needs ROCKNIX first, and it depends on stock U-Boot honouring the added entry — unverified.)

### Provenance of the bundled stock image

The bundled **`preloader-stock.img`** (md5 `1d525e6e6c89bd788b5245c90c97833b`) is **byte-identical to the first 2 MiB of `spi_20241119160817.img`**, the full SPI NAND dump tracked in this repo — reproducible with:

```sh
unzip -p spi_20241119160817/spi_20241119160817.img.zip spi_20241119160817.img \
  | head -c 2097152 | md5sum      # 1d525e6e6c89bd788b5245c90c97833b
```

Structural check that it is a real preloader rather than merely matching bytes: `RKNS` at `0x20000` and `0x80000` (two IDB copies), `d00dfeed` at `0x685c0` and `0xc85c0` (the two SPL device trees), the strings `U-Boot SPL board init` and `rockchip,rk3566`, and content ending at `0xe0000` with `0xff` beyond.

The same two commands turn **your own** full SPI dump into a restore image, since the first 2 MiB *is* the preloader region:

```sh
dd if=spi_YYYYmmddHHMMSS.img of=preloader-mine.img bs=512 count=4096
```

A stock OTA package cannot be used for this: `miyoo355_fw.img` starts at the `uboot` slot and contains **no preloader at all** — see [OTA update mechanism](../stock-firmware-and-findings/ota-update-mechanism.md).

### Is shipping one unit's preloader defensible?

IDB entry 1 is DRAM init, so a shared image imposes one unit's DRAM blob on every other. That objection has been tested and does not hold:

- This unit's blob is `DDR V1.18 f366f69a7d`, **byte-identical over 54.5 KiB** to the one in `unbrick_tool_windows/update.img` — a community package from [steward-fu's releases](https://github.com/steward-fu/website/releases?q=flip) used on many Flips. Community rather than official, so the evidence is empirical: it is the blob that demonstrably works on other people's units.
- It matches the public rkbin `rk3566_ddr_1056MHz_v1.18.bin` that the stock BSP already referenced.
- ROCKNIX boots the same hardware on a **newer generic blob (`v1.23`)**, which per-unit calibration data could not do.
- Miyoo have told this project's maintainer there is **only one hardware revision**, and the component difference this repo once suspected (`RK860` vs `FAN53555`/`TCS4525`) is the *CPU* regulator, unrelated to DRAM — the stock kernel probes for both.

Full evidence: [BSP and DDR findings](../stock-firmware-and-findings/bsp-and-ddr-findings.md#1-ddr-initialization-and-firmware).

Rather than rest on that, the app **verifies it per device**: it reads the existing preloader before erasing and compares the real ddrbin (`0x20620`–`0x2e000`, md5 `4824552a71c46199c7c260d68b6a831f`), refusing without erasing anything if it differs. Board model, SoC and NAND geometry are gated too — the gates are listed in the [app README](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/tree/main/preloader-stock-rocknix/App/apommel-multiboot#hardware-gating). Anyone who prefers deriving their own image can run upstream's `mkpreloader.py` against a dump on a PC.

One caveat survives regardless: the **SPL** is not common — more than one stock build exists (Nov 02 and Dec 12 2024) — so a shared image also moves the SPL, even though the DRAM blob is shared.

A per-unit patcher was planned while the blob still looked device-specific, and abandoned once it did not. It would have needed a native SFC **reader** on stock, because the dump has to happen *before* the erase (both IDB copies must be invalid for the bootrom to fall through to SD) and no MTD-readable second copy exists — `DDR V1.18` occurs exactly once in the whole 128 MiB dump, at `0x2d0cc`. Since the blob is public and identical, that work buys nothing the ddrbin gate does not already cover.

### Why Knulli fails

Knulli's card is laid out *correctly* for the patched SPL. From a Miyoo Flip Knulli card (2026-05 image):

```
sda1  start 16384, size 8192   name "uboot"      <- exactly where the SPL looks
sda2  start 24576, size 2048   name "resource"
sda3  start 32768              name "vfat"       KNULLI, extlinux + kernel
sda4  start 8421376            name "userdata"   SHARE
```

`sda1` is a valid FIT (`d00dfeed`), `FIT Image with ATF/OP-TEE/U-Boot/MCU`, and sector 64 holds an `RKNS` idbloader. So format and location are both right. The problem is *which board* it is for:

```
configurations/conf/description = rk3568-evb
U-Boot 2017.09-g4dbf6b2-dirty #davidb (May 02 2023 - 23:27:30 +0200)
```

and its own SPL carries a generic `DDR Version V1.13 20220218`.

Under the erase method the bootrom loaded **Knulli's** idbloader at sector 64, so its EVB SPL and EVB U-Boot ran as a self-consistent pair. Under the patched preloader, sector 64 is never read: Miyoo's 2024 DDR init runs, then the stock SPL loads Knulli's foreign FIT and jumps into it. An EVB U-Boot then re-initialises clocks, regulators and display from a device tree that does not describe this hardware.

**Observed:** black screen, no logo, device stays powered. Since the SPL did *not* fall through to stock — which is known to boot on that unit — it had already loaded and jumped into the card's U-Boot. The failure is inside Knulli's U-Boot, not in the preloader.

---

## See also

| Topic | Link |
|-------|------|
| Eraser (MASKROM), restoring stock, recovery | [MASKROM and SD boot by erasing the preloader](stock-rocknix-without-disassembly.md) |
| Partition layout, xrock, MASKROM | [Flashing guide](flashing.md) |
| Preloader region, IDB, FIT offsets | [SPI and boot chain](../stock-firmware-and-findings/spi-and-boot-chain.md) |
| Stock OTA internals | [OTA update mechanism](../stock-firmware-and-findings/ota-update-mechanism.md) |
| Boot chain overview | [Boot and flash](../boot-and-flash.md#boot-chain) |
