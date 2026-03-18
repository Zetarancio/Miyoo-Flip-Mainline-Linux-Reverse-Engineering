# Steward-fu: obtain and flash

This page is the wiki entry for obtaining/testing images and flashing the Miyoo Flip.

## 1) Use current image source

Use **[Zetarancio/distribution](https://github.com/Zetarancio/distribution)** (branch `flip`) for current code/images.

- GitHub Actions creates **generic** and **device-specific** images.
- For Miyoo Flip testing, use the **device-specific** image.

## 2) Flash with xrock

Use xrock in MASKROM mode, then flash boot/rootfs (and U-Boot only when needed).

- Partition layout, backup/restore, and SD-boot procedure: [Flashing](flashing.md)
- Quick SD boot procedure: [Boot from SD](boot-from-sd.md)

## 3) steward-fu assets

Useful references and files:

- [steward-fu website — Miyoo Flip](https://steward-fu.github.io/website/handheld/miyoo_flip_uart.htm)
- [steward-fu release (miyoo-flip)](https://github.com/steward-fu/website/releases/tag/miyoo-flip)

## Legacy note

This `main` branch is wiki-focused. Legacy local build scripts are kept in branch **`buildroot`**.
