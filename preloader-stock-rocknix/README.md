# Miyoo Flip — preloader tools (multiboot, MASKROM, restore)

| Folder | Role |
|--------|------|
| **`App/apommel-multiboot/`** | **Repairs** the SPI preloader so the SPL can read a card: no card → **stock**, bootable card → **SD**. Install/restore/backup modes. Runs on stock and ROCKNIX, but can only **write** from ROCKNIX. Method by **[apommel](https://github.com/apommel/baseos-my355)**. |
| **`App/PreloaderEraser/`** | **Erases** the SPI preloader so the device powers on into **MASKROM** when no card is inserted (a bootable card still boots from SD). Removes internal stock boot. |

Restoring a stock preloader is part of the multiboot app — **`restore-preloader.sh`**, or `sh launch.sh restore [FILE]` — so there is no separate restore tool. The app bundles a verified stock image, and it validates, backs up, verifies the readback and rolls back on failure.

**For dual boot use `apommel-multiboot`, not the eraser.** The eraser is for reaching MASKROM from software, and for getting a stock-only unit onto ROCKNIX so the multiboot app can be written there.

**Documentation:** [SD multiboot via a repaired preloader](../docs/boot-and-flash/sd-multiboot-apommel.md) · [MASKROM and SD boot by erasing the preloader](../docs/boot-and-flash/stock-rocknix-without-disassembly.md)

**See also:** [Boot and flash](../docs/boot-and-flash.md) · [Flashing](../docs/boot-and-flash/flashing.md) · [Stock OTA mechanism](../docs/stock-firmware-and-findings/ota-update-mechanism.md)

**ROCKNIX images:** [Zetarancio/distribution](https://github.com/Zetarancio/distribution) branch **`flip`** (GitHub Actions artifacts).
