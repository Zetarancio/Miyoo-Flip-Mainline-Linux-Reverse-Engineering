# Documentation model

This repository is a hardware, firmware, and reverse-engineering wiki for the original Miyoo Flip (`my355`, Rockchip RK3566). A developer building a different operating system should still be able to use it.

Contributor and agent policy lives in [`AGENTS.md`](../AGENTS.md). This page is the short version for people.

## What belongs where

| Kind of statement | Where it lives |
|-------------------|----------------|
| What the board, SoC, or electrical path actually is | Hardware pages (`docs/rk3566-reference/`, board/USB/input/display pages) |
| How firmware or a protocol behaves (BL31 SIP, preloader, UART, OTA) | Firmware and protocol pages |
| What **Zlyme** currently ships | [`implementations/zlyme.md`](implementations/zlyme.md), plus Zlyme’s own repository |
| What the maintainer’s ROCKNIX fork shipped | [`implementations/rocknix.md`](implementations/rocknix.md) — historical |
| Vendor behavior | Stock pages and the `miyoo355_fw_20250527/` / `spi_20241119160817/` trees |
| A failed hypothesis that later evidence corrected | The original investigation, with a current-conclusion note — do not delete the trail |

```text
Miyoo Flip wiki          hardware, firmware, protocol
Zlyme                    active implementation (Zetarancio/zlyme)
Zetarancio/distribution  archived Miyoo Flip ROCKNIX fork
ROCKNIX/distribution     external upstream, not this project’s state
stock firmware           vendor implementation and evidence
```

Archiving the ROCKNIX fork does not erase what that tree measured. A commit that fixed the upper-port OHCI clock, proved DMC resume, or isolated `SYS_CAN_SD` stays a valid provenance link. It is no longer “what the maintained OS does today.”

## How to label a claim

Say which of these you mean: **confirmed**, **observed on hardware**, **observed in stock firmware**, **observed in Zlyme**, **observed in the archived ROCKNIX implementation**, **observed in another distribution**, **inferred**, **presumed**, **untested**, **historical**, **superseded**.

Name the subject of “current.” “Current Zlyme” and “stock firmware 20250527” are usable. “The current configuration” is not, once more than one OS exists in the record.

When an implementation snapshot matters, include the repository, branch or tag, commit, and date.

## Where a new fact goes

Ask whether the sentence would still be true if the Flip ran a different operating system.

- If yes, put it on the hardware or firmware page, with the measurement, log, stock artifact, or commit that supports it.
- If it is only how Zlyme packages, starts, or policies a feature, put it in Zlyme’s own docs and, when a wiki reader needs the one-line status, in [`implementations/zlyme.md`](implementations/zlyme.md).
- If it is how the archived ROCKNIX fork used to do something, leave it on [`implementations/rocknix.md`](implementations/rocknix.md) or as a labeled historical note. Do not refresh that fork to match upstream ROCKNIX.
- Update this wiki for an upstream ROCKNIX or KNULLI change only when it adds hardware evidence or a useful comparison. Do not mirror those projects.

InputPlumber, Weston, EmulationStation, and PipeWire are operating-system choices. UART pins, GPIO maps, PHY clocks, and PMIC bits are not.

Deep-suspend enablement in Zlyme is implementation status. A new BL31 flag, wake source, or measured current is a hardware or firmware fact and belongs on the generic page as well.

## Evidence

Raw logs, stock unpacks, and BL31 disassemblies are evidence. Do not edit them to match a later conclusion. Add a new capture and explain the relationship in prose.

Patch numbers (1012, 0007, 1013) are historical names inside the archived ROCKNIX tree. The durable name is the mechanism: RK3566/RK3568 V2-SIP DMC devfreq, RK817 `SYS_CAN_SD`, rk3568-suspend / `ARMOFF_LOGOFF`. A later OS does not have to keep those filenames.
