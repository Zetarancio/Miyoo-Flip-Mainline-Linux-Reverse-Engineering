# Flashing and partition layout

Generic guide to flashing the Miyoo Flip SPI NAND: partition layout, xrock, MASKROM, backup, and restore. For **booting from SD** with xrock, see [Boot from SD](boot-from-sd.md). For a quick overview, see the [Boot and flash](../boot-and-flash.md) front page.

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

---

## Entering MASKROM mode

1. Power off the device completely.
2. Hold the MASKROM button (see [steward-fu’s MASKROM guide](https://steward-fu.github.io/website/handheld/miyoo_flip_maskrom.htm) for button or solder point).
3. While holding, connect USB to the host.
4. Confirm with `lsusb` (Rockchip USB device).

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

From a full stock dump (128 MB):

```bash
xrock flash write 0 <stock-full-dump.img>
```

---

## Boot flow

1. **Bootrom** reads IDBLOCK on SPI NAND, loads DDR init + SPL.
2. **SPL** tries boot sources (e.g. MMC2 → MMC1 → MTD). Loads U-Boot.
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
```

---

## Booting from SD

See [Boot from SD](boot-from-sd.md) for a brief xrock procedure. Below: scenarios, why write zeros, and restore.

To boot from an SD card (e.g. ROCKNIX) instead of internal SPI NAND: zero the preloader so the bootrom falls through to SD. Optionally erase boot and uboot so internal storage is unused.

**Boot scenarios:** With **zeroed preloader** + mainline SD → device boots from SD. With zeroed preloader and no SD → device stays in bootrom/MASKROM (not a brick). With stock/GammaOS preloader, U-Boot usually boots internal first.

**Why write zeros:** `xrock flash erase 0 4096` does not clear the preloader (IDBLOCK is at raw NAND level). Use `dd if=/dev/zero of=/tmp/zeros.img bs=512 count=4096` then `xrock flash write 0 /tmp/zeros.img`.

**Procedure:** (1) MASKROM + load loader + `xrock flash`. (2) `xrock flash erase 14336 77824` (boot). (3) `xrock flash erase 6144 8192` (uboot). (4) Write zeros to sectors 0–4095 (see above). (5) Insert SD, power on. SPL often loads from MMC2 (left slot), U-Boot from MMC1 (right) — see [Serial — SD slot mapping](../serial.md). **GammaOS:** Same steps apply; zeroing preloader avoids SPL MMC timeout. **Restore internal:** `xrock flash write 0 preloader_backup.img` and `xrock flash write 6144 uboot_backup.img` (or full stock dump).

---

## mtdparts string

For kernel bootargs or U-Boot:

```
mtdparts=spi-nand0:0x100000@0x200000(vnvm),0x400000@0x300000(uboot),0x2600000@0x700000(boot),0x4000000@0x2d00000(rootfs),0x1260000@0x6d00000(userdata)
```
