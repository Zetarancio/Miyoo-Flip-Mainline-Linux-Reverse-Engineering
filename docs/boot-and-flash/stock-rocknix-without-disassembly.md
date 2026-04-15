# Try ROCKNIX (and return to stock) without opening the device

> **This does not brick the device.** The SoC **bootrom** and **USB recovery (MASKROM)** are not stored in SPI. Worst case you have no convenient internal boot until you recover from a PC — that is **annoying**, not **permanent**.
>
> **You can always recover the usual way:** open the shell, use the **MASKROM** button (or test point), connect **USB**, and flash with **`xrock`** / **`rkdeveloptool`** like any other Miyoo Flip restore — same as [Flashing](flashing.md). The flow on this page is an **extra** option so you can switch **stock ↔ ROCKNIX** **without** taking the device apart for that step.

Miyoo Flip **ROCKNIX** images are published as GitHub Actions artifacts on **[Zetarancio/distribution](https://github.com/Zetarancio/distribution)** branch **`flip`**. Use the **device-specific** build for this handheld.

---

## At a glance: stock ↔ ROCKNIX

| Direction | What you do | Result |
|-----------|----------------|--------|
| **Stock → ROCKNIX** | Copy **`App/PreloaderEraser/`** to `SDCARD/App/`, run the app on **stock**; reboot with a **ROCKNIX** SD inserted. | Bootrom skips invalid internal preloader → **boots ROCKNIX from SD**. |
| **ROCKNIX → stock** | On **ROCKNIX**, run **`preloader-restore/write-preloader-mtd.sh`** (with **`preloader.img`** beside it — **included in this repo**), then reboot. | **Restores** the first 2 MiB of SPI → **stock from internal NAND** again. |

**Tools:** [`preloader-stock-rocknix/`](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/tree/main/preloader-stock-rocknix) in this wiki repo.

---

## Before you start

| You need | Why |
|----------|-----|
| A microSD with a **ROCKNIX** image for Miyoo Flip (**device-specific** Actions build) | After the preloader is erased, the handheld boots from this SD. |
| The **`PreloaderEraser`** app folder (from the tools repo above) | Only for the **stock → ROCKNIX** step. |
| **`write-preloader-mtd.sh`** + **`preloader.img`** (same folder; **`preloader.img`** is in **`preloader-restore/`** in this repo) | For **ROCKNIX → stock**. Optional: your own 2 MiB extract from a **full SPI dump** if you prefer — see [About `preloader.img`](#about-preloaderimg). |

Card OTA packages like **`miyoo355_fw.img`** are **not** a full raw SPI dump and **do not** contain the bootrom preloader slice by themselves — use the **`preloader.img`** supplied here, or extract from a **full** backup you trust.

---

## Stock → ROCKNIX (erase preloader from stock)

1. Copy **`PreloaderEraser`** from [`preloader-stock-rocknix/App/`](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/tree/main/preloader-stock-rocknix/App) to **`SDCARD/App/PreloaderEraser/`**.  
   Optional: add **`icon.png`** next to `launch.sh` if you want a launcher icon (`config.json` references it).
2. Boot **stock** with that SD (or use internal + SD with the app on card — follow your usual stock layout for `App/`).
3. Launch **“Miyoo Flip Preloader Eraser”**. The app erases SPI NAND blocks **0–15** (first **2 MiB**) via the **SFC** (`devmem` / `/dev/mem`; stock does not expose this region as `/dev/mtd*`), then **reboots**.
4. After reboot, boot with the SD that contains **ROCKNIX** (idbloader + U-Boot + rootfs). The device should **boot ROCKNIX from SD**.

**How it fits the boot chain:** bootrom → preloader on SPI → … Clearing the preloader makes the bootrom **fall through** to **SD**. Diagram and offsets: [Boot and flash — Boot chain](../boot-and-flash.md#boot-chain) · [SPI and boot chain](../stock-firmware-and-findings/spi-and-boot-chain.md).

---

## ROCKNIX → stock (restore preloader)

Current Miyoo Flip images from **[Zetarancio/distribution](https://github.com/Zetarancio/distribution)** branch **`flip`** expose the **`preloader`** MTD partition (first 2 MiB). The restore script uses **`flash_eraseall`** and **`nandwrite`** on that node.

1. Copy **`write-preloader-mtd.sh`** and **`preloader.img`** into the **same folder** on the device (e.g. `/tmp/` over **SSH**, or e.g. under **`roms/`** on the SD card).
2. Run as **root**:
   - **SSH:** `chmod +x write-preloader-mtd.sh && ./write-preloader-mtd.sh`  
     (or `./write-preloader-mtd.sh /path/to/preloader.img`)
   - **Commander:** **Execute** on `write-preloader-mtd.sh` (default image is **`preloader.img`** next to the script).
3. **Reboot.** The device should boot **stock** from internal SPI again.

**Script:** [`preloader-stock-rocknix/preloader-restore/write-preloader-mtd.sh`](https://github.com/Zetarancio/Miyoo-Flip-Mainline-Linux-Reverse-Engineering/blob/main/preloader-stock-rocknix/preloader-restore/write-preloader-mtd.sh).

If **`/proc/mtd`** does not list **`preloader`**, install a newer Miyoo Flip image from the same **`flip`** branch; older Actions builds may not expose that MTD name yet.

---

## About `preloader.img`

- It is exactly the **first 2 MiB** of SPI (IDBLOCK region), e.g. from a full NAND dump.
- This repo **includes** a copy under **`preloader-stock-rocknix/preloader-restore/preloader.img`** for the restore script.
- To build your own from a raw dump on a PC:

```bash
dd if=spi_full_dump.img of=preloader.img bs=512 count=4096
```

Or: **`extract-preloader-from-spi-dump.sh`** in the same folder.

**Important:** **`miyoo355_fw`**-style card images are **not** raw SPI dumps; they ship slices for uboot/boot/rootfs but **not** this bootrom region, so they are **not** enough by themselves to mint a new `preloader.img` from scratch.

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
| Partition layout, backup, `xrock` | [Flashing guide](flashing.md) |
| SD boot via erase (classic) | [Boot from SD](boot-from-sd.md) |
| Boot chain and SPI regions | [Boot and flash (front)](../boot-and-flash.md) |
| ROCKNIX releases | [Zetarancio/distribution](https://github.com/Zetarancio/distribution) (`flip`) |
