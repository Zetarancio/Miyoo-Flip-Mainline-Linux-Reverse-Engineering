miyoo355_fw_20250527.img unpack
================================

Source: official Miyoo 355 card-flash image (ASCII header: model:miyoo355, version:20250527210639).

Layout (offsets are byte offsets into miyoo355_fw.img; validated against prior internal 20250509 unpack):

  uboot     0x00100000 (1 MiB)   -> uboot.img (7 340 032 bytes)
  boot      0x00800000 (8 MiB)   -> boot.img   (72 MiB, Android bootimg v0)
  rootfs    0x05000000 (80 MiB) -> rootfs.img (squashfs; image may end before
                                full 52 400 128-byte slice — use actual file size)

boot.img:
  abootimg -x boot.img  -> zImage, bootimg.cfg, initrd.img (ramdisk size 0)

Device trees (two appended DTBs after kernel, same offsets as 20250509):
  Primary @ 0x22f5800 (97 246 bytes), secondary @ 0x23c2a00 (97 261 bytes).
  Extract with a DTB header walk (magic d0 0d fe ed + big-endian totalsize),
  then: dtc -I dtb -O dts -o <name>.dts <name>.dtb

rootfs:
  unsquashfs -d rootfs -f rootfs.img

Notes:
  - This 20250527 .img is ~135 MiB vs ~136 MiB for 20250509; rootfs partition
    slice is shorter but contains a complete squashfs.
  - zImage and uboot.img differ from 20250509; primary DTB differs slightly (see DTS diff).
