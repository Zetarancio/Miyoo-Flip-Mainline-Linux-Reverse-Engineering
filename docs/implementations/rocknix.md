# Archived Miyoo Flip ROCKNIX fork

**This page is historical.**

The maintainer’s Miyoo Flip ROCKNIX fork, [Zetarancio/distribution](https://github.com/Zetarancio/distribution), is **archived**. Active Miyoo Flip OS work is [Zlyme](zlyme.md). This page keeps the implementation record and the commits that established hardware facts. It is not the current maintained OS, and it is not kept in sync with upstream.

Official upstream [ROCKNIX/distribution](https://github.com/ROCKNIX/distribution) is a **separate** project. Use it as an external reference for generic RK3566, kernel, or packaging questions. Do not read an upstream ROCKNIX decision as the state of this fork or of Zlyme.

Last wiki stamp of branch **`flip`**: [`d249b09bd9`](https://github.com/Zetarancio/distribution/commit/d249b09bd9) (*Merge commit '1ebff24f36' into flip*, 2026-09-02). RK3566 kernel on that tree: **Linux 7.0.2** (selected at build time for RK3566; `packages/linux/package.mk` alone does not show that version). Branch **`next`** was the integration branch ahead of `flip` image freezes.

## What that tree shipped

Past tense is deliberate. Zlyme may package the same mechanisms differently.

| Area | Archived `flip` state |
|------|------------------------|
| **DMC** | Out-of-tree RK3566/RK3568 V2-SIP DMC devfreq, carried as kernel **patch 1012**, plus DFI PM **patch 1010**. Scaling and resume were confirmed on that tree. |
| **Deep suspend** | **Deferred.** Patches **1013a/1013b** were `*.testing-disabled`. `CONFIG_RK3568_SUSPEND_MODE` was not set ([ca7bb4a9](https://github.com/Zetarancio/distribution/commit/ca7bb4a903)). `vdd_logic` stayed `regulator-on-in-suspend`. The stated blocker was an upstream EmulationStation fix. Standard suspend was demonstrated. |
| **Off-state drain** | Kernel **patch 0007** cleared RK817 `SYS_CAN_SD`. |
| **Joypad** | `rocknix-singleadc-joypad` with `rocknix,use-miyoo-serial-joypad` on UART1. Driver patches **0002** / **0003** only. Kernel patch **0001** (gpiolib revert) had already been dropped. |
| **RTL8733BU** | Tree [rtl8733bu-linux-driver](https://github.com/Awesome-Embedded-Learning-Studio/rtl8733bu-linux-driver) pin `c46aa25e`, plus local patches **001–006**. **RTL8733BU-POWER** cut the enable GPIO in `.suspend_late` / `.resume`. |
| **PipeWire** | `pulse.idle.timeout = 60` in `99-rk3566-power.conf`. `099-audio_prime` primed the RK817 playback mux. |
| **Other userspace** | `060-btusb_power` bluetooth drop-in; `010-led_control`; Bluetooth agent event loop ([86de663](https://github.com/Zetarancio/distribution/commit/86de6632e5)). Miyoo `sleep.d` 001-btusb pre/post hooks were removed. |
| **Images** | GitHub Actions on `flip` uploaded `ROCKNIX-image-RK3566-YYYYMMDD` (Generic and Specific `.img.gz` inside) and `ROCKNIX-update-RK3566-YYYYMMDD` (OTA tar). The Flip used the decompressed **Specific** `.img`, then `FDT` set to `rk3566-miyoo-flip.dtb`. Those artifacts are not a maintained download channel. Naming notes: [Where to get images](../boot-and-flash.md#where-to-get-images). |

Patch numbers above are names from that tree. The hardware mechanisms are documented without them on [Board DTS](../drivers-and-dts/board-dts-pmic-ddr-updates.md), [Suspend](../drivers-and-dts/suspend-and-vdd-logic.md), and [BSP and DDR](../stock-firmware-and-findings/bsp-and-ddr-findings.md).

## Evidence that remains useful

Commits on the archived fork are still the right citation when they are the measurement that settled a hardware question (upper USB OHCI plus the PHY 480 MHz clock, `SYS_CAN_SD`, UART joypad, shared SD `vqmmc`). Link the commit. Do not describe the branch as current.
