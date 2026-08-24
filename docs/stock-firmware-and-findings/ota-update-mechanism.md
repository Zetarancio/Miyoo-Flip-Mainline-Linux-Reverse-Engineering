# Stock OTA update mechanism (`miyoo355_fw.img`)

How the stock card-based firmware update works, why it does **not** disturb a [repaired preloader](../boot-and-flash/sd-multiboot-apommel.md), and why it doubles as a root-code hook on stock.

---

## Package format

`miyoo355_fw.img` is a flat image, not an archive. `runmiyoo.sh` detects it on the card and hands it to `/usr/miyoo/apps/fw_update/miyoo_fw_update`, which extracts and runs the script from sector 1 as **root**.

| Offset | Content |
|--------|---------|
| sector 0 (`0x0`) | descriptor: `model:` and `version:` |
| sector 1 (`0x200`) | the update **shell script** |
| 1 MiB | `uboot.img` slot |
| 8 MiB | `boot.img` slot |
| 80 MiB | `rootfs.img` slot |

The 20250527 package (`134 938 624` bytes) carries:

```
model:miyoo355
version:20250527210639
```

## The update script

Verbatim structure of the 20250527 script, which is the whole of the update logic:

```sh
mount -o loop,offset=83886080 $MIYOO_FW $ROOT_RECOVERY   # tools from the NEW rootfs
export PATH=$ROOT_RECOVERY/bin:...

flash_erase /dev/mtd1 0 0        # uboot
flash_erase /dev/mtd2 0 0        # boot
flash_erase /dev/mtd3 0 0        # rootfs

dd if=$MIYOO_FW of=/dev/mtd1 bs=1M skip=1  count=7
dd if=$MIYOO_FW of=/dev/mtd2 bs=1M skip=8  count=72
dd if=$MIYOO_FW of=/dev/mtd3 bs=1M skip=80 count=128
sync
echo 1 > "/tmp/fwupdate_done"
poweroff
```

It mounts the packaged rootfs over loop to borrow `flash_erase`/`dd` from the *new* firmware, then writes three partitions and powers the device off.

### It never touches the preloader

Only `mtd1`, `mtd2`, `mtd3`. `mtd0` is `vnvm`, and the preloader region is not an MTD at all on stock. **A patched preloader and SD multiboot therefore survive an official update** — verified by updating a patched unit to 20250527 and finding both stock and ROCKNIX still booting afterwards.

This is not an oversight in one build. **No card-based package Miyoo ships contains a preloader**, including the *"Miyoo Flip V2 Firmware (unable to boot into the system)"* recovery download, whose script is byte-for-byte the same three-partition `flash_erase` + `dd`. Even their remedy for an unbootable device assumes a working preloader and U-Boot, so no card-based path repairs one — precisely the gap the [preloader eraser](../boot-and-flash/stock-rocknix-without-disassembly.md#preloader-eraser--maskrom-access) and [SD multiboot](../boot-and-flash/sd-multiboot-apommel.md) operate in.

**A preloader is distributed, but over USB and not by Miyoo.** The `unbrick_tool_windows` package from [steward-fu's releases](https://github.com/steward-fu/website/releases?q=flip) — `update.img`, a Rockchip `RKFW` carrying `MiniLoaderAll` — contains one, flashed from MASKROM with RKDevTool. Its DRAM blob is byte-identical to the one in this project's unit, which is what makes a shared patched preloader defensible; see [BSP and DDR findings](bsp-and-ddr-findings.md#1-ddr-initialization-and-firmware).

### The `count=` values exceed the partitions, harmlessly

The counts are slot sizes, not payload sizes. Measured real content versus the 2024 layout:

| Slice | Requested | Real content | Partition | Verdict |
|-------|-----------|--------------|-----------|---------|
| uboot → `mtd1` | 7 MiB | 3.96 MiB | 4 MiB | fits (40 KiB spare) |
| boot → `mtd2` | 72 MiB | 35.85 MiB | 38 MiB | fits |
| rootfs → `mtd3` | 128 MiB | 48.69 MiB | 64 MiB | fits |

Magics check out: `d00dfeed` (FIT), `ANDROID!` (boot image), `hsqs` (squashfs). The excess is padding, and `dd` truncation at the end of the device discards only padding.

### The layout is preserved

The packaged U-Boot 2017.09 (May 27 2025) contains no hardcoded `mtdparts` string — it generates one from the **GPT** already in flash (header at `0x200`, entries `0x400`–`0x4400`, first partition at LBA 4096), which the update does not rewrite. So updating does not silently repartition, and a 2024-layout device stays on its layout.

That GPT is also why stock can never write its own preloader: the table that would have to declare the region sits *inside* the region. See [SD multiboot](../boot-and-flash/sd-multiboot-apommel.md#it-can-only-write-from-rocknix).

---

## Version gating differs between firmware versions

| Firmware | Behaviour |
|----------|-----------|
| **20241119** | runs `miyoo355_fw.img` **unconditionally** — no version comparison |
| **20250527** | compares the descriptor `version:` against the installed one |

The 2024 script's permissiveness is what makes the hook usable for arbitrary payloads on that firmware.

The 2025 gate is weaker than it looks, so the hook stays usable there too. It requires `model:miyoo355` and a `version:` that merely **differs** from `/usr/miyoo/version` — the test is inequality, not "newer" — and it accepts the image from **either** card slot (`/media/sdcard0` or `/media/sdcard1`):

```sh
if [ "$oldversion" = "$version" ];then  echo "same version, skip."; miyoo_fw_update=0
else                                    miyoo_fw_update=1
fi
```

Two practical notes. The official script leaves `#rm $MIYOO_FW` commented out, so an image that passes the gate runs again on **every** boot unless the payload removes it. And the recovery download documents a forcing key combo: hold **menu**, then hold **power**, until the rocket logo appears, for when a normal update will not start.

### Known public versions

| Version | Package |
|---------|---------|
| `20241119160817` | 2024 firmware; matches the SPI dump tracked in this repo |
| `20250527210639` | "250527 Firmware" |
| `20250627233124` | shipped as the *"unable to enter the system"* recovery download — **newer than the headline release**, and the likely origin of the build apommel refers to as given to developers |

---

## Root-code hook on stock

The OTA check in `runmiyoo.sh` happens **before** MainUI is launched. Consequently a `miyoo355_fw.img` whose sector-1 script does something other than updating will run as root **even when stock's UI is completely broken** — which makes it the reliable escape hatch on a stock-only device.

`preloader-stock-rocknix/App/apommel-multiboot/tools/mkdiagfw.py` builds such an image. Practical notes:

- the file must be named exactly **`miyoo355_fw.img`**; anything else is ignored
- there is **no progress bar** if MainUI is broken, since the progress UI is MainUI's job
- the official script ends in `poweroff`, so **self power-off is the success signal**, not a failure
- touch `/tmp/fwupdate_done` at the end of a custom payload so the updater stops waiting

It cannot write the preloader: there is still no MTD node for that region, and a raw SFC write cannot produce valid ECC. See [SD multiboot](../boot-and-flash/sd-multiboot-apommel.md#it-can-only-write-from-rocknix).

---

## Case study: stock stuck on "loading" with a healthy boot

Symptom on a 20241119 unit: Miyoo logo, magnifying-glass icon, then a permanent "loading" screen. Boot itself was fine — the diagnostic payload above captured the cause.

MainUI did **not** hang; it initialised the display and then **exited after 4 seconds**:

```
DEBUG: KMSDRM_VideoInit()
DEBUG: Opened DRM FD (5)
--- exited on its own after 4s ---
```

because it could not read its own files from the squashfs rootfs:

```
blk_update_request: I/O error, dev mtdblock3, sector 33584 op 0x0:(READ)
SQUASHFS error: Failed to read block 0x105e9d9: -5
```

`runmiyoo.sh` then relaunches it forever, which is what the stuck "loading" screen actually is.

Notable details:

- exactly **one** failing squashfs block and **one** sector, ~16.4 MiB into the rootfs; boot-time `dmesg` was clean
- the same partition read back **byte-identical to the factory dump** from ROCKNIX, so the stored data was intact — stock runs the SPI NAND at 75 MHz (`spi-max-frequency = 75000000`) against ROCKNIX's 24 MHz
- **resolution:** the official OTA rewrites the rootfs, and stock booted normally afterwards

The lesson for diagnosis: a stock UI that never appears is not necessarily a boot or preloader problem, and the OTA hook can tell you which it is.

---

## See also

| Topic | Link |
|-------|------|
| Repaired preloader / SD multiboot | [SD multiboot](../boot-and-flash/sd-multiboot-apommel.md) |
| MTD layout, xrock, MASKROM | [Flashing guide](../boot-and-flash/flashing.md) |
| Preloader region, IDB, FIT | [SPI and boot chain](spi-and-boot-chain.md) |
