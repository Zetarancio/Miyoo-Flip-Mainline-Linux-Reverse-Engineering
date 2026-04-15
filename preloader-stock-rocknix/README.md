# Miyoo Flip — preloader tools (stock ↔ ROCKNIX, no disassembly)

| Folder | Role |
|--------|------|
| **`App/PreloaderEraser/`** | Stock OS app: erases the SPI preloader so the device boots **ROCKNIX from SD**. |
| **`preloader-restore/`** | On **ROCKNIX**: shell script + bundled **`preloader.img`** to write the preloader back → **stock from internal SPI**. |

**Documentation:** [Try ROCKNIX without opening the device](../docs/boot-and-flash/stock-rocknix-without-disassembly.md)

**See also:** [Boot and flash](../docs/boot-and-flash.md) · [Flashing](../docs/boot-and-flash/flashing.md) · [Boot from SD](../docs/boot-and-flash/boot-from-sd.md)

**ROCKNIX images:** [Zetarancio/distribution](https://github.com/Zetarancio/distribution) branch **`flip`** (GitHub Actions artifacts).
