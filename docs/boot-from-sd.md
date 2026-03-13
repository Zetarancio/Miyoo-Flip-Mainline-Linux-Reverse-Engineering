# Booting from SD

To boot the Miyoo Flip from an SD card (e.g. ROCKNIX) instead of internal SPI NAND, use **xrock** to erase the boot and uboot partitions or **zero the preloader** so the bootrom falls through to SD.

**Steps (with xrock):**

1. Enter [MASKROM](flashing.md#entering-maskrom-mode) and [load the loader](flashing.md#loading-the-loader), then `xrock flash`.
2. Erase boot: `xrock flash erase 14336 77824`
3. Erase uboot: `xrock flash erase 6144 8192`
4. Zero the preloader (erase does not clear it):  
   `dd if=/dev/zero of=/tmp/zeros.img bs=512 count=4096`  
   `xrock flash write 0 /tmp/zeros.img`
5. Insert your SD (mainline image with idbloader/U-Boot/extlinux), disconnect USB, power on.

**Backup first.** Restore internal boot by reflashing preloader and uboot — see [Flashing](flashing.md) (backup, restore, partition layout, and the full [Booting from SD](flashing.md#booting-from-sd) section).
