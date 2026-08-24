# Try ROCKNIX (and return to stock) without opening the device

> **This does not brick the device.** The SoC **bootrom** and **USB recovery (MASKROM)** are not stored in SPI. Worst case you have no convenient internal boot until you recover from a PC — that is **annoying**, not **permanent**.
>
> **You can always recover the usual way:** open the shell, use the **MASKROM** button (or test point), connect **USB**, and flash with **`xrock`** / **`rkdeveloptool`** like any other Miyoo Flip restore — same as [Flashing](flashing.md). The flow on this page is an **extra** option so you can switch **stock ↔ ROCKNIX** **without** taking the device apart for that step.

Miyoo Flip **ROCKNIX** images are published as GitHub Actions artifacts on **[Zetarancio/distribution](https://github.com/Zetarancio/distribution)** branch **`flip`**. Use the **device-specific** build for this handheld.

---

## Prefer multiboot: you no longer have to choose

**[SD multiboot via a repaired preloader](sd-multiboot-apommel.md)** keeps **stock on internal NAND** *and* boots an SD distro when a card is inserted — nothing is erased, and official firmware updates survive it. Method by **[apommel](https://github.com/apommel/baseos-my355)**.

The erase-based flow on this page still matters for two things: **reaching MASKROM without opening the device**, and getting a stock-only unit far enough to install the multiboot patch (which can only be written from ROCKNIX).

---

## At a glance

| Goal | What you do | Result |
|-----------|----------------|--------|
| **Stock + SD distro (recommended)** | Run **`App/apommel-multiboot/`** from **ROCKNIX**. | Card inserted → SD; no card → **stock**. See [SD multiboot](sd-multiboot-apommel.md). |
| **MASKROM access** | Copy **`App/PreloaderEraser/`** to `SDCARD/App/`, run it on **stock**. | With **no card**, the device powers on into **MASKROM**. With a bootable card, it boots that card. |
| **Back to stock only** | On **ROCKNIX**, run **`restore-preloader.sh`** from **`App/apommel-multiboot/`**, then reboot. | **Restores** the first 2 MiB of SPI → **stock from internal NAND** again. |

**Tools:** [`preloader-stock-rocknix/`](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/tree/main/preloader-stock-rocknix) in this wiki repo.

---

## Before you start

| You need | Why |
|----------|-----|
| A microSD with a **ROCKNIX** image for Miyoo Flip (**device-specific** Actions build) | After the preloader is erased, the handheld boots from this SD. |
| The **`PreloaderEraser`** app folder (from the tools repo above) | For **MASKROM access**, and to get a stock-only unit onto ROCKNIX. |
| The **`apommel-multiboot`** app folder | For **ROCKNIX → stock**: it bundles **`preloader-stock.img`** and restores it with validation and rollback. Optional: your own 2 MiB extract from a **full SPI dump** — see [About the bundled stock preloader](#about-the-bundled-stock-preloader) below. |

Card OTA packages like **`miyoo355_fw.img`** are **not** a full raw SPI dump and **do not** contain the bootrom preloader slice by themselves — use the bundled **`preloader-stock.img`**, or extract from a **full** backup you trust.

---

## ROCKNIX on the SD card: `extlinux.conf` and the device tree

After you write a ROCKNIX image to the microSD, open the **boot** filesystem (the partition is often labeled **ROCKNIX** in disk utilities). Edit:

**`ROCKNIX/extlinux/extlinux.conf`**

Ensure the **FDT** line selects the Miyoo Flip tree:

```text
FDT /device_trees/rk3566-miyoo-flip.dtb
```

If the file still references another board’s `rk3566-*.dtb`, change it to **`rk3566-miyoo-flip.dtb`** so the kernel, regulators, and peripherals match this device. **Device-specific** Miyoo Flip artifacts from the distribution **`flip`** branch may already ship the correct line—still worth checking before the first SD boot.

U-Boot reads this path when chainloading Linux from the SD layout described in ROCKNIX’s standard `extlinux` setup.

---

## Preloader Eraser — MASKROM access

Erasing the preloader leaves the bootrom with nothing to load internally, which is what gives you **MASKROM on demand**:

| At power-on | Result |
|-------------|--------|
| **no SD card** | device comes up in **MASKROM** — connect USB and use `xrock` |
| **bootable SD card** | bootrom loads the **card's own** idbloader and boots that OS |

Everything an opened-case MASKROM session can do — full backup, restore, reflash — becomes reachable from software. The trade-off is that **internal stock boot is gone** until you write a preloader back, which needs ROCKNIX or a PC.

1. Copy **`PreloaderEraser`** from [`preloader-stock-rocknix/App/`](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/tree/main/preloader-stock-rocknix/App) to **`SDCARD/App/PreloaderEraser/`**.  
   Optional: add **`icon.png`** next to `launch.sh` if you want a launcher icon (`config.json` references it).
2. Boot **stock** with that SD (or use internal + SD with the app on card — follow your usual stock layout for `App/`).
3. Launch **“Miyoo Flip MASKROM Access (Preloader Eraser)”**. It erases SPI NAND blocks **0–15** (first **2 MiB**) and **reboots**.
4. Power on with **no card** for MASKROM, or with a **ROCKNIX** card to boot ROCKNIX from SD.

**Why it needs the SFC on stock:** stock's partitions come from `mtdparts=` on the kernel command line and start at `vnvm` (`0x200000`), so no `/dev/mtd*` covers the preloader; the app drives the **SFC** directly (`devmem` / `/dev/mem`). Erase needs no ECC, which is why this works blind — a *write* would not. On **ROCKNIX** the region is `mtd0`, and the script uses `flash_erase` there instead.

**How it fits the boot chain:** bootrom → preloader on SPI → … Clearing the preloader makes the bootrom **fall through** to **SD**, or to MASKROM when there is no card. Diagram and offsets: [Boot and flash — Boot chain](../boot-and-flash.md#boot-chain) · [SPI and boot chain](../stock-firmware-and-findings/spi-and-boot-chain.md).

**For dual boot, use [SD multiboot](sd-multiboot-apommel.md) instead** — it repairs the preloader rather than destroying it, so stock keeps working. Distros whose cards are built for **GammaLoader** (Knulli, GammaOS) currently still need this erase method: see [distro compatibility](sd-multiboot-apommel.md#distro-compatibility).

---

## ROCKNIX → stock (restore preloader)

Current Miyoo Flip images from **[Zetarancio/distribution](https://github.com/Zetarancio/distribution)** branch **`flip`** expose the **`preloader`** MTD partition (first 2 MiB). Restoring uses **`flash_erase`** and **`nandwrite`** on that node, which is what the multiboot app does in restore mode.

1. Copy the **`App/apommel-multiboot/`** folder onto a card (in ROCKNIX's file manager the cards appear under **`games-external`**).
2. Run it as **root**:
   - **File manager or Ports menu:** **Execute** on **`restore-preloader.sh`**.
   - **SSH:** `sh launch.sh restore` (or `sh launch.sh restore /path/to/image.img`).
3. **Reboot.** The device should boot **stock** from internal SPI again.

The app picks the newest valid backup in its folder if there is one, otherwise the bundled **`preloader-stock.img`**. It validates the image, saves the current contents first, verifies the readback and rolls back on failure. Full behaviour: [`App/apommel-multiboot/README.md`](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/tree/main/preloader-stock-rocknix/App/apommel-multiboot).

If **`/proc/mtd`** does not list **`preloader`**, install a newer Miyoo Flip image from the same **`flip`** branch; older Actions builds may not expose that MTD name yet.

**Watch out for blank “backups”.** A preloader image captured while the region was **erased** is 2 MiB of `0xff` (md5 `b23b5d09162b92c0284923a7f628d2a5`) and writing it back erases rather than restores. Anyone who used the eraser first will have one. Check with `dd if=IMG bs=1 skip=131072 count=4` — it must print `RKNS`. Details: [SD multiboot — restoring](sd-multiboot-apommel.md#a-backup-is-not-automatically-a-restore-point).

---

## About the bundled stock preloader

- It is exactly the **first 2 MiB** of SPI (IDBLOCK region), e.g. from a full NAND dump.
- This repo **includes** a copy as **`preloader-stock-rocknix/App/apommel-multiboot/preloader-stock.img`** (md5 `1d525e6e6c89bd788b5245c90c97833b`). Provenance: [SD multiboot — provenance of the bundled stock image](sd-multiboot-apommel.md#provenance-of-the-bundled-stock-image).
- To build your own from a raw dump on a PC:

```bash
dd if=spi_full_dump.img of=preloader-mine.img bs=512 count=4096
```

then `sh launch.sh restore preloader-mine.img` on the device.

**Important:** **`miyoo355_fw`**-style card images are **not** raw SPI dumps; they ship slices for uboot/boot/rootfs but **not** this bootrom region, so they are **not** enough by themselves to mint a preloader image from scratch.

---

## MASKROM without disassembly (recovery / flashing)

With the preloader **erased** or invalid and **no bootable SD**, plugging **USB** into a host often enters **MASKROM** without pressing the hardware button — useful for **`xrock`** recovery. Behaviour can vary with cable and port; if USB recovery does not appear, use **MASKROM + flash** the classic way below.

---

## If USB recovery is awkward: disassemble and MASKROM (always works)

This is the **standard** Miyoo Flip recovery: open the device, hold **MASKROM** (see [steward-fu MASKROM](https://steward-fu.github.io/website/handheld/miyoo_flip_maskrom.htm)), connect USB, run **`xrock`** as in [Flashing](flashing.md). **No special dependency** on the preloader app — you can **always** return the device to a known state that way.

---

## Alternative: clear preloader only with xrock

You can instead zero the preloader from **MASKROM** with **`xrock`** — see [Boot from SD](boot-from-sd.md). That path usually needs **hardware MASKROM** (often **disassembly**).

---

## See also

| Topic | Link |
|--------|------|
| **Stock + SD distro at once (apommel's method)** | [SD multiboot via a repaired preloader](sd-multiboot-apommel.md) |
| Stock OTA internals, root-code hook | [OTA update mechanism](../stock-firmware-and-findings/ota-update-mechanism.md) |
| Partition layout, backup, `xrock` | [Flashing guide](flashing.md) |
| SD boot via erase (classic) | [Boot from SD](boot-from-sd.md) |
| Boot chain and SPI regions | [Boot and flash (front)](../boot-and-flash.md) |
| ROCKNIX releases | [Zetarancio/distribution](https://github.com/Zetarancio/distribution) (`flip`) |
