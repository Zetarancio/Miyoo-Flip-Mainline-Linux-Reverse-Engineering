# Restore preloader on ROCKNIX

- **`preloader.img`** — first **2 MiB** of SPI (same as in a full NAND dump). **Bundled in this folder** for convenience; you can replace it with your own extract if you ever need a different backup.
- **`write-preloader-mtd.sh`** — run as **root** on ROCKNIX (`flash_eraseall` + `nandwrite` on the `preloader` MTD node). Keep **`preloader.img`** in the **same directory** as the script (or pass a path as the first argument).
- **`extract-preloader-from-spi-dump.sh`** — optional: extract `preloader.img` from **your** full SPI dump on a PC (`dd` equivalent).

Procedure, recovery, and MASKROM behaviour: [stock-rocknix-without-disassembly.md](../../docs/boot-and-flash/stock-rocknix-without-disassembly.md).
