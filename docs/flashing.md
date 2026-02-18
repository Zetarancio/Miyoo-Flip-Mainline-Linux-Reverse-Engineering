# Flashing & Partition Layout

## MTD Partition Table

The Miyoo Flip's 128 MB SPI NAND is divided into 5 partitions:

| Partition | Byte Offset | Size | Sector | Purpose |
|-----------|-------------|------|--------|---------|
| vnvm | 0x200000 | 1 MB | 4096 | Non-volatile storage |
| uboot | 0x300000 | 4 MB | 6144 | U-Boot FIT (ATF + OP-TEE + U-Boot) |
| boot | 0x700000 | 38 MB | 14336 | Kernel + DTB (Android boot.img) |
| rootfs | 0x2d00000 | 64 MB | 92160 | Root filesystem (squashfs) |
| userdata | 0x6d00000 | ~18 MB | 110592 | Writable user data |

The area 0x0-0x200000 (2 MB) is the **preloader** (IDBLOCK: DDR init + SPL),
read directly by the RK3566 bootrom.

Sectors are 512 bytes. Sector = byte_offset / 512.

### Partition Source

| Source | Description | Used By |
|--------|-------------|---------|
| cmdlinepart | `mtdparts=` in kernel command line | Stock (BSP) kernel |
| fixed-partitions | DTS node under `&sfc flash@0` | Mainline kernel |

Both produce 5 partitions with rootfs at `mtdblock3`. If you see 6
partitions instead of 5, the kernel is using cmdlinepart with different
parsing -- set `root=/dev/mtdblock4` or switch to DTS fixed-partitions.

## xrock Setup

[xrock](https://github.com/xboot/xrock) is the tool for reading/writing
SPI NAND via USB in MASKROM mode. Build it from source or use
[steward-fu's build guide](https://steward-fu.github.io/website/handheld/miyoo_flip_build_xrock.htm).

## Entering MASKROM Mode

1. Power off the device completely.
2. Hold the MASKROM button (see [steward-fu's guide](https://steward-fu.github.io/website/handheld/miyoo_flip_maskrom.htm)
   for the exact button / solder point).
3. While holding, insert USB cable to host PC.
4. Verify: `lsusb` should show a Rockchip USB device.

## Loading the Loader

Before xrock can access flash, the RK3566 needs DDR init and a USB
flash protocol handler. Two options:

**Option A -- Combined loader** (from U-Boot build):
```bash
xrock download output/rk356x_spl_loader_v1.23.114.bin
sleep 1
xrock flash
```

**Option B -- DDR + usbplug** (from rkbin):
```bash
xrock extra maskrom \
    --rc4 off --sram rk3566_ddr_1056MHz_v1.18.bin --delay 10 \
    --rc4 off --dram rk356x_usbplug_v1.17.bin --delay 10
sleep 1
xrock flash
```

## Backup (Before Flashing)

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

The stock firmware `Extra/spi_20241119160817.img` (128 MB, from
`setup-extra.sh --all`) is a complete SPI NAND dump for full restore.

## Flashing U-Boot

```bash
xrock flash write 6144 output/uboot.img
```

Only flash U-Boot when you need to update it. Normally you only flash
boot + rootfs.

## Flashing Boot + Rootfs

```bash
# Enter MASKROM, load loader, connect flash (see above), then:
xrock flash write 14336 output/boot.img
xrock flash write 92160 output/rootfs.squashfs
```

### One-liner

```bash
xrock download output/rk356x_spl_loader_v1.23.114.bin && \
  sleep 1 && xrock flash && sleep 1 && \
  xrock flash write 14336 output/boot.img && \
  xrock flash write 92160 output/rootfs.squashfs
```

## Restoring Stock Firmware

```bash
# From backup
xrock flash write 0 preloader_backup.img
xrock flash write 6144 uboot_backup.img

# From stock dump (full restore)
xrock flash write 0 Extra/spi_20241119160817.img

# From individual partition images
xrock flash write 6144 Extra/spi_20241119160817_uboot.img
```

## Boot Flow

1. **Bootrom** finds IDBLOCK on SPI NAND, loads DDR init + SPL.
2. **SPL** tries boot sources: MMC2 -> MMC1 -> MTD1. Loads U-Boot.
3. **U-Boot** runs `boot_android`: reads boot partition, finds Android
   boot image with kernel + DTB.
4. **Kernel** mounts rootfs from `/dev/mtdblock3` (squashfs).

## boot.img Format

U-Boot expects an **Android-format boot image** on the boot partition.
The `build-boot-img.sh` script creates this using `mkbootimg` from the
steward-fu U-Boot sources (`Extra/miyoo-flip-main/u-boot/scripts/mkbootimg`).

Layout (matching stock):
- Header v0, page size 2048
- Kernel at offset 0x00008000
- DTB as "second" at offset 0x00f00000
- Base address 0x10000000

The boot partition is 38 MB. If the uncompressed kernel exceeds ~36 MB,
use LZ4 compression (the build script handles this automatically).

## Notes on `xrock flash erase`

- Works for uboot, boot, and rootfs partitions.
- Does **NOT** work for the preloader (IDBLOCK area, sectors 0-4095).
  The IDBLOCK is at the raw NAND level, below xrock's logical erase.
- To destroy the preloader, write zeros:
  ```bash
  dd if=/dev/zero of=/tmp/zeros.img bs=512 count=4096
  xrock flash write 0 /tmp/zeros.img
  ```

## mtdparts String

For kernel bootargs or U-Boot:

```
mtdparts=spi-nand0:0x100000@0x200000(vnvm),0x400000@0x300000(uboot),0x2600000@0x700000(boot),0x4000000@0x2d00000(rootfs),0x1260000@0x6d00000(userdata)
```
