# Booting from SD card

How to make the Miyoo Flip boot from an SD card instead of internal SPI NAND. Useful for mainline distros (e.g. ROCKNIX) that provide an SD image with U-Boot and extlinux. No information is lost: you can restore internal boot by reflashing the preloader and U-Boot.

---

## Boot scenarios

| SPI NAND state | SD card | Result |
|----------------|---------|--------|
| Stock preloader + U-Boot | No SD | Boots stock Miyoo OS |
| Stock preloader + U-Boot | Mainline SD (e.g. ROCKNIX) | Boots from internal (U-Boot often finds internal boot first) |
| Third-party preloader (e.g. GammaOS) + U-Boot | Mainline SD | Same: internal boot usually wins |
| **Zeroed preloader** | Mainline SD | **Boots from SD** (bootrom falls back to SD) |
| Zeroed preloader | No SD | Device stays in bootrom/MASKROM (not a brick) |

So: to boot from SD on power-on, you **zero the preloader** (and optionally erase boot/uboot so nothing on SPI NAND is used). With a zeroed preloader, the bootrom does not find a valid IDBLOCK on SPI NAND and falls through to SD.

---

## Why not just “erase” the preloader?

`xrock flash erase 0 4096` reports success but the preloader **remains**. The IDBLOCK lives at raw NAND level; xrock’s logical erase does not clear it. You must **write zeros** to sectors 0–4095 to remove it.

---

## Full procedure: boot from SD on power-on

### Prerequisites

- xrock installed and working
- SD card prepared with your mainline distro (e.g. ROCKNIX: correct layout, `rk3566-miyoo-flip.dtb`, extlinux)
- SPI NAND backup (see [Flashing](flashing.md))

### Steps

```bash
# 1. Enter MASKROM, load loader, connect flash
xrock download <path-to-loader.bin>
sleep 1 && xrock flash && sleep 1

# 2. Erase boot partition (remove internal kernel)
xrock flash erase 14336 77824

# 3. Erase uboot partition (remove internal U-Boot)
xrock flash erase 6144 8192

# 4. Zero the preloader (so bootrom falls through to SD)
dd if=/dev/zero of=/tmp/zeros.img bs=512 count=4096
xrock flash write 0 /tmp/zeros.img

# 5. Insert SD card, disconnect USB, power on
```

The device will load the idbloader (DDR + SPL) from the SD card, then U-Boot and kernel per the SD layout (e.g. extlinux). Slot mapping: SPL often uses MMC2 (left slot), U-Boot may use MMC1 (right slot) — see [Serial — SD slot mapping](serial.md).

---

## GammaOS bootloader (optional context)

Some users install the [GammaOS bootloader](https://github.com/TheGammaSqueeze/GammaOSCore/releases) (`GammaLoaderMiyooFlip.zip`), which writes a new preloader and U-Boot. That U-Boot often uses `boot_android` and still boots the **internal** boot partition if it contains a valid image. So even with GammaOS:

- **Erase the boot partition** (step 2 above) if you want to force boot from SD.
- **Zero the preloader** (step 4) if you want the bootrom to skip SPI NAND and boot from SD directly. GammaOS SPL can also have short MMC timeout (~9 ms); many cards need 50–250 ms, which can cause “Card did not respond to voltage select!”. Zeroing the preloader avoids that by having the bootrom load from SD.

---

## Restoring internal (stock or GammaOS) boot

```bash
# From your backup
xrock flash write 0 preloader_backup.img
xrock flash write 6144 uboot_backup.img

# From a full stock dump
xrock flash write 0 <stock-full-dump.img>
```

Then reflash boot/rootfs as needed (see [Flashing](flashing.md)).

---

## Important notes

- With a **zeroed preloader**, the device will not boot without an SD card; it stays in bootrom/MASKROM. That is **not a brick** — insert a prepared SD or use xrock to write back the preloader.
- **`xrock flash erase`** works for uboot, boot, and rootfs but **not** for the preloader. Always use **write zeros** for sectors 0–4095 when you want to remove the preloader.
