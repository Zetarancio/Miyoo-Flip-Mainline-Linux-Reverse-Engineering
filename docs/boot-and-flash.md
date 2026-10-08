# Boot and flash

How the Miyoo Flip boots, where images come from, how to flash the SPI NAND, and how to boot from SD.

---

## Install Zlyme

Write `zlyme.img` and put the card in the right-hand slot, next to the power button. On a Flip that has never been prepared for SD boot, turn it on so stock can run the `miyoo355_fw.img` included on that card. Stock updates this unit's preloader. The next boot from the right-hand slot starts Zlyme. Writing the card does not itself modify NAND. Full steps: [Zlyme's install guide](https://github.com/Zetarancio/zlyme#install).

You do not need the apommel internals page for that install. [Preloader tools](boot-and-flash/preloader-tools.md) is the page for the three standalone helpers (SD boot, recovery preloader, restore this unit's original). [SD multiboot](boot-and-flash/sd-multiboot-apommel.md) keeps the technical explanation and the manual app.

With the normal repaired preloader: no card boots stock from NAND; a bootable card in the right-hand slot boots that OS. The published zlyme44 image does not contain `miyoo355_fw.img`. For that image, use the standalone helper once it is on the [Zlyme releases page](https://github.com/Zetarancio/zlyme/releases), or the manual steps on the multiboot page.

## Other boot and recovery paths

These are not the Zlyme install.

| Path | When it applies |
|------|-----------------|
| [Recovery preloader](boot-and-flash/recovery-preloader.md) | Right-hand slot only. A bootable card there still boots. No bootable card there resets to the boot ROM. |
| [Erase the preloader](boot-and-flash/stock-rocknix-without-disassembly.md) | Historical path used to reach USB MASKROM or an SD loader by removing the SPI preloader. A blank preloader is not USB MASKROM while another loader can boot. |
| [Physical MASKROM and xrock](boot-and-flash/flashing.md) | Last resort, from a PC, when the Flip will not boot. |

**Articles:** [Preloader tools](boot-and-flash/preloader-tools.md) · [SD multiboot](boot-and-flash/sd-multiboot-apommel.md) · [Erase the preloader](boot-and-flash/stock-rocknix-without-disassembly.md). Images: [Zlyme](#zlyme) (maintained). Historical ROCKNIX images from [Zetarancio/distribution](https://github.com/Zetarancio/distribution) branch **`flip`** are an [archived fork](#archived-rocknix-fork), not the current install path.

Multiboot puts U-Boot **on the card**, so each SD distro must ship one built for this board. **Stock** stays bootable from NAND with no card while the normal repaired preloader is installed. ROCKNIX, **SpruceOS**, and apommel's MinUI base were tested on that path. **Zlyme** was observed the same way on 2026-10-07. Cards made for **GammaLoader** (Knulli, GammaOS) do not boot under the repaired preloader — [why](boot-and-flash/sd-multiboot-apommel.md#distro-compatibility).

**Not a brick:** you can recover with **USB MASKROM** (and, if needed, **disassemble** and use the hardware MASKROM button) plus **`xrock`** — [Flashing](boot-and-flash/flashing.md).

Four different things get called MASKROM, and erasing the preloader is a fifth operation that is easy to mix up with them. They are not interchangeable:

1. The physical MASKROM button, which forces the boot ROM. [Flashing](boot-and-flash/flashing.md).
2. Stock U-Boot `rbrom`, which sets the BootROM download flag and resets. It does not erase the preloader.
3. Historical Zlyme experiments that tried to do that from Linux, or with a boot-file marker. Those failed and are not a product path.
4. The [recovery preloader](boot-and-flash/recovery-preloader.md): a deterministic change of the vendor SPL boot order to the right-hand slot only. A bootable card there still boots. No bootable card there resets to the BootROM.
5. Erasing the preloader. That removes the SPI preloader. It is not USB MASKROM while another loader can still boot. [Erase the preloader](boot-and-flash/stock-rocknix-without-disassembly.md).

---

## Hardware overview

| Component | Detail |
|-----------|--------|
| SoC | Rockchip RK3566 (quad Cortex-A55 @ 1.8 GHz) |
| GPU | Mali-G52 2EE (Bifrost), 200–800 MHz |
| RAM | LPDDR4 |
| Storage | SPI NAND 128 MB (**ESMT**, via SFC) — 128 KiB blocks, 2 KiB pages, 64 B OOB. Stock and mainline both log `esmt SPI NAND was found`; earlier wiki text said Winbond, which the boot logs do not support. |
| SD slots | Right (near power): **MMC1** @ `fe2b0000`. Left (near volume): **MMC2** @ `fe2c0000`. |
| Display | **LMY35120-20p** (**2503x** on flex). Sure: 640×480, 2-lane DSI, RGB888 video mode (stock DTS). Presumed: FT8006M — [Display](drivers-and-dts/display.md#module-name-vs-what-is-proven) |
| Backlight | PWM4 |
| WiFi/BT | RTL8733BU (USB combo) |
| Audio | RK817 codec, I2S, speaker amplifier |
| PMIC | RK817 (main) |
| Battery | Miyoo **755060**, **3.7 V** nominal, **3000 mAh**, **11.1 Wh** (typical pack marking) |
| VDD_CPU (I2C0) | **RK8600 @ 0x40** only. **TCS4525 @ 0x1c** was removed from the DTS after **Miyoo officially confirmed** there is **no second CPU-regulator variant**. The 2025 stock DTS still lists both addresses, but that is BSP legacy rather than evidence of two SKUs. See [Board DTS / PMIC / DDR — I2C0 CPU regulator](drivers-and-dts/board-dts-pmic-ddr-updates.md#i2c0-cpu-regulator). |
| USB | Two USB-C: **upper** (top) = USB 2.0 host (`usb_host0_ehci` + `usb_host0_ohci` with PHY **480 MHz** clock, `usb2phy1_otg`, VBUS `vcc5v0_host`); **lower** (bottom) = charge + gadget (`usb_host0_xhci`, `dr_mode = "otg"`, no VBUS). See [Board DTS — USB](drivers-and-dts/board-dts-pmic-ddr-updates.md#usb). |
| UART | ttyS2 (fe660000), 1,500,000 baud, 3.3V |

Pinout and board photos: [steward-fu pin mapping](https://steward-fu.github.io/website/handheld/miyoo_flip_pin.htm), [specs](https://steward-fu.github.io/website/handheld/miyoo_flip_spec.htm). Serial: [serial.md](serial.md).

---

## Where to get images

### Zlyme

The maintained OS is [Zlyme](https://github.com/Zetarancio/zlyme). Zlyme stable releases publish **`zlyme.img`**, a raw image for the OS card. [zlyme44](https://github.com/Zetarancio/zlyme/releases/tag/zlyme-37164297221) (2026-10-04) is the first stable release; earlier Zlyme GitHub releases are prereleases.

1. **Let the Flip boot from SD first.** A current Zlyme card image carries `miyoo355_fw.img` at the root of its boot FAT. That file is [apommel](https://github.com/apommel/baseos-my355)'s installer, not a replacement preloader. Boot **stock** with the card inserted. Stock runs the installer, which reads this unit's own preloader, saves `mtd5-original-<sha256>.img`, patches the SPL `/pinctrl` node, and checks the write. Writing the card image does not itself modify NAND. The published zlyme44 image does not contain that file. Standalone helpers, including a multiboot image you rename to `miyoo355_fw.img`, are [preloader tools](boot-and-flash/preloader-tools.md). Until a release publishes them, use the [Zlyme releases page](https://github.com/Zetarancio/zlyme/releases) rather than a direct file link. The manual repair remains [SD multiboot](boot-and-flash/sd-multiboot-apommel.md). Erasing the preloader is a different operation: [erase the preloader](boot-and-flash/stock-rocknix-without-disassembly.md).
2. **Write the card.** The recommended, convenient way is the [Zlyme Installer](https://github.com/Zetarancio/zlymeOS-Installer); download it from its [Releases page](https://github.com/Zetarancio/zlymeOS-Installer/releases). Its first normal release is [V1.8.0](https://github.com/Zetarancio/zlymeOS-Installer/releases/tag/V1.8.0) (2026-10-04), with Windows, macOS and Linux builds. It fetches the latest Zlyme release, selects `zlyme.img`, and writes it as a raw image, erasing the whole card. It is forked from the [SpruceOS Installer](https://github.com/spruceUI/spruceOS-Installer); [SundownerSport](https://github.com/Sundownersport) kindly made the original Zlyme adaptation.
3. **Or write it by hand.** Download `zlyme.img` from the [release](https://github.com/Zetarancio/zlyme/releases/tag/zlyme-37164297221) and write it with [Balena Etcher](https://etcher.balena.io/) or another raw-image writer. This also erases the whole card.
4. **Boot** with the card in the right-hand slot, next to power.

Later OS updates happen inside Zlyme (**Settings → Update**); the card does not need to be rewritten. Full steps: [Zlyme’s install guide](https://github.com/Zetarancio/zlyme#install).

### Archived ROCKNIX fork

The names below are the **archived** Miyoo Flip ROCKNIX fork, [Zetarancio/distribution](https://github.com/Zetarancio/distribution) branch **`flip`**. Those GitHub Actions artifacts are historical. They are not a maintained download channel. A GitHub login is required to download whatever still remains: [Actions filtered to `flip`](https://github.com/Zetarancio/distribution/actions?query=branch%3Aflip).

There is **no** artifact named after the handheld. Each successful RK3566 job uploaded two zips named by **SoC and date** (the date is the build day). [Build 245](https://github.com/Zetarancio/distribution/actions/runs/33621892655) (2026-09-02) is a typical layout; other builds of that fork only change the date suffix:

| Artifact on the Actions page | What is inside after unzipping | Use for |
|------------------------------|--------------------------------|---------|
| **`ROCKNIX-image-RK3566-YYYYMMDD`** | **both** the Generic and Specific SD images (`.img.gz` + `.sha256`) | writing a microSD for first boot |
| **`ROCKNIX-update-RK3566-YYYYMMDD`** | the OTA tarball (`.tar` + `.sha256`) | upgrading a device that already ran that fork’s ROCKNIX |

For that 245 example the names are `ROCKNIX-image-RK3566-20260902` and `ROCKNIX-update-RK3566-20260902`.

Unzip the **image** zip. The files look like:

| File inside `ROCKNIX-image-RK3566-YYYYMMDD` | Handhelds | Miyoo Flip? |
|---------------------------------------------|-----------|-------------|
| `ROCKNIX-RK3566.aarch64-YYYYMMDD-Generic.img.gz` | Anbernic RG353 family and similar | **no** |
| `ROCKNIX-RK3566.aarch64-YYYYMMDD-Specific.img.gz` | Powkiddy X55 / X35s, Anbernic RG DS, **Miyoo Flip** | **yes — this one** |

Decompress the **Specific** `.img.gz` (it is gzip, not a ready disk image). Flash the resulting **`.img`** to the card — never the `.gz`, and never the update `.tar`. General ROCKNIX install steps: [rocknix.org/play/install](https://rocknix.org/play/install/).

The Specific image is shared with those other boards, so its default device tree is **not** the Flip (it ships as the X55 DTB). After writing the card, set `FDT /device_trees/rk3566-miyoo-flip.dtb` in `ROCKNIX/extlinux/extlinux.conf` before the first boot — steps: [ROCKNIX on the SD card](boot-and-flash/stock-rocknix-without-disassembly.md#rocknix-on-the-sd-card-extlinuxconf-and-the-device-tree).

---

## Boot chain

| Region | SPI Offset | Content |
|--------|------------|---------|
| Preloader | 0x000000–0x200000 | IDBLOCK + DDR init blob + stock SPL |
| U-Boot FIT | 0x300000+ | FIT image: ATF (BL31) + **OP-TEE (BL32)** + U-Boot + FDT |

**Proven configuration:** the stock SPI FIT contains TF-A **BL31**, **OP-TEE as BL32**, U-Boot, and an FDT. Known working SD and mainline boots documented here also included TF-A and OP-TEE, except Zlyme: its card FIT carries BL31 v1.44 and U-Boot with **no OP-TEE**, and it boots and resumes from deep suspend that way (observed in Zlyme, zlyme44 `337ccbce` and the deep-suspend acceptance on `b709719a`; no serial capture is kept in this wiki — [Zlyme](implementations/zlyme.md)). In the OP-TEE configuration BL31 hands off to the BL32 secure payload. This repository does not contain a controlled test showing that omitting OP-TEE necessarily fails, so this is not a universal hardware requirement.

Boot flow: **Bootrom** reads IDBLOCK on SPI NAND, loads DDR init + SPL. **SPL** tries boot sources (MMC2 → MMC1 → MTD) and loads U-Boot. **U-Boot** reads the boot partition (Android boot image: kernel + DTB). **Kernel** mounts rootfs from `/dev/mtdblock3`.

For deep analysis (FIT segment addresses, BL31 DDR strings, DDR scaling), see [SPI image analysis](stock-firmware-and-findings/spi-and-boot-chain.md).

---

## Flashing

The 128 MB SPI NAND is flashed via **xrock** over USB in MASKROM mode. The full guide covers the MTD partition table, xrock setup, entering MASKROM, loading the DDR init, backup/restore commands, flashing U-Boot/boot/rootfs, boot.img format, erasing the preloader, and the mtdparts string.

**[Full flashing guide →](boot-and-flash/flashing.md)**

---

## Booting from SD

Three routes, in order of how much they cost you:

| Route | Keeps stock? | Needs a PC? |
|-------|--------------|-------------|
| [**SD multiboot**](boot-and-flash/sd-multiboot-apommel.md) — repair the preloader | **yes** | no |
| [**Preloader Eraser**](boot-and-flash/stock-rocknix-without-disassembly.md) — erase it from software | no | no |
| [**xrock from MASKROM**](boot-and-flash/flashing.md#booting-from-sd) — zero it from a host | no | yes |

All three end with the bootrom or SPL loading U-Boot from the card instead of internal NAND when that card has a loader the ROM or SPL can use. The difference with no card inserted: multiboot still boots stock. The erase routes have no SPI preloader left, so USB MASKROM is what remains when no other loader is present. A card that still contains an idbloader can boot that loader instead.

---

## steward-fu assets

- [steward-fu website — Miyoo Flip](https://steward-fu.github.io/website/handheld/miyoo_flip_uart.htm)
- [steward-fu release (miyoo-flip)](https://github.com/steward-fu/website/releases/tag/miyoo-flip)

---

## Legacy note

This `main` branch is wiki-focused. Legacy local build scripts are kept in branch **`buildroot`**.
