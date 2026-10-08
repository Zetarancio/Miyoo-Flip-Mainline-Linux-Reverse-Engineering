# Flashing and partition layout

Generic guide to flashing the Miyoo Flip SPI NAND: partition layout, xrock, MASKROM, backup, restore, and [booting from SD](#booting-from-sd). For a quick overview, see the [Boot and flash](../boot-and-flash.md) front page.

---

## MTD partition table

The 128 MB SPI NAND is divided into five partitions:

| Partition | Byte offset | Size | Sector | Purpose |
|-----------|-------------|------|--------|---------|
| vnvm | 0x200000 | 1 MB | 4096 | Non-volatile storage |
| uboot | 0x300000 | 4 MB | 6144 | U-Boot FIT (ATF + OP-TEE + U-Boot) |
| boot | 0x700000 | 38 MB | 14336 | Kernel + DTB (Android boot.img) |
| rootfs | 0x2d00000 | 64 MB | 92160 | Root filesystem (e.g. squashfs) |
| userdata | 0x6d00000 | ~18 MB | 110592 | Writable user data |

The area **0x0–0x200000 (2 MB)** is the **preloader** (IDBLOCK: DDR init + SPL), read directly by the RK3566 bootrom. Sectors are 512 bytes; sector = byte_offset / 512.

### Partition source

| Source | Description | Used by |
|--------|-------------|---------|
| cmdlinepart | `mtdparts=` in kernel command line | Stock (BSP) kernel |
| fixed-partitions | DTS node under `&sfc flash@0` | Mainline kernel |

Both yield five partitions with rootfs at `mtdblock3`. If you see six partitions, the kernel may be using cmdlinepart with different parsing — use `root=/dev/mtdblock4` or switch to DTS fixed-partitions.

---

## xrock setup

[xrock](https://github.com/xboot/xrock) reads and writes SPI NAND over USB in MASKROM mode. Build from source or follow [steward-fu’s xrock build guide](https://steward-fu.github.io/website/handheld/miyoo_flip_build_xrock.htm).

Host recovery with xrock is separate from stock running `miyoo355_fw.img`, from restoring a `mtd5-original-*.img` backup, and from erasing the preloader. Erasing the preloader is not the same thing as rebooting into USB download.

Upstream `xboot/xrock` at `50effcef229a7e8ff85fde916e635cdd58fe8c09` still sends 128 KiB USB bulk chunks with a 2 second timeout and receives a large buffer in one transfer. On a Linux host that fails against a Flip in MASKROM. [xrock-linux-bulk.patch](xrock-linux-bulk.patch) is a Flip-tested workaround for that revision: 32 KiB chunks and a 10 second timeout, on both send and receive. Apply it from a checkout of that commit:

```bash
patch -p1 < /path/to/xrock-linux-bulk.patch
```

It is not an upstream xrock requirement. Zlyme does not build or ship xrock.

---

## Entering MASKROM mode

1. Power off the device completely.
2. Hold the MASKROM button (see [steward-fu’s MASKROM guide](https://steward-fu.github.io/website/handheld/miyoo_flip_maskrom.htm) for button or solder point).
3. While holding, connect USB to the host.
4. Confirm with `lsusb` (Rockchip USB device).

**Without the button:** USB MASKROM on power-on is what the boot ROM does when it finds **no** valid loader. A blank SPI preloader is one missing loader. A card with its own idbloader, including a Zlyme card, is another loader, and the ROM can boot that card instead of USB. Measured on 2026-10-07: `flash_erase` of the preloader completed and the next boot did not enumerate USB MASKROM while a bootable Zlyme card was installed. The [preloader eraser](stock-rocknix-without-disassembly.md#preloader-eraser--maskrom-access) still removes the SPI preloader. It does not promise USB MASKROM by itself. Behaviour also varies with cable and port.

**From a running stock U-Boot, with the bottom USB-C already on the host:** the command `rbrom` stores `0xef08a53c` at `0xfdc20200` (PMUGRF OS register 0) and resets. The early SPL sees that word and returns to the boot ROM. That enumerated as USB `2207:350a` on 2026-10-06 and again on 2026-10-07, with a card inserted and with the battery connected. That is the proven software entry. It does not erase the preloader. A Zlyme Linux restart that wrote those same registers failed on 2026-10-07. On a running Zlyme root, `/usr/sbin/zlyme-maskrom` logged `Restarting system with command 'maskrom'` and the UART then stayed silent for more than four minutes: no DDR, no SPL, no U-Boot, and no USB `2207:350a`. A physical reset was required. The gadget was not attached before the request, so the log does not separate a failed reset from a boot-ROM entry the host could not see. That Linux path was removed. A later boot-file request for U-Boot `rbrom` was also removed. It was not measured. The measured software path that reached `2207:350a` without the MASKROM button is the [recovery preloader](recovery-preloader.md): the November 02 vendor SPL with a boot order of only the right-hand SD. A bootable card in that slot still boots. No bootable card there makes the SPL fail and reset to the boot ROM.

To keep internal stock boot *and* boot from SD, patch the preloader instead: [SD multiboot](sd-multiboot-apommel.md).

---

## Loading the loader

Before xrock can access flash, the RK3566 needs DDR init and a USB flash protocol. Two options:

**Option A — Combined loader** (from U-Boot build):

```bash
xrock download <path-to-rk356x_spl_loader_*.bin>
sleep 1
xrock flash
```

**Option B — DDR + usbplug** (from rkbin):

```bash
xrock extra maskrom \
    --rc4 off --sram rk3566_ddr_1056MHz_v1.18.bin --delay 10 \
    --rc4 off --dram rk356x_usbplug_v1.17.bin --delay 10
sleep 1
xrock flash
```

---

## Backup (before flashing)

```bash
# Preloader (2 MB)
xrock flash read 0 4096 preloader_backup.img

# U-Boot (4 MB)
xrock flash read 6144 8192 uboot_backup.img

# Boot (38 MB)
xrock flash read 14336 77824 boot_backup.img

# Rootfs (64 MB)
xrock flash read 92160 131072 rootfs_backup.img
```

A full 128 MB SPI NAND dump (e.g. from steward-fu releases) can be used for full restore.

---

## Flashing U-Boot

Only when you need to update U-Boot:

```bash
xrock flash write 6144 <your-uboot.img>
```

---

## Flashing boot and rootfs

After entering MASKROM and loading the loader:

```bash
xrock flash write 14336 <your-boot.img>
xrock flash write 92160 <your-rootfs.squashfs>
```

Replace with your actual boot image and rootfs image paths (from your build or distro).

---

## Restoring stock firmware

From a backup:

```bash
xrock flash write 0 preloader_backup.img
xrock flash write 6144 uboot_backup.img
```

From a full stock dump (128 MB), or when flashing stock software:

```bash
xrock flash write 0 <stock-full-dump.img>
```

---

## Boot flow

1. **Bootrom** reads IDBLOCK on SPI NAND, loads DDR init + SPL.
2. **SPL** tries boot sources in vendor numbering (MMC2 → MMC1 → MTD). Vendor MMC2 is the right-hand slot, `/dwmmc@fe2b0000`, which Linux calls MMC1. Loads U-Boot.
3. **U-Boot** typically runs `boot_android`: reads boot partition, finds Android boot image (kernel + DTB).
4. **Kernel** mounts rootfs from `/dev/mtdblock3` (squashfs or your rootfs type).

---

## boot.img format

U-Boot expects an **Android-format boot image** on the boot partition. Common layout (match your distro):

- Header v0, page size 2048
- Kernel at offset 0x00008000
- DTB as “second” at offset 0x00f00000
- Base address 0x10000000

The boot partition is 38 MB. If the kernel is large, use LZ4 compression so it fits.

---

## Erasing and the preloader

- **uboot, boot, rootfs:** `xrock flash erase` works. Example (boot):  
  `xrock flash erase 14336 77824`
- **Preloader (sectors 0–4095):** `xrock flash erase` does **not** clear the IDBLOCK (it is at raw NAND level). To remove the preloader (e.g. to force boot from SD), **write zeros**:

```bash
dd if=/dev/zero of=/tmp/zeros.img bs=512 count=4096
xrock flash write 0 /tmp/zeros.img
```

- **Whole 128 MB:** To erase everything (preloader + all partitions), write zeros to the full SPI NAND. After this the device will not boot from internal storage until you reflash (e.g. from SD or a full dump).

```bash
dd if=/dev/zero of=/tmp/zero_128mb.img bs=1M count=128
xrock flash write 0 /tmp/zero_128mb.img
rm /tmp/zero_128mb.img 
```

---

## Booting from SD

The recommended Zlyme install is to write `zlyme.img`, put it in the right-hand slot, and on an unprepared Flip boot stock once so the included `miyoo355_fw.img` can finish. Later updates are Settings → Update. The standalone multiboot helper is that same repair without a full Zlyme card: [preloader tools](preloader-tools.md).

The table below keeps the other ways to boot from SD. They are not substitutes for that install. Erasing the preloader is the historical method from the archived ROCKNIX fork. It removes internal stock boot. Host `xrock` is the PC recovery path once the boot ROM is already waiting.

| Path | What it does |
|------|----------------|
| Recovery preloader | [Recovery preloader](recovery-preloader.md). The vendor SPL boot order is the right-hand slot only. A bootable right card still boots. No bootable right card resets to the BootROM. The stock-side helper that derives this on the device is [preloader tools](preloader-tools.md). This is not the physical MASKROM button, not `rbrom`, and not the removed Zlyme marker experiments. |
| Stock-assisted card | A card whose boot FAT contains `miyoo355_fw.img`. Boot stock. Stock runs apommel's installer, which backs up and patches this unit's own preloader. A fresh Zlyme card already includes that file. The standalone names, which you rename to `miyoo355_fw.img`, are [preloader tools](preloader-tools.md). Writing the card does not modify NAND by itself. |
| Manual repaired preloader | [SD multiboot](sd-multiboot-apommel.md). Same apommel repair, as a technical explanation and the older on-device app. |
| Erase the preloader | [Preloader Eraser](stock-rocknix-without-disassembly.md#preloader-eraser--maskrom-access). Removes the SPI preloader. The next power-on enters USB MASKROM only when the boot ROM has no other valid loader. A bootable SD idbloader can boot instead. A Zlyme erase that does not complete tries to write the previous preloader back. A failed Zlyme restore does the same. Neither result is USB MASKROM. |
| Host `xrock` | This page. USB MASKROM recovery from a PC, including writing a saved preloader back. |

The procedure below is the **`xrock` from MASKROM** equivalent, for when you are already on a PC or the device will not boot at all. Like the eraser, zeroing the preloader destroys internal boot.

To boot from an SD card under that historical erase method: zero the preloader so the boot ROM falls through to SD. Optionally erase boot and uboot so internal storage is unused. The archived ROCKNIX fork used this. A repaired preloader does not.

**Boot scenarios:** With **zeroed preloader** + mainline SD → device boots from SD. With zeroed preloader and no SD → device stays in bootrom/MASKROM (not a brick). With stock/GammaOS preloader, U-Boot usually boots internal first.

**Why write zeros:** `xrock flash erase 0 4096` does not clear the preloader (IDBLOCK is at raw NAND level). Use `dd if=/dev/zero of=/tmp/zeros.img bs=512 count=4096` then `xrock flash write 0 /tmp/zeros.img`.

**Procedure:** (1) MASKROM + load loader + `xrock flash`. (2) `xrock flash erase 14336 77824` (boot). (3) `xrock flash erase 6144 8192` (uboot). (4) Write zeros to sectors 0–4095 (see above). (5) Insert SD, power on. The vendor SPL's MMC2 is `/dwmmc@fe2b0000`, the right-hand slot. Linux numbers that same controller MMC1. The left-hand slot is Linux MMC2 at `/dwmmc@fe2c0000`. Mainline U-Boot's `mmc` index is a third numbering. Historical log lines stay as captured. **GammaOS:** Same erase steps apply; zeroing the preloader avoids the SPL MMC timeout. **Restore internal:** `xrock flash write 0 preloader_backup.img` and `xrock flash write 6144 uboot_backup.img` (or full stock dump).

---

## mtdparts string

For kernel bootargs or U-Boot:

```
mtdparts=spi-nand0:0x100000@0x200000(vnvm),0x400000@0x300000(uboot),0x2600000@0x700000(boot),0x4000000@0x2d00000(rootfs),0x1260000@0x6d00000(userdata)
```
