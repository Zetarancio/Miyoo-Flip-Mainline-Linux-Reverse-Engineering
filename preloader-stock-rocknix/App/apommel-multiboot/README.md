# Multiboot — preloader repair app

Repairs the SPI NAND preloader so the SPL can read an SD card, giving automatic multiboot while internal stock boot keeps working:

| Card in the right-hand slot | Result |
|------|--------|
| none | stock from internal SPI NAND |
| card with a U-Boot the stock SPL can load | that OS from SD |
| card without one | falls through to stock |

Unlike **[PreloaderEraser](../PreloaderEraser/)**, which destroys the preloader so the bootrom drops into MASKROM, this **repairs** it.

## Credits

**The method is apommel's, not mine.** It was researched, documented and published at **[apommel/baseos-my355](https://github.com/apommel/baseos-my355)** — see `docs/02-sd-boot.md` for the analysis and `tools/mkpreloader.py` for the reference patcher.

apommel found that Miyoo's `fdtgrep` run left `/pinctrl` in the SPL device tree as an empty skeleton. No pinctrl driver binds to it, so `dwmmc@fe2b0000`'s `pinctrl-0` is never applied, the SD pins are never muxed, and the SPL cannot read a card even though its code is perfectly capable of doing so. Restoring nine properties on that node fixes it — leaving the DDR blob, the SPL code and the boot order exactly as Miyoo shipped them, which is why stock keeps booting and why an official firmware update survives the patch.

Thanks to apommel for doing the hard part and writing it up clearly enough to be reproduced and verified independently. The app prints these credits on every run.

The wiki page **[SD multiboot via a repaired preloader](../../../docs/boot-and-flash/sd-multiboot-apommel.md)** carries the full write-up: independent verification against this project's unit, why stock cannot write the preloader, the provenance of the bundled images, and the DRAM-blob argument. This file is the operator's manual for the app itself.

---
---

## Instructions

Copy the **whole folder** to `SDCARD/App/apommel-multiboot/`. The scripts read the images beside them.

### Where it can run

It **runs** on both stock and ROCKNIX, but it can only **write** where the kernel exposes the preloader region as an MTD node.

| System | Preloader as MTD? | This app |
|--------|-------------------|----------|
| **ROCKNIX** | yes — `mtd0` = `preloader`, 2 MiB | installs, restores, backs up |
| **stock** | no | writes nothing, leaves `mtd-report.txt` |

Erasing can bypass the kernel through the SFC (which is what `PreloaderEraser` does) because **erase needs no ECC**. **Writing cannot**: NAND pages need correct ECC and only the MTD layer produces it, so there is no safe stock-side fallback — and stock cannot be given the missing node either, for a reason that turns out to be circular: [why](../../../docs/boot-and-flash/sd-multiboot-apommel.md#why-stock-cannot-write-the-preloader).

### From a file manager (easiest on device)

Pick the script and choose **Execute**. No arguments, no typing — passing arguments on device means an SSH session, which is exactly what these avoid:

| Script | Does | Writes? |
|--------|------|---------|
| **`check-preloader.sh`** | report board, geometry, current preloader and DRAM blob | **no** |
| **`install-multiboot.sh`** | patch the preloader → SD multiboot on | yes |
| **`restore-preloader.sh`** | put a stock preloader back → multiboot off | yes |

Start with **`check-preloader.sh`** if unsure: it is read-only by construction, exiting before the first `flash_erase`, and it is the only one that tells you whether this unit's DRAM blob matches the bundled image before anything is at stake.

All three are thin wrappers around `launch.sh`, which must stay beside them. Each writes its own log next to the script (`install-log.txt`, `restore-log.txt`, `backup-log.txt`), which matters because a file manager usually shows no console.

### From the ROCKNIX Ports menu

Copy the three scripts in **`rocknix-ports/`** to `/storage/roms/ports/` and they appear as `Multiboot 1 Check`, `2 Install` and `3 Restore` in the Ports menu. They locate this folder on any attached card and call the wrapper above, so nothing needs arguments and the app folder can stay where it is.

### From a shell

```sh
sh launch.sh                 # install the patched preloader (default)
sh launch.sh install FILE    # install a specific image
sh launch.sh restore         # put a stock preloader back
sh launch.sh restore FILE    # put a specific image back
sh launch.sh backup          # read the current preloader out, write nothing
```

The stock launcher menu runs `launch.sh` (install) via `config.json`. Launchers that cannot pass arguments can instead select restore by creating an empty file named `RESTORE` next to `launch.sh`; `BACKUP_ONLY=1` still selects backup mode.

Optional: add `icon.png` next to `launch.sh` for a launcher icon (`config.json` references it).

### Bootstrap from stock: two steps

If only stock boots, the preloader cannot be written from there, so getting to multiboot takes two manual steps and two reboots. Both are operations already validated on this project's unit.

| # | Where | Run | Result |
|---|-------|-----|--------|
| 1 | **stock** | **[`PreloaderEraser`](../PreloaderEraser/)** | preloader erased → bootrom falls through to SD (and to MASKROM with no card) |
| 2 | **ROCKNIX**, booted from the card | **`install-multiboot.sh`** in this folder | patched preloader written via `mtd0` → multiboot |

Between the two steps the device is in exactly the state `PreloaderEraser` has always left it in: SD-only boot, MASKROM reachable without disassembly. If you stop after step 1, nothing new is broken — so a failed step 2 is not a dead end.

Step 2 is deliberately **manual**, not an autostart hook: nothing should rewrite the preloader without being asked.

### Restoring

`sh launch.sh restore` picks its image in this order:

1. the file you passed on the command line
2. the newest backup in this folder that is a **valid restore point** — preferred, because IDB entry 1 is DRAM init and belongs to *this* board
3. the bundled **`preloader-stock.img`**

A backup is rejected as a restore point if it is the wrong size, has no `RKNS` magic (an erased preloader is 2 MiB of `0xff`), **or is the patched image itself**. That last rule matters more than it sounds: every check or install saves a copy of the preloader it found, so after installing multiboot the newest backup on the card *is* the patched one — and restore has to mean undo the patch, not reapply it.

Blank copies are not merely skipped, they are **deleted**, so a 2 MiB file of `0xff` never sits on the card looking like a safety net. The only exception is during a failed install, where it is the honest description of the previous state until the rollback has finished.

**Verify your own images before trusting them**, especially if you reached ROCKNIX via the eraser — in that case the "backup" taken before patching is an erased region:

```sh
md5sum preloader-backup-*.img                            # b23b5d09... means blank
dd if=preloader-backup-X.img bs=1 skip=131072 count=4    # must print RKNS
```

Your own full SPI dump also makes a restore image, since the first 2 MiB *is* the preloader region:

```sh
dd if=spi_YYYYmmddHHMMSS.img of=preloader-mine.img bs=512 count=4096
sh launch.sh restore preloader-mine.img
```

### Other ways to restore

| Situation | Do this |
|-----------|---------|
| ROCKNIX boots | `restore-preloader.sh`, or `sh launch.sh restore [FILE]` |
| only stock boots | you cannot write from stock — run `PreloaderEraser`, boot ROCKNIX, restore there |
| nothing boots | MASKROM + `xrock` — see [flashing](../../../docs/boot-and-flash/flashing.md) |

The bootrom and USB MASKROM are not stored in SPI, so a bad preloader is recoverable, not permanent.

### Card requirements, and why Knulli / GammaOS do not work

Once patched, the SPL loads U-Boot **from the card**, finding it either in a GPT partition named `uboot` or at raw **sector 16384**. That U-Boot must be built for this board and loadable by the *stock* SPL.

ROCKNIX satisfies this, and so does apommel's own MinUI base. Cards built for **GammaLoader** (Knulli, GammaOS) currently do not — they ship a U-Boot that only works when paired with their own SPL via the bootrom. The failure is dissected in **[SD multiboot — distro compatibility](../../../docs/boot-and-flash/sd-multiboot-apommel.md#distro-compatibility)**.

---
---

## Technical evidence

### Hardware gating

Rather than trusting that one image suits every unit, the app verifies it and refuses when it cannot.

**Board identity**, from the device tree, which both systems expose with different strings:

| System | `/proc/device-tree/model` |
|--------|---------------------------|
| stock | `MIYOO RK3566 355 V10 Board` |
| ROCKNIX | `Miyoo Flip` |

The model must contain `Miyoo` and `compatible` must contain `rk3566`. A missing property only warns — a kernel without an unflattened DT is odd but is not evidence of wrong hardware — because the two checks below are the ones that actually protect the flash.

**Flash geometry**, from `/sys/class/mtd/mtdN/`: pages must be 2048 B and blocks 131072 B, and the partition exactly 2 MiB. The IDB header addresses its payload in 512 B sectors laid out for that geometry, so different values would put the DRAM blob and SPL where the bootrom does not look. This is also why a bad block in the first 2 MiB is fatal and refused.

**The DRAM blob itself** — the check that matters. The current preloader is read out *before* anything is erased, so the app compares the real ddrbin instead of reasoning about it:

```
ddrbin  = 0x020620 .. 0x02e000   (55776 bytes)
md5     = 4824552a71c46199c7c260d68b6a831f
```

Identical in `preloader-stock.img` and `preloader-patched.img`, since the patch only rewrites the two SPL device trees. If a unit's existing blob differs, its DRAM configuration differs, and the app **stops without erasing anything**, telling you to patch your own dump instead:

```sh
python3 mkpreloader.py preloader-backup-YYYYmmdd-HHMMSS.img mine.img
sh launch.sh install mine.img
```

The check is skipped only when the current preloader is already erased, where there is nothing to compare and replacing it was the point. Why one shared image is defensible in the first place — and why the blob turned out not to be per-unit — is argued with the measurements in [the wiki](../../../docs/boot-and-flash/sd-multiboot-apommel.md#is-shipping-one-units-preloader-defensible).

**Recorded but never gated:** the CPU regulator line from `dmesg`, and the SPI NAND identification. Useful in a log when diagnosing an odd unit; irrelevant to DRAM, so they must not block a write.

`FORCE=1` overrides any of these. It exists for the case where you have compared the blob yourself and disagree with the verdict — not as a way past an unexplained refusal.

### What it checks before erasing

- image is exactly 2 097 152 bytes and carries `RKNS` at `0x20000` and `0x80000`
- image is not an erased region (blank md5 rejected explicitly)
- md5 matches, for the two bundled images
- target MTD is named `preloader` or `spl` **and** is exactly 2 MiB
- zero bad blocks (a skipped block shifts every following page, so the IDB sector offsets would no longer point at the DDR blob and the SPL)
- battery over 25% or on charger
- current contents backed up to the SD card and size-checked before anything is erased

It retries up to three times and, if it still cannot verify the readback, **restores the backup**. It reboots only on success.

### The bundled images

| File | md5 | What it is |
|------|-----|-----------|
| `preloader-stock.img` | `1d525e6e6c89bd788b5245c90c97833b` | unmodified stock preloader, byte-identical to the first 2 MiB of this project's full SPI dump |
| `preloader-patched.img` | `c2009762b1704d5ed2ebbfa4346e6ecc` | the same, with `/pinctrl` repaired in **both** IDB copies — 4360 bytes differ, between `0x200e8` and `0xc9e1c` |

Provenance, the structural checks that confirm the stock image is a real preloader, and how to reproduce the extraction: [the wiki](../../../docs/boot-and-flash/sd-multiboot-apommel.md#provenance-of-the-bundled-stock-image).

More than one stock SPL build exists (Nov 02 and Dec 12 2024), so a fixed image silently up- or downgrades the **SPL** along with applying the fix, even though the DRAM blob is common. Upstream's `tools/mkpreloader.py` derives the patch from a unit's own dump on a PC if you would rather avoid that:

```sh
python3 mkpreloader.py mtd0-dump.img preloader-patched.img
```

### `tools/`

`mkdiagfw.py` builds a `miyoo355_fw.img` that makes **stock** run an arbitrary root script instead of updating anything, by abusing the OTA hook in `runmiyoo.sh`. It was written to diagnose a stock userspace that would not reach its UI, and it works even when MainUI is broken, because the OTA check runs before MainUI is launched. Useful as a general stock-side escape hatch. See [OTA update mechanism](../../../docs/stock-firmware-and-findings/ota-update-mechanism.md).

---

**See also:** [PreloaderEraser](../PreloaderEraser/) · [SD multiboot (wiki)](../../../docs/boot-and-flash/sd-multiboot-apommel.md) · [Erase the preloader for MASKROM](../../../docs/boot-and-flash/stock-rocknix-without-disassembly.md)
