# MASKROM and SD boot by erasing the preloader

> **This does not brick the device.** The SoC **bootrom** and **USB recovery (MASKROM)** are not stored in SPI. Worst case you have no convenient internal boot until you recover from a PC — that is **annoying**, not **permanent**.
>
> **You can always recover the usual way:** open the shell, use the **MASKROM** button (or test point), connect **USB**, and flash with **`xrock`** / **`rkdeveloptool`** like any other Miyoo Flip restore — same as [Flashing](flashing.md).

**If what you want is stock and an SD distro at the same time, you are on the wrong page.** [SD multiboot via a repaired preloader](sd-multiboot-apommel.md) does that without erasing anything, and official firmware updates survive it.

Erasing still has two jobs, and this page covers both:

- **reaching MASKROM without opening the device**
- getting a **stock-only** unit far enough to install the multiboot patch, which can only be written from ROCKNIX

Miyoo Flip **ROCKNIX** images are published as GitHub Actions artifacts on **[Zetarancio/distribution](https://github.com/Zetarancio/distribution)** branch **`flip`**. Use the **device-specific** build for this handheld. Tools: [`preloader-stock-rocknix/`](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/tree/main/preloader-stock-rocknix) in this repo.

---

## Instructions

### Before you start

| You need | Why |
|----------|-----|
| A microSD with a **ROCKNIX** image for Miyoo Flip (**device-specific** Actions build) | After the preloader is erased, the handheld boots from this SD. |
| The **`App/PreloaderEraser/`** folder | Does the erase, from stock or from ROCKNIX. |
| The **`App/apommel-multiboot/`** folder | To get internal boot back afterwards: it bundles a stock preloader and restores it with validation and rollback. |

### ROCKNIX on the SD card: `extlinux.conf` and the device tree

After you write a ROCKNIX image to the microSD, open the **boot** filesystem (the partition is often labeled **ROCKNIX** in disk utilities) and check **`ROCKNIX/extlinux/extlinux.conf`**. The **FDT** line must select the Miyoo Flip tree:

```text
FDT /device_trees/rk3566-miyoo-flip.dtb
```

If it still references another board's `rk3566-*.dtb`, change it, so the kernel, regulators and peripherals match this device. **Device-specific** artifacts from the `flip` branch usually ship the correct line already — still worth checking before the first SD boot. U-Boot reads this path when chainloading Linux.

### Preloader Eraser — MASKROM access

Erasing the preloader leaves the bootrom with nothing to load internally, which is what gives you **MASKROM on demand**:

| At power-on | Result |
|-------------|--------|
| **no SD card** | device comes up in **MASKROM** — connect USB and use `xrock` |
| **bootable SD card** | bootrom loads the **card's own** idbloader and boots that OS |

Everything an opened-case MASKROM session can do — full backup, restore, reflash — becomes reachable from software. The trade-off is that **internal stock boot is gone** until you write a preloader back, which needs ROCKNIX or a PC.

1. Copy **`PreloaderEraser`** from [`preloader-stock-rocknix/App/`](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/tree/main/preloader-stock-rocknix/App) to **`SDCARD/App/PreloaderEraser/`**.
   Optional: add **`icon.png`** next to `launch.sh` for a launcher icon (`config.json` references it).
2. Boot **stock** with that SD.
3. Launch **"Miyoo Flip MASKROM Access (Preloader Eraser)"**. It erases SPI NAND blocks **0–15** (first **2 MiB**) and **reboots**.
4. Power on with **no card** for MASKROM, or with a **ROCKNIX** card to boot ROCKNIX from SD.

Distros whose cards are built for **GammaLoader** (Knulli, GammaOS) still need this method rather than multiboot: see [distro compatibility](sd-multiboot-apommel.md#distro-compatibility).

### ROCKNIX → stock (restore the preloader)

Current Miyoo Flip images from the **`flip`** branch expose the **`preloader`** MTD partition (first 2 MiB), which is what makes writing possible there.

1. Copy the **`App/apommel-multiboot/`** folder onto a card (in ROCKNIX's file manager the cards appear under **`games-external`**).
2. Run it as **root**:
   - **File manager or Ports menu:** **Execute** on **`restore-preloader.sh`**.
   - **SSH:** `sh launch.sh restore` (or `sh launch.sh restore /path/to/image.img`).
3. **Reboot.** The device boots **stock** from internal SPI again.

The app picks the newest valid backup in its folder if there is one, otherwise its bundled **`preloader-stock.img`**. It validates the image, saves the current contents first, verifies the readback and rolls back on failure.

**A backup taken after an erase is not a restore point** — it is 2 MiB of `0xff`, and writing it back erases rather than restores. Anyone who used the eraser first has one. The app refuses them; if you are checking by hand, see [SD multiboot — a backup is not automatically a restore point](sd-multiboot-apommel.md#a-backup-is-not-automatically-a-restore-point).

If **`/proc/mtd`** does not list **`preloader`**, install a newer Miyoo Flip image from the same **`flip`** branch; older Actions builds may not expose that MTD name yet.

### If nothing boots

| Situation | Do this |
|-----------|---------|
| preloader erased, no bootable SD | plug **USB** into a host — the device usually enters **MASKROM** with no button press, ready for `xrock`. Behaviour varies with cable and port. |
| USB recovery does not appear | open the device, hold **MASKROM** ([steward-fu](https://steward-fu.github.io/website/handheld/miyoo_flip_maskrom.htm)), connect USB, run `xrock` as in [Flashing](flashing.md). This always works and depends on nothing in SPI. |
| you want to erase from a PC instead | zero the preloader from MASKROM with `xrock` — [Flashing — booting from SD](flashing.md#booting-from-sd). Usually needs hardware MASKROM, so disassembly. |

---

## Technical evidence

**Why the eraser needs the SFC on stock.** Stock's partitions come from `mtdparts=` on the kernel command line and start at `vnvm` (`0x200000`), so no `/dev/mtd*` covers the preloader region. The app drives the **SFC** directly through `devmem` / `/dev/mem` instead. Erase needs no ECC, which is why this works blind — a *write* would not, and that asymmetry is what forces the two-step bootstrap: [why stock cannot write the preloader](sd-multiboot-apommel.md#why-stock-cannot-write-the-preloader). On **ROCKNIX** the region is `mtd0`, so the script uses `flash_erase` there instead.

**How it fits the boot chain.** bootrom → preloader on SPI → U-Boot → kernel. Clearing the preloader makes the bootrom **fall through** to SD, or to MASKROM when there is no card. Diagram and offsets: [Boot and flash — boot chain](../boot-and-flash.md#boot-chain) · [SPI and boot chain](../stock-firmware-and-findings/spi-and-boot-chain.md).

**Sourcing a preloader image.** It is exactly the **first 2 MiB** of SPI (the IDBLOCK region), so any full NAND dump yields one: `dd if=spi_full_dump.img of=preloader-mine.img bs=512 count=4096`. Card OTA packages like `miyoo355_fw.img` will not do — they ship slices for uboot/boot/rootfs and contain **no preloader at all** ([why](../stock-firmware-and-findings/ota-update-mechanism.md)). The image bundled with the multiboot app is md5 `1d525e6e6c89bd788b5245c90c97833b`; its provenance is documented in [SD multiboot](sd-multiboot-apommel.md#provenance-of-the-bundled-stock-image).

---

## See also

| Topic | Link |
|--------|------|
| **Stock + SD distro at once (apommel's method)** | [SD multiboot via a repaired preloader](sd-multiboot-apommel.md) |
| Stock OTA internals, root-code hook | [OTA update mechanism](../stock-firmware-and-findings/ota-update-mechanism.md) |
| Partition layout, backup, `xrock` | [Flashing guide](flashing.md) |
| SD boot via erase, from a PC | [Flashing — booting from SD](flashing.md#booting-from-sd) |
| Boot chain and SPI regions | [Boot and flash (front)](../boot-and-flash.md) |
| ROCKNIX releases | [Zetarancio/distribution](https://github.com/Zetarancio/distribution) (`flip`) |
