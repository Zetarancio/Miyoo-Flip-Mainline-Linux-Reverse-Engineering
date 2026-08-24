# Multiboot — preloader repair app

Repairs the SPI NAND preloader so the SPL can read an SD card, giving automatic multiboot while internal stock boot keeps working:

| Card in the right-hand slot | Result |
|------|--------|
| none | stock from internal SPI NAND |
| card with a U-Boot the stock SPL can load | that OS from SD |
| card without one | falls through to stock |

Unlike **[PreloaderEraser](../PreloaderEraser/)**, which destroys the preloader so the bootrom drops into MASKROM, this **repairs** it.

---

## Credits

**The method is apommel's, not mine.** It was researched, documented and published at **[apommel/baseos-my355](https://github.com/apommel/baseos-my355)** — see `docs/02-sd-boot.md` for the analysis and `tools/mkpreloader.py` for the reference patcher.

apommel found that Miyoo's `fdtgrep` run left `/pinctrl` in the SPL device tree as an empty skeleton. No pinctrl driver binds to it, so `dwmmc@fe2b0000`'s `pinctrl-0` is never applied, the SD pins are never muxed, and the SPL cannot read a card even though its code is perfectly capable of doing so. Restoring nine properties on that node fixes it.

What makes the approach worth adopting is what it leaves alone: the **DDR blob, the SPL code and the boot order all stay exactly as Miyoo shipped them**. It repairs the vendor's own preloader instead of replacing it, which is why internal stock boot survives — and why an official firmware update survives it too (the OTA only rewrites `mtd1`/`mtd2`/`mtd3`, never the preloader).

Thanks to apommel for doing the hard part and writing it up clearly enough to be reproduced and verified independently. The app prints these credits on every run.

Independent verification against this project's own unit is summarised in the wiki: **[SD multiboot via patched preloader](../../../docs/boot-and-flash/sd-multiboot-apommel.md)**.

---

## Where it can run

It **runs** on both stock and ROCKNIX, but it can only **write** where the kernel exposes the preloader region as an MTD node.

| System | Preloader as MTD? | This app |
|--------|-------------------|----------|
| **ROCKNIX** | yes — `mtd0` = `preloader`, 2 MiB | installs, restores, backs up |
| **stock** | no | writes nothing, leaves `mtd-report.txt` |

Stock's partitions come from `mtdparts=` on the kernel command line and start at `vnvm` (`0x200000`):

```
root=/dev/mtdblock3 rootfstype=squashfs
mtdparts=spi-nand0:0x100000@0x200000(vnvm),0x400000@0x300000(uboot),
         0x2600000@0x700000(boot),0x4000000@0x2d00000(rootfs),0x1260000@0x6d00000(userdata)
```

Nothing maps `0x000000`–`0x200000`, and `CONFIG_MTD_PARTITIONED_MASTER` is not set. Erasing can bypass the kernel through the SFC (which is what `PreloaderEraser` does) because **erase needs no ECC**. **Writing cannot**: NAND pages need correct ECC and only the MTD layer produces it, so there is no safe stock-side fallback.

### Why stock cannot simply be given a node

Stock's `mtdparts=` is not hardcoded — stock U-Boot generates it from the **GPT in flash**, and that GPT declares nothing below 2 MiB (its first entry, `vnvm`, starts at LBA 4096). The obvious fix is to add an entry covering `0x000000`–`0x200000`. That is impossible from stock, and the way it fails is circular:

```
0x000000  protective MBR (0x1c2 = 0xee)
0x000200  GPT header          first usable LBA 34, entries at LBA 2
0x000400  GPT entry array     128 x 128 B, ends 0x004400
0x020000  RKNS                IDB copy 1
0x080000  RKNS                IDB copy 2
0x0e0000  end of content      remainder of the 2 MiB is 0xff
```

**The partition table you would have to edit lives inside the region you cannot write.** ROCKNIX escapes this only because it takes its partitions from its device tree rather than the GPT, which is the real root of the asymmetry above.

(A one-time GPT edit *from ROCKNIX* would add the entry permanently, after which stock could patch and restore itself natively. It cannot help bootstrapping, since it needs ROCKNIX first, and it depends on stock U-Boot honouring the added entry — unverified.)

---

## Bootstrap from stock: two steps

If only stock boots, the preloader cannot be written from there, so getting to multiboot takes two manual steps and two reboots. Both are operations already validated on this project's unit.

| # | Where | Run | Result |
|---|-------|-----|--------|
| 1 | **stock** | **[`PreloaderEraser`](../PreloaderEraser/)** | preloader erased → bootrom falls through to SD (and to MASKROM with no card) |
| 2 | **ROCKNIX**, booted from the card | **`install-multiboot.sh`** in this folder | patched preloader written via `mtd0` → multiboot |

Between the two steps the device is in exactly the state `PreloaderEraser` has always left it in: SD-only boot, MASKROM reachable without disassembly. If you stop after step 1, nothing new is broken — so a failed step 2 is not a dead end.

Step 2 is deliberately **manual**, not an autostart hook: nothing should rewrite the preloader without being asked.

---

## Usage

Copy the **whole folder** to `SDCARD/App/apommel-multiboot/`.

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
sh launch.sh restore         # put a stock preloader back
sh launch.sh restore FILE    # put a specific image back
sh launch.sh backup          # read the current preloader out, write nothing
```

The stock launcher menu runs `launch.sh` (install) via `config.json`. Launchers that cannot pass arguments can instead select restore by creating an empty file named `RESTORE` next to `launch.sh`; `BACKUP_ONLY=1` still selects backup mode.

Optional: add `icon.png` next to `launch.sh` for a launcher icon (`config.json` references it).

---

## Restoring

`sh launch.sh restore` picks its image in this order:

1. the file you passed on the command line
2. the newest backup in this folder that is a **valid restore point** — preferred, because IDB entry 1 is DRAM init and belongs to *this* board
3. the bundled **`preloader-stock.img`**

A backup is rejected as a restore point if it is the wrong size, has no `RKNS` magic (an erased preloader is 2 MiB of `0xff`), **or is the patched image itself**. That last rule matters more than it sounds: every check or install saves a copy of the preloader it found, so after installing multiboot the newest backup on the card *is* the patched one — and restore has to mean undo the patch, not reapply it.

Blank copies are not merely skipped, they are **deleted**, so a 2 MiB file of `0xff` never sits on the card looking like a safety net. The only exception is during a failed install, where it is the honest description of the previous state until the rollback has finished.

Easiest route on device: run **`restore-preloader.sh`** from a file manager.

### Provenance of `preloader-stock.img`

It is the unmodified stock preloader, md5 `1d525e6e6c89bd788b5245c90c97833b` — **byte-identical to the first 2 MiB of `spi_20241119160817.img`**, this project's own full SPI NAND dump (verified by extracting from `spi_20241119160817/spi_20241119160817.img.zip` in this repo). The same file has been committed as `../../preloader-restore/preloader.img` since commit `70afc20`.

Structure, as a sanity check that it is a real preloader and not just matching bytes:

```
RKNS            0x20000, 0x80000     two IDB copies
d00dfeed        0x685c0, 0xc85c0     the two SPL device trees
strings         "U-Boot SPL board init", "rockchip,rk3566"
content ends    0xe0000              remainder is 0xff
```

It differs from `preloader-patched.img` in only 4360 bytes, between `0x200e8` and `0xc9e1c` — the patch is applied to **both** IDB copies.

You can reproduce the extraction yourself:

```sh
unzip -p spi_20241119160817/spi_20241119160817.img.zip spi_20241119160817.img \
  | head -c 2097152 | md5sum      # 1d525e6e6c89bd788b5245c90c97833b
```

### A backup is not automatically a restore point

If the preloader was **already erased** when a backup was taken — which is the case if you had used `PreloaderEraser` to get to ROCKNIX — that backup is **2 MiB of `0xff`** (md5 `b23b5d09162b92c0284923a7f628d2a5`). Writing it back does not restore anything; it erases. The app refuses such images by name and skips them when auto-selecting, but check your own files before trusting them:

```sh
md5sum preloader-backup-*.img          # b23b5d09... means blank
dd if=preloader-backup-X.img bs=1 skip=131072 count=4   # must print RKNS
```

### Other ways to restore

| Situation | Do this |
|-----------|---------|
| ROCKNIX boots | `sh launch.sh restore`, or `preloader-restore/write-preloader-mtd.sh preloader.img` |
| only stock boots | you cannot write from stock — run `PreloaderEraser`, boot ROCKNIX, restore there |
| nothing boots | MASKROM + `xrock` — see [flashing](../../../docs/boot-and-flash/flashing.md) |

The bootrom and USB MASKROM are not stored in SPI, so a bad preloader is recoverable, not permanent.

---

## Prebuilt image, and why that matters

`preloader-patched.img` (2 MiB, md5 `c2009762b1704d5ed2ebbfa4346e6ecc`) is derived from **this project's own unit** — byte-identical to the first 2 MiB of `spi_20241119160817.img` apart from the patch.

IDB entry 1 is DRAM init, so writing one unit's image onto another imposes its DDR blob on that unit. That was the reason for caution here — **and it has since been checked and cleared** (see below): this unit's blob is byte-identical to the one Miyoo distributes publicly for unbricking any Flip. Upstream's `tools/mkpreloader.py` still lets anyone derive their own on a PC:

```sh
python3 mkpreloader.py mtd0-dump.img preloader-patched.img
```

One caveat is unaffected by that: more than one stock SPL build exists (Nov 02 and Dec 12 2024), so a fixed image silently up- or downgrades the **SPL** along with applying the fix, even though the DRAM blob is common.

### The DRAM blob is not unit-specific — measured, not assumed

That caution turned out to be overstated, and it is now settled by comparison rather than assumption.

The blob identifies itself as `DDR V1.18 f366f69a7d typ 23/07/17-15:48:58`: a stock **Rockchip** ddrbin, same family as the public `rk3566_ddr_1056MHz_v1.xx.bin` files in [`rkbin`](https://github.com/rockchip-linux/rkbin). Those are per-SoC-and-frequency binaries that train DRAM at runtime — not per-device calibration data.

Better still, the identical blob is **publicly redistributed for every Flip**, in the community `unbrick_tool_windows` package from [steward-fu's releases](https://github.com/steward-fu/website/releases?q=flip) (not a Miyoo download — Miyoo ship no preloader on any card). Comparing this unit's preloader with the `update.img` inside it:

| Region | Result |
|--------|--------|
| `RKNS` header | identical to `0xd2`, then IDB sector counts differ |
| **ddrbin, `0x000620`–`0x00e000` (54.5 KiB)** | **byte-identical** |
| beyond `0x00e000` | diverges — the device carries a U-Boot SPL, the unbrick loader carries `MiniLoaderAll` |

So the exact DRAM blob on this unit is the one inside a one-size-fits-all unbrick package that has been used successfully across many Flips. Since the tool is community-built rather than official, the evidence is empirical rather than a vendor guarantee — but for this purpose that is arguably stronger: it is the blob that demonstrably works on other people's units, not just a claim that it should.

On board-revision variation, two further points. Miyoo have told this project's maintainer directly that there is **only one hardware revision**. And the difference this repo previously suspected — `RK860` versus `FAN53555`/`TCS4525` — is the **CPU** regulator, which has nothing to do with DRAM init; the stock kernel simply probes for both and uses whichever answers (this unit logs `fan53555-regulator 0-001c: Failed to get chip ID!` followed by `RK860 chip ID:88`).

None of that is a substitute for checking, so the app now checks. See below.

### Why an on-device per-unit patcher is not needed

Deriving the patch per unit was the plan while the blob looked device-specific. It would have needed a native SFC **reader** on stock, because the dump must happen *before* the erase (both IDB copies must be invalid for the bootrom to fall through to SD) and no MTD-readable copy exists elsewhere — `DDR V1.18` occurs exactly once in the whole 128 MiB dump, at `0x2d0cc`.

Since the blob is public and identical, that work buys nothing. The bundled image stands, and anyone who prefers deriving their own can run upstream's `mkpreloader.py` against a MASKROM dump on a PC.

---

## Hardware gating

Rather than trusting that one image suits every unit, the app verifies it and refuses when it cannot.

**Board identity**, from the device tree, which both systems expose with different strings:

| System | `/proc/device-tree/model` |
|--------|---------------------------|
| stock | `MIYOO RK3566 355 V10 Board` |
| ROCKNIX | `Miyoo Flip` |

The model must contain `Miyoo` and `compatible` must contain `rk3566`. A missing property only warns — an unflattened-DT-less kernel is odd but is not evidence of wrong hardware — because the two checks below are the ones that actually protect the flash.

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

The check is skipped only when the current preloader is already erased, where there is nothing to compare and replacing it was the point.

**Recorded but never gated:** the CPU regulator line from `dmesg`, and the SPI NAND identification. Useful in a log when diagnosing an odd unit; irrelevant to DRAM, so they must not block a write.

`FORCE=1` overrides any of these. It exists for the case where you have compared the blob yourself and disagree with the verdict — not as a way past an unexplained refusal.

---

## What it checks before erasing

- image is exactly 2 097 152 bytes and carries `RKNS` at `0x20000` and `0x80000`
- image is not an erased region (blank md5 rejected explicitly)
- md5 matches, for the two bundled images
- target MTD is named `preloader` or `spl` **and** is exactly 2 MiB
- zero bad blocks (a skipped block shifts every following page, so the IDB sector offsets would no longer point at the DDR blob and the SPL)
- battery over 25% or on charger
- current contents backed up to the SD card and size-checked before anything is erased

It retries up to three times and, if it still cannot verify the readback, **restores the backup**. It reboots only on success.

---

## Card requirements, and why Knulli / GammaOS do not work

Once patched, the SPL loads U-Boot **from the card**, finding it either in a GPT partition named `uboot` or at raw **sector 16384**. That U-Boot must be built for this board and loadable by the *stock* SPL.

ROCKNIX satisfies this. Cards built for **GammaLoader** (Knulli, GammaOS) currently do not — they ship a U-Boot that only works when paired with their own SPL via the bootrom. Details and what those projects would need to change: **[SD multiboot — distro compatibility](../../../docs/boot-and-flash/sd-multiboot-apommel.md#distro-compatibility)**.

---

## `tools/`

`mkdiagfw.py` builds a `miyoo355_fw.img` that makes **stock** run an arbitrary root script instead of updating anything, by abusing the OTA hook in `runmiyoo.sh`. It was written to diagnose a stock userspace that would not reach its UI, and it works even when MainUI is broken, because the OTA check runs before MainUI is launched. Useful as a general stock-side escape hatch. See [stock firmware findings](../../../docs/stock-firmware-and-findings.md).

---

**See also:** [PreloaderEraser](../PreloaderEraser/) · [preloader-restore](../../preloader-restore/) · [SD multiboot (wiki)](../../../docs/boot-and-flash/sd-multiboot-apommel.md) · [Stock ↔ ROCKNIX without disassembly](../../../docs/boot-and-flash/stock-rocknix-without-disassembly.md)
