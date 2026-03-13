# Steward-fu Project: Obtain and Flash

This is the **only** page that describes how to get and flash software for the **Steward-fu** Miyoo Flip project. For serial, generic flashing, boot-from-SD, and device reference, see the [device wiki](README.md).

---

## 1. Obtaining the software

### Recommended: pre-built images and current code

For a working mainline image and up-to-date kernel, DTS, and drivers:

- **[Zetarancio/distribution](https://github.com/Zetarancio/distribution)** (branch `flip`) — ROCKNIX-based build system and images for the Miyoo Flip.
- [ROCKNIX](https://rocknix.org/) — distribution; the Flip port is maintained in the repo above.

Use their documentation for downloading images, building, and recommended flash procedure. Boot logs in this repo root (`boot_log_ROCKNIX.txt`, etc.) are reference only.

### steward-fu assets and references

- **Releases and assets:** [steward-fu website — Miyoo Flip](https://steward-fu.github.io/website/handheld/miyoo_flip_uart.htm), [GitHub release (miyoo-flip)](https://github.com/steward-fu/website/releases/tag/miyoo-flip).
- **xrock build guide:** [steward-fu — build xrock](https://steward-fu.github.io/website/handheld/miyoo_flip_build_xrock.htm).
- **MASKROM procedure:** [steward-fu — MASKROM](https://steward-fu.github.io/website/handheld/miyoo_flip_maskrom.htm).

If you build from this repo (see §3), run `./setup-extra.sh` to download steward-fu assets (SDK toolchain, U-Boot sources, firmware, optional full SPI dump).

---

## 2. Flashing the software

### Prerequisites

- **xrock** — for reading/writing SPI NAND over USB in MASKROM mode. Build from [xboot/xrock](https://github.com/xboot/xrock) or use steward-fu’s build guide above.
- **MASKROM mode:** Power off, hold MASKROM button (see steward-fu’s MASKROM page), insert USB. Confirm with `lsusb` (Rockchip device).

### Generic procedure

1. Enter MASKROM and load the loader (DDR + USB flash handler). Either:
   - **Combined loader** (from U-Boot build):  
     `xrock download <path-to-rk356x_spl_loader_*.bin>` then `sleep 1` and `xrock flash`.
   - **DDR + usbplug** (from rkbin):  
     `xrock extra maskrom --rc4 off --sram rk3566_ddr_1056MHz_*.bin --delay 10 --rc4 off --dram rk356x_usbplug_*.bin --delay 10`, then `sleep 1` and `xrock flash`.
2. Flash **boot** and **rootfs** (and U-Boot only if you need to change it):
   - Boot partition: sector 14336, size 77824 sectors (38 MB).  
     Example: `xrock flash write 14336 <your-boot.img>`.
   - Rootfs partition: sector 92160, size 131072 sectors (64 MB).  
     Example: `xrock flash write 92160 <your-rootfs.squashfs>`.
   - U-Boot: sector 6144, size 8192 sectors (4 MB).  
     Example: `xrock flash write 6144 <your-uboot.img>`.

Partition layout, backup, restore stock, and boot flow are in [Flashing](flashing.md). To **boot from SD**, see [Boot from SD](boot-from-sd.md).

### If you use this repo’s build (historical)

Outputs go to `output/`. After building (see §3):

```bash
xrock download output/rk356x_spl_loader_v1.23.114.bin
sleep 1 && xrock flash && sleep 1
xrock flash write 14336 output/boot.img
xrock flash write 92160 output/rootfs.squashfs
# U-Boot only when needed:
# xrock flash write 6144 output/uboot.img
```

---

## 3. Building from this repo (historical, outdated)

The build system in this repo is **outdated**. Prefer [Zetarancio/distribution](https://github.com/Zetarancio/distribution) (branch `flip`) for current builds. What follows is kept so you can reproduce or adapt the flow.

### Prerequisites

- Docker; ~2 GB for image; ~1 GB for `Extra/` (from `setup-extra.sh`); ~2 GB for kernel source.

### Setup

```bash
./setup-extra.sh                              # steward-fu assets
make download-kernel                          # mainline Linux + patches
make download-wifi                            # RTL8733BU + compat patch
make download-mali                            # mali_kbase + libmali
```

### Build

```bash
make build
# Or step by step:
# make build-kernel && make build-rootfs && make build-wifi && make build-mali
# make boot-img && make rootfs-img
```

### Outputs (in `output/`)

| File | Description |
|------|-------------|
| `Image` / `Image.lz4` | Kernel |
| `rk3566-miyoo-flip.dtb` | Device tree |
| `boot.img` | Android-format boot image (kernel + DTB) |
| `rootfs.squashfs` | Root filesystem |
| `uboot.img` | U-Boot FIT |
| `rk356x_spl_loader_v1.23.114.bin` | Loader for xrock |
| `modules/`, `firmware/` | Out-of-tree modules and WiFi/BT firmware |

### Useful targets

- `make build` — full build  
- `make build-kernel` / `make build-rootfs` / `make build-wifi` / `make build-mali`  
- `make boot-img` / `make rootfs-img` — pack images  
- `make clean` / `make clean-kernel` / `make clean-rootfs`  
- `make shell` — Docker shell  
- `make help` — list targets  

### DTS

The mainline DTS is at repo root: `rk3566-miyoo-flip.dts`. The kernel build copies it in; after editing, run `make build-kernel && make boot-img` (no full clean needed for DTS-only changes).

### Kernel branch

Default: `linux-6.6.y`. Override:  
`KERNEL_BRANCH=linux-6.12.y make download-kernel` or `KERNEL_BRANCH=latest make download-kernel`.

---

For serial console, partition layout, boot-from-SD, drivers, and troubleshooting, use the [documentation index](README.md).
