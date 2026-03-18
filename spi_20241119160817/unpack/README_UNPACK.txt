spi_20241119160817.img unpack (same idea as miyoo355_fw unpack)
================================================================

Source: GPT SPI flash image (128 MiB).

Partitions (from parted):
  vnvm     0x200000  - 0x300000   -> vnvm.img (1 MiB)
  uboot    0x300000  - 0x700000   -> uboot.img
  boot     0x700000  - ~0x2cff000 -> boot.img (Android bootimg)
  rootfs   ~0x2cff000 - ...      -> rootfs.img (squashfs)
  userdata ...                  -> userdata.img (erased 0xCC in this dump;
                                   on device = /userdata ext4 with joypad.config)

Joystick study bundle: unpack/joystick_study/
  - miyoo_inputd.c, stock miyoo_inputd/MainUI/factory_test, example configs

Extract commands (512-byte sectors):
  dd if=spi_20241119160817.img of=vnvm.img     bs=512 skip=4096  count=2048
  dd if=spi_20241119160817.img of=uboot.img   bs=512 skip=6144  count=8192
  dd if=spi_20241119160817.img of=boot.img    bs=512 skip=14336 count=77824
  dd if=spi_20241119160817.img of=rootfs.img  bs=512 skip=92160 count=131072
  dd if=spi_20241119160817.img of=userdata.img bs=512 skip=223232 count=37855

boot.img:
  abootimg -x boot.img  -> zImage (LZ4-compressed kernel), bootimg.cfg
  DTB is appended after page-aligned kernel in boot.img (offset 0xEE0000):
    dd if=boot.img of=spi_20241119.dtb bs=1 skip=15611904 count=97210
  dtc -I dtb -O dts spi_20241119.dtb -o spi_20241119.dts

rootfs.img:
  unsquashfs -d rootfs -f rootfs.img

Date in squashfs: 2024-11-19 (matches spi_20241119160817).
