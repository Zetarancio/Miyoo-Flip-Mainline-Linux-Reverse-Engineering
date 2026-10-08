# Zlyme

**Active** Miyoo Flip operating system maintained by this project: [Zetarancio/zlyme](https://github.com/Zetarancio/zlyme).

This wiki does not copy Zlyme’s architecture manual. Implementation detail belongs in that repository. This page is only the hardware-facing status a wiki reader needs.

## Snapshot

Last synchronized against Zlyme zlyme44 (tag `zlyme-37164297221`, runtime `337ccbce2587393463a4b49c551f94e33e318e44`, 2026-10-04); documentation `d2e2496b7fe935d5123d082d1ef28b6ac28ed139` on `phase-10-maintenance`.

| | Runtime | Documentation |
|--|---------|---------------|
| Repository | [Zetarancio/zlyme](https://github.com/Zetarancio/zlyme) | [Zetarancio/zlyme](https://github.com/Zetarancio/zlyme) |
| Branch or tag | tag [`zlyme-37164297221`](https://github.com/Zetarancio/zlyme/releases/tag/zlyme-37164297221), release *zlyme44 (2026-10-04)*; `main` points at the same commit | branch [`phase-10-maintenance`](https://github.com/Zetarancio/zlyme/tree/phase-10-maintenance) |
| Commit | [`337ccbce2587393463a4b49c551f94e33e318e44`](https://github.com/Zetarancio/zlyme/commit/337ccbce2587393463a4b49c551f94e33e318e44) | [`d2e2496b7fe935d5123d082d1ef28b6ac28ed139`](https://github.com/Zetarancio/zlyme/commit/d2e2496b7fe935d5123d082d1ef28b6ac28ed139) |
| Date | 2026-10-04 | 2026-10-04 |

The runtime commit is what the lines below describe. The maintainer hardware-accepted the zlyme44 image built from it, and GitHub Actions Build run [`37164297221`](https://github.com/Zetarancio/zlyme/actions/runs/37164297221) built it from a clean tree and published the release. The documentation commit only supplied wording for this sync. It is **not** a hardware-tested runtime. zlyme44 is Zlyme’s first stable release; earlier Zlyme GitHub releases are prereleases.

Where a mechanism was hardware-accepted on an earlier Zlyme runtime, that runtime is named. Each of those commits is an ancestor of `337ccbce`.

## Implementation status at zlyme44 (`337ccbce`)

Observed in Zlyme unless a line says otherwise. Patch numbers are Zlyme’s filenames, not the archived fork’s; the same number can mean a different patch in each tree.

| Area | Zlyme zlyme44 (`337ccbce`) |
|------|-----------------------------|
| **Kernel and boot chain** | Linux **7.0.2**. Mainline U-Boot **2026.01**. rkbin BL31 `rk3568_bl31_v1.44.elf` and TPL `rk3566_ddr_1056MHz_v1.23.bin`. The card FIT carries BL31 and U-Boot, **no OP-TEE** (no BL32). |
| **Gamepad driver** | `miyoo-flip-gamepad`, Zlyme’s own out-of-tree driver: one input device for the UART1 sticks (through `serdev`), the 17 GPIO buttons, a calibration and deadzone transform, and `FF_RUMBLE` on PWM5. Calibration files are restored by userspace through sysfs after the first frame. Accepted on runtime `4d1c1d44d2a24eb8ca3f91d038cd0311ed60a4ba`. |
| **Application controllers** | InputPlumber **v0.81.0** presents application-facing controllers as virtual Xbox 360 (`xb360`) pads. That is OS input policy, not a hardware requirement. Volume, power, and the lid stay outside InputPlumber. Accepted on runtime `0b139e9099eec699e31d1cb5313998f57f387e12`. |
| **Deep suspend** | Enabled. DTS node `rockchip-suspend`, `compatible = "rockchip,pm-rk3568"` (the stock/BSP shape), sleep mode `0x5ec` including `ARMOFF_LOGOFF`, wakeup `0x10`, BL31 v1.44. A built-in `rockchip-pm-config` driver from Zlyme kernel patches `1011a`/`1011b` sends mode and wake at probe, and `LINUX_PM_STATE` (`0x09`), mode, and wake again before each suspend. `vdd_logic` (RK817 `DCDC_REG1`) is `regulator-off-in-suspend`. Linux mem sleep is `s2idle [deep]`. |
| **Deep-suspend acceptance** | Zlyme Phase 6 hardware acceptance ran on runtime [`b709719aac5c5540394d0369e5e06981b8aa00bc`](https://github.com/Zetarancio/zlyme/commit/b709719aac5c5540394d0369e5e06981b8aa00bc). BL31 returned 0 for the `LINUX_PM_STATE`, mode, and wake calls. Repeated power-button suspend/resume cycles passed (the exact count was not recorded), on the frontend and in game. Display, audio, the built-in pad, the virtual pad, storage, Wi-Fi, DMC devfreq, and `mali_kbase` recovered. No filesystem corruption, Oops, panic, or hung task attributable to deep suspend was seen. An `xHC error in resume, USBSTS 0x401, Reinit` line recovered with the USB radio. |
| **DDR scaling (DMC)** | External module `rk3568_dmc.ko` (Zlyme package `rk3568-dmc`), not a kernel patch. It speaks the Rockchip V2 SIP shared-memory protocol, uses OPPs 324/528/780/1056 MHz all at 900 mV, and loads from the `rockchip,rk3568-dmc` modalias during the deferred udev coldplug. Load comes from the in-tree DFI driver, with Zlyme patch `1010` adding its suspend/resume. Hardware-accepted on runtime `21de8081d6e6a419d708e8f3c792e4f1357eaafc`, including one physical deep suspend that came back at 324 MHz. |
| **Weston** | Application-scoped, never a permanent compositor. Native Wayland clients (Wine today) use Zlyme’s own per-launch Weston, built without Xwayland. PortMaster X11 ports use PortMaster’s WestonPack, which brings Xwayland for that launch. |
| **RTL8733BU Wi-Fi** | `8733bu` is a third-party driver, [Charliechen114514/rtl8733bu-linux-driver](https://github.com/Charliechen114514/rtl8733bu-linux-driver) pinned at [`c46aa25e237cb43f33390cf58eee5c69d9b32883`](https://github.com/Charliechen114514/rtl8733bu-linux-driver/commit/c46aa25e237cb43f33390cf58eee5c69d9b32883) (the same commit the wiki cites under another owner name), with Zlyme’s integration patches. IPS and radio power save are kept off so the Bluetooth half keeps its firmware. |
| **RTL8733BU power** | `rtl8733bu-power` is Zlyme’s own module, separate from the third-party Wi-Fi driver. It owns the chip enable GPIO (GPIO0_PA0, active low), registers WLAN and Bluetooth rfkill, and cuts power when both are blocked and in its late suspend phase. Nothing loads the combo chip at boot; Zlyme loads it on demand and stops Bluetooth, then Wi-Fi, before mem suspend. |
| **RTL8733BU Bluetooth** | In-tree `btusb` + `btrtl`, bound after `8733bu`. Zlyme kernel patch `0005-Bluetooth-btrtl-Add-the-support-for-RTL8733BU.patch` adds RTL8733BU to `btrtl`. |
| **Off-state drain** | Zlyme kernel patch `0007-power-supply-rk817-clear-sys-can-sd-fix-drain.patch` clears RK817 `SYS_CAN_SD` in `rk817_battery_init()`, the mechanism in [Power-off investigation](../miyoo-flip-power-off-investigation.md). During Zlyme Phase 5 (2026-09-28) the bit read clear after at least 6 h powered off and unplugged. That was a register readback, not an ammeter measurement. |
| **GPU** | Two stacks, chosen per boot: vendor `mali_kbase` + libmali `bifrost-g52 g29p1` (default, GLES and Vulkan) or Mesa Panfrost (GLES only). |

## Not claimed for Zlyme

This wiki does **not** record any of these for Zlyme:

- a measured standby (suspend) current, or an ammeter reading of off-state current;
- the archived fork’s informal 100–120 h standby estimate;
- long or scripted suspend cycle counts;
- a USB-host attach/detach matrix or a full Wi-Fi/Bluetooth on/off matrix across suspend;
- a separate lid-close deep-suspend test;
- Switch replacement sticks or specific external controller models;
- a non-zero BL31 sleep-debug setting;
- hardware validation of the later DMC source correction [`70acb1d27443447df84903e2043a2af05dbd9ee3`](https://github.com/Zetarancio/zlyme/commit/70acb1d27443447df84903e2043a2af05dbd9ee3) on its own (source review and rebuild only).

## Install

Zlyme stable releases publish `zlyme.img`; zlyme44 is the first. The recommended way to write it is the [Zlyme Installer](https://github.com/Zetarancio/zlymeOS-Installer) (forked from the SpruceOS Installer; first normal release [V1.8.0](https://github.com/Zetarancio/zlymeOS-Installer/releases/tag/V1.8.0), 2026-10-04), with Balena Etcher or another raw-image writer as the manual alternative.

A development card image can include `miyoo355_fw.img` on the boot FAT. Stock runs that file. It is apommel's installer: it patches this unit's own preloader and keeps a `mtd5-original-<sha256>.img` backup. On 2026-10-07 a fresh card written from a development `zlyme.img` was booted from stock. Stock ran that installer, the installer rebooted, and Zlyme booted. That accepts the stock-assisted fresh-install path only. The same day's direct Linux MASKROM restart on that installation logged the restart command and then went silent, with no USB `2207:350a`, and needed a physical reset. That mechanism was removed. The later boot-file request for U-Boot `rbrom` was also removed. It is not a product path. The measured replacement is the [recovery preloader](../boot-and-flash/recovery-preloader.md): the vendor SPL boot order becomes the right-hand slot only. A bootable card there boots the OS. No bootable card there resets to the BootROM, and the 2026-10-08 capture enumerated `2207:350a`. The published zlyme44 image does not contain `miyoo355_fw.img`, and this page does not call an unpublished `zlyme44.2` GitHub release hardware-accepted. The recovery-preloader measurement is a hardware record, not that release. Standalone helpers (`miyoo355_fw-multiboot.img`, `miyoo355_fw-maskrom.img`, `miyoo355_fw-restore.img`) are described in [preloader tools](../boot-and-flash/preloader-tools.md). Stock only runs the literal name `miyoo355_fw.img`. Until a release publishes the files, use the [Zlyme releases page](https://github.com/Zetarancio/zlyme/releases) rather than a direct file link. On 2026-10-08 one Flip accepted the restore helper, the MASKROM helper from the repaired preloader, the MASKROM helper from the original stock preloader, a right-slot Zlyme boot of the resulting recovery image, and Zlyme's disarm back to the repaired preloader. The hashes and raw logs are on [preloader tools](../boot-and-flash/preloader-tools.md) and [recovery preloader](../boot-and-flash/recovery-preloader.md). That acceptance is that unit. It does not cover every vendor SPL revision. The restore helper runs only while stock still boots, so it is not how an armed recovery preloader is left. The technical repair page remains [SD multiboot](../boot-and-flash/sd-multiboot-apommel.md). Later updates happen inside Zlyme (Settings → Update) and do not rewrite the preloader. Steps: [Where to get images — Zlyme](../boot-and-flash.md#zlyme) and [Zlyme’s install guide](https://github.com/Zetarancio/zlyme#install).

## Zlyme documentation

- [README](https://github.com/Zetarancio/zlyme/blob/main/README.md)
- [Architecture](https://github.com/Zetarancio/zlyme/blob/main/docs/ARCHITECTURE.md)
- Changelog: [`CHANGELOG.md`](https://github.com/Zetarancio/zlyme/blob/main/CHANGELOG.md) on `main`

## Community

Zlyme's discussion space is kindly hosted inside the SpruceOS Discord server: https://discord.gg/KjR5uMQQt9

## Where hardware facts go

Hardware facts discovered while doing Zlyme work belong on the generic pages ([Input](../hardware/input.md), [Suspend](../drivers-and-dts/suspend-and-vdd-logic.md), [USB](../drivers-and-dts/board-dts-pmic-ddr-updates.md#usb)), not only here.
