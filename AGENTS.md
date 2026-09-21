# Miyoo Flip Device Wiki — agent instructions

## Purpose of this repository

This repository is the maintained hardware wiki, reverse-engineering record, and reference archive for the original Miyoo Flip / `my355` based on the Rockchip RK3566.

Its primary purpose is to answer:

> What is true about the Miyoo Flip hardware, firmware, boot chain, and Linux support?

It is **not** the documentation repository for one Linux distribution.

The repository should remain useful to someone implementing a completely different operating system for the Miyoo Flip.

## Project status

The maintainer's active operating-system development happens in:

```text
Zetarancio/zlyme
```

Zlyme is the only actively maintained Miyoo Flip distribution implementation by this project.

The maintainer's former ROCKNIX fork:

```text
Zetarancio/distribution
```

is being archived and must be treated as **historical implementation evidence**, not as an active source of current Miyoo Flip implementation state.

The official upstream:

```text
ROCKNIX/distribution
```

may still be useful as an external reference for generic RK3566, kernel, driver, emulator, or packaging work, but it is not authoritative for the current Miyoo Flip implementation.

Stock Miyoo firmware, archived ROCKNIX work, upstream ROCKNIX, Zlyme, SpruceOS, MinUI/baseos-my355, KNULLI, GammaOS and other projects may provide evidence or implementations, but no distribution defines the hardware truth.

## Source-of-truth model

Use this hierarchy conceptually:

```text
Miyoo Flip wiki
    = hardware, firmware, protocol and reverse-engineering truth

Zlyme
    = active OS implementation

Zetarancio/distribution
    = archived historical ROCKNIX implementation/evidence

official ROCKNIX / KNULLI / other projects
    = external comparison and reference sources

stock firmware
    = vendor implementation and evidence
```

Do not blur these roles.

---

# Repository information model

Treat repository content as belonging to one of these categories.

## 1. Hardware facts

Facts about the physical Miyoo Flip or its SoC/peripherals.

Examples:

* RK3566 SoC;
* RK817 PMIC;
* RK8600 CPU regulator;
* RTL8733BU;
* GPIO assignments;
* UART protocol;
* display panel;
* USB topology;
* shared SD `vqmmc`;
* PWM5 rumble;
* boot-ROM behavior;
* PMIC register behavior;
* electrical constraints.

These should be documented independently of any distribution whenever possible.

## 2. Firmware / protocol facts

Facts about firmware interfaces and hardware protocols.

Examples:

* BL31 SIP calls;
* RK3568 V2 DDR SIP protocol;
* shared-memory layout;
* MCU/IRQ DMC completion;
* `ARMOFF_LOGOFF`;
* preloader/IDBLOCK format;
* U-Boot FIT expectations;
* stock OTA layout.

These may originate from stock firmware, BSP code, disassembly, experiments or another distribution, but should be described independently of that implementation once established.

## 3. Implementation status

How a particular operating system implements a feature.

Examples:

* Zlyme packages a driver as an external module;
* stock uses a vendor userspace input daemon;
* the archived ROCKNIX port carried a feature as a kernel patch;
* Zlyme uses InputPlumber;
* Zlyme enables or disables deep suspend.

Implementation status must always name the implementation.

Never write:

> Deep suspend is disabled.

when the actual meaning is:

> The archived ROCKNIX Miyoo Flip implementation shipped deep suspend disabled.

or:

> Zlyme currently ships deep suspend disabled.

## 4. Evidence

Primary or near-primary evidence preserved for verification.

Examples:

* stock firmware dumps;
* decompiled DTS files;
* kernel configs;
* `System.map`;
* BL31 disassembly;
* boot logs;
* PMIC dumps;
* pinctrl/debugfs captures;
* test measurements;
* stock scripts.

Evidence artifacts should normally remain unchanged.

## 5. Investigations

Chronological engineering investigations that preserve hypotheses, experiments, failures and eventual conclusions.

Example:

```text
docs/miyoo-flip-power-off-investigation.md
```

An investigation is not expected to read like current architecture documentation.

When an old hypothesis becomes false, preserve the historical sequence and add or maintain a clear correction/current-conclusion section rather than rewriting history as if the incorrect hypothesis never existed.

## 6. Operational tools

Scripts that interact with real hardware.

Examples:

* preloader multiboot installer;
* PreloaderEraser;
* power-dump helper;
* serial helpers.

These are executable artifacts, not merely wiki prose.

Changes to them require a higher standard of review because some operations can erase or rewrite SPI NAND.

---

# Documentation principles

## Hardware first, implementation second

A subsystem page should normally be ordered:

1. what the hardware is;
2. how the mechanism works;
3. evidence supporting the conclusion;
4. mainline/BSP implications;
5. implementation status;
6. known limitations or open questions.

Avoid leading a hardware page with the state of a particular distribution unless the page is explicitly about that implementation.

## The active implementation is Zlyme

When documenting current project implementation status, Zlyme is the active implementation.

Do not update the archived `Zetarancio/distribution` fork merely to keep documentation examples current.

Do not describe the archived fork as:

* current;
* maintained;
* canonical;
* the latest Miyoo Flip implementation.

It remains valuable for historical commits, known-working code, driver experiments and evidence.

## Historical ROCKNIX evidence remains valuable

Do not delete or rewrite historical ROCKNIX references merely because development moved to Zlyme.

Statements such as:

> The issue was first proven in the ROCKNIX Flip port.

or:

> The archived ROCKNIX implementation carried this as patch 1012.

are useful provenance.

The correct change is attribution, not erasure.

## Upstream ROCKNIX is a reference, not project state

Official `ROCKNIX/distribution` may be consulted for:

* generic RK3566 work;
* mainline kernel integration;
* emulator packaging;
* driver changes;
* comparable handheld implementations.

Never assume a current upstream ROCKNIX decision describes Zlyme or the Miyoo Flip.

## Never confuse observation with conclusion

Use precise language.

Prefer:

> On the tested unit, GPIO0_PC6 reports the hall sensor.

over:

> All units definitely use GPIO0_PC6.

unless the broader claim is supported.

Prefer:

> The 2025 stock DTS contains both regulator nodes, but later evidence establishes RK8600 as the populated retail regulator.

over inferring two hardware revisions from DTS contents alone.

## State the evidence level

When uncertainty matters, distinguish among:

* **Confirmed hardware fact**
* **Verified from source**
* **Observed on hardware**
* **Observed in stock firmware**
* **Observed in Zlyme**
* **Observed in the archived ROCKNIX implementation**
* **Observed in another distribution**
* **Inferred**
* **Presumed**
* **Untested**
* **Historical**
* **Superseded**

Do not upgrade an inference into a fact when rewriting prose.

## Qualify "current"

Never use `current`, `latest`, `now`, or similar terms without a clear subject.

Good:

> Current Zlyme configuration...

> Zlyme as of commit X...

> Stock firmware 20250527...

> Historical ROCKNIX Flip configuration at commit Y...

Bad:

> The current configuration...

The archived ROCKNIX fork should generally use past tense.

## Patch numbers are not conceptual identities

Do not make a patch number the primary name of a feature.

Bad:

> Patch 1012 provides DDR scaling.

Better:

> RK3566/RK3568 V2-SIP DMC devfreq support provides DDR scaling. The archived ROCKNIX Flip implementation carried that implementation as patch 1012.

Patch numbers, filenames and distro paths can change.

The underlying hardware requirement should remain understandable after such changes.

## Distro policy is not hardware policy

Examples:

* InputPlumber is an OS input-policy choice.
* PipeWire is an audio-stack choice.
* Weston is a compatibility/display-runtime choice.
* EmulationStation behavior is not a suspend hardware limitation.
* NextUI behavior is not a hardware property.
* a Buildroot package layout is not a kernel requirement.

Document them only in the appropriate implementation context.

## Do not force every page to be distro-agnostic

Some pages are intentionally implementation-specific.

Examples:

* stock OTA internals;
* historical ROCKNIX implementation notes;
* Zlyme implementation status;
* KNULLI multiboot compatibility;
* distro-specific workarounds.

Mark them clearly instead of rewriting them into vague generic language.

Distro-agnostic does not mean deleting useful implementation evidence.

---

# Source hierarchy

No single source is universally authoritative. Use the right source for the question.

## Physical hardware / electrical behavior

Prefer, when applicable:

1. direct measurement on hardware;
2. confirmed component identification;
3. official component datasheets/TRM;
4. stock hardware behavior;
5. stock DTS/BSP;
6. independently verified community evidence.

A DTS node alone is not proof that hardware is populated.

## Stock implementation

Use:

* tracked stock firmware unpack;
* stock scripts;
* stock DTS;
* stock kernel config;
* `System.map`;
* stock boot logs;
* BSP source where corresponding behavior is established.

Always keep the firmware version explicit where relevant.

## Mainline Linux behavior

Use the actual kernel version/source being discussed.

Do not assume behavior from Linux 6.x remains unchanged in Linux 7.x.

When version-sensitive, name the kernel version.

## Zlyme implementation

Use:

```text
Zetarancio/zlyme
```

for current implementation state.

Examples:

* active kernel configuration;
* kernel-module packaging;
* InputPlumber state;
* Weston runtime;
* NextUI behavior;
* current DMC implementation;
* current suspend implementation.

Do not infer Zlyme behavior from the archived ROCKNIX fork.

## Historical ROCKNIX implementation

Use:

```text
Zetarancio/distribution
```

only as historical evidence/reference after it is archived.

It may answer questions such as:

* how a hardware issue was first solved;
* which patch was used at the time;
* which DTS state was proven;
* which runtime behavior was observed;
* which implementation informed later Zlyme work.

It should not be used as the default answer to:

> What does the maintained Miyoo Flip system currently do?

That answer should come from Zlyme.

## Official upstream ROCKNIX

Use:

```text
ROCKNIX/distribution
```

as an external reference.

It may be useful for generic RK3566 and package/kernel research.

It does not define current Miyoo Flip behavior for this project.

## Conflicting evidence

Do not silently choose one source.

Document:

* what each source says;
* its version/date;
* which behavior was actually measured;
* the best-supported conclusion;
* any remaining uncertainty.

---

# Current high-value device invariants

These are examples of facts that must not be accidentally lost while reorganizing documentation.

They are not a substitute for reading the relevant pages.

* Device: original Miyoo Flip / my355.
* SoC: Rockchip RK3566.
* CPU: 4× Cortex-A55.
* GPU: Mali-G52.
* PMIC/audio codec: RK817.
* Retail VDD_CPU regulator: RK8600 at I2C address `0x40`.
* Wi-Fi/Bluetooth: RTL8733BU.
* Debug UART: `ttyS2`, 1,500,000 baud, 3.3 V.
* Upper USB-C is the powered host connector.
* Upper USB host requires EHCI + OHCI and the required PHY clock for full-speed devices and correct suspend behavior.
* Lower USB-C is charge/gadget and does not provide the same host VBUS path.
* Both MicroSD slots share the relevant I/O-voltage rail; mixed-voltage assumptions are unsafe.
* Miyoo analog-stick communication uses UART1 and the documented Miyoo serial protocol.
* GPIO2_B6 is part of the Miyoo joypad UART path and must not be classified as unused.
* Rumble uses PWM5 in the established implementation.
* Standard suspend has been demonstrated.
* Deep suspend is a separate BL31/SIP mechanism from ordinary suspend.
* `vdd_logic` off-in-suspend is only safe when BL31 is configured for the required logic-domain save/restore mode such as `ARMOFF_LOGOFF`.
* DDR dynamic scaling and deep-suspend configuration are independent mechanisms.
* RK3566/RK3568 DMC frequency scaling uses the Rockchip V2 SIP shared-memory / MCU-completion protocol in the established implementation.
* RK817 `SYS_CAN_SD` handling is the established cause/fix area for the measured ~8 mA off-state drain.
* The multiboot preloader work changes SPL DT behavior; it must not be casually conflated with Linux runtime power behavior.

If reorganizing text appears to contradict one of these, stop and inspect the evidence before changing the conclusion.

---

# Repository areas

## `docs/`

Maintained human-readable wiki.

Changes here should improve clarity without destroying evidence provenance.

## `miyoo355_fw_20250527/`

Tracked stock-firmware reference material.

Treat as evidence.

Do not reformat, normalize, reorganize or clean up the unpacked vendor tree without an explicit task.

## `spi_20241119160817/`

Historical stock SPI/reference dump and unpacked artifacts.

Treat as evidence.

Do not edit files inside it merely to make them consistent with current documentation.

## `bl31_*`

Firmware/disassembly evidence.

Do not reformat large assembly/disassembly files during documentation cleanup.

## `logs/`

Captured evidence.

Logs are historical records, not current-state documentation.

Do not edit old log contents.

If a new test supersedes an old capture, add a new capture and update documentation explaining their relationship.

## `preloader-stock-rocknix/`

Operational boot/preloader tools.

The directory name is historical and does not imply ROCKNIX remains the active project.

Some scripts intentionally erase or rewrite SPI NAND.

Do not rename or rewrite this directory merely because the ROCKNIX fork is archived unless there is a separate migration task with compatibility/link analysis.

Do not modify these scripts during documentation restructuring except to repair documentation links/comments made invalid by a move.

Never weaken safety checks as cleanup.

## `test-scripts/`

Hardware investigation helpers.

Preserve diagnostic intent.

Do not execute destructive or hardware-writing commands merely to validate documentation.

---

# Hardware safety rules

Changes involving any of the following are safety-sensitive:

* SPI NAND;
* preloader;
* U-Boot;
* MTD;
* raw flash offsets;
* SFC registers;
* PMIC registers;
* regulator voltage;
* GPIO output levels;
* DDR;
* suspend;
* clock/PLL programming;
* battery/charger settings.

Do not guess register values, offsets, partition identities or device paths.

Do not turn a documented diagnostic experiment into a recommended command without understanding its risk.

Do not remove safety gates from flash-writing scripts.

Do not make a destructive operation automatic if it was previously explicitly user-triggered.

The `PreloaderEraser` is intentionally destructive. Do not simplify its semantics.

The multiboot installer intentionally validates board identity, flash geometry, images, DRAM blob, bad blocks, power state, backups and readback. Those checks are part of the design.

---

# Historical investigations

Long-form investigations may contain statements later disproved by subsequent sections.

Do not fix such documents by deleting the failed reasoning.

Instead:

1. keep the chronological experiment;
2. maintain a prominent current-conclusion banner;
3. link to the current canonical page;
4. label superseded claims where necessary.

A reader should be able to understand both:

* what was believed at the time;
* what later evidence established.

---

# Implementation status pages

Keep implementation status separate from hardware truth.

Recommended location:

```text
docs/implementations/
├── README.md
├── stock.md
├── rocknix.md
└── zlyme.md
```

## `stock.md`

Vendor implementation/reference.

Document firmware versions explicitly.

## `rocknix.md`

Historical implementation page.

It should clearly state near the top:

* the maintainer's Miyoo Flip ROCKNIX fork is archived;
* it is no longer the active implementation;
* the page preserves historically useful implementation details and evidence;
* new Miyoo Flip OS development happens in Zlyme;
* official upstream ROCKNIX is a separate external project.

Use past tense where appropriate.

Do not maintain a rolling "current ROCKNIX Flip state" for the archived fork.

## `zlyme.md`

Active implementation page.

This is the correct place in the wiki for concise cross-references to current Zlyme implementation status.

Do not duplicate Zlyme's own architecture documentation in the wiki.

The wiki should summarize only what is useful to connect hardware facts to the active implementation.

Example:

```text
Hardware wiki:
The analog stick uses UART1 and protocol X.

Zlyme implementation page:
Zlyme currently exposes this through driver Y and input policy Z.
```

---

# Updating the wiki after future work

Use this decision test:

> Would this statement remain true if the Miyoo Flip ran a completely different operating system?

If yes, it probably belongs in the hardware/firmware part of the wiki.

If no, it probably belongs in an implementation-status page or in the implementation repository itself.

## When Zlyme changes

Zlyme is the active implementation.

First update Zlyme's own documentation when the change is about:

* packaging;
* init/services;
* InputPlumber policy;
* NextUI;
* Weston;
* emulator runtime;
* filesystem design;
* build system;
* module loading policy;
* frontend behavior.

Update this wiki when:

* the change establishes a new hardware fact;
* it establishes a firmware/protocol fact;
* it changes the concise Zlyme implementation status useful to wiki readers;
* it supersedes an old hardware interpretation.

Example:

A new Zlyme joypad driver exposes the same known UART protocol differently:

```text
Zlyme docs -> implementation details
wiki       -> only concise implementation status
```

During that work a previously unknown packet field is decoded:

```text
wiki       -> protocol fact + evidence
Zlyme docs -> implementation details using it
```

## When deep suspend work changes

If Zlyme successfully enables deep suspend:

* update Zlyme implementation docs;
* update `docs/implementations/zlyme.md`;
* do not rewrite the historical ROCKNIX page to imply ROCKNIX changed.

If the work discovers a new BL31 flag, regulator constraint, wake-source limitation or measured hardware behavior:

* also update the generic suspend/hardware documentation.

## When InputPlumber changes

InputPlumber itself is Zlyme policy.

Document in the hardware wiki only:

* physical controls;
* UART/GPIO protocol;
* Linux input capabilities where relevant;
* hardware limitations;
* facts learned while implementing the driver.

Document in Zlyme:

* virtual controller policy;
* player assignment;
* controller merging;
* grabs;
* mappings;
* hotkey policy;
* startup ordering.

## When the joypad driver changes

Kernel implementation details belong primarily in Zlyme.

Newly discovered hardware/protocol details belong in this wiki.

## When upstream ROCKNIX changes

Do not automatically update this wiki.

Use upstream ROCKNIX only when the change provides relevant evidence or a generally useful implementation comparison.

Do not maintain a mirror of upstream ROCKNIX status.

## When the archived ROCKNIX fork is referenced

Treat it as historical evidence.

Prefer wording such as:

> The archived Miyoo Flip ROCKNIX port established...

rather than:

> ROCKNIX currently does...

## When stock firmware is newly analyzed

Keep the firmware version explicit.

Do not overwrite older stock observations unless they were factually erroneous.

Where stock versions differ, document both.

## When a patch is upstreamed

Change implementation wording from:

> implemented by local patch N

to:

> provided by upstream Linux since version/commit X

while preserving the hardware reason the functionality exists.

## When a workaround becomes obsolete

Before deleting documentation:

1. establish why it existed;
2. identify what upstream/device change made it unnecessary;
3. record the transition;
4. preserve historical references where they explain old logs or commits.

---

# Documentation style

Write for humans first while keeping structure explicit enough for tools and AI agents.

Prefer:

* descriptive headings;
* explicit nouns instead of ambiguous pronouns;
* tables for structured facts;
* code blocks for exact register/DTS/config examples;
* short paragraphs;
* relative repository links;
* exact dates, versions and commits where state can change.

Avoid:

* marketing language;
* unexplained acronyms when they matter;
* vague `it`, `this`, `current`, or `latest`;
* duplicated long explanations across several pages;
* claims without provenance when evidence exists in the repository.

A page should be understandable without access to the author's workstation.

Never put developer-local absolute filesystem paths into canonical documentation.

---

# Links and moves

When moving a document:

1. search the entire repository for references to the old path;
2. update Markdown links;
3. update links from scripts/comments if relevant;
4. check root `README.md`;
5. check `docs/README.md`;
6. check sibling `See also` sections;
7. avoid breaking externally useful anchors unnecessarily.

Prefer semantic headings that remain stable.

Do not rename files merely for aesthetic consistency when the move provides no information-architecture benefit.

---

# Evidence preservation

Never modify a raw capture to make it agree with the current conclusion.

Examples:

* boot logs;
* register dumps;
* stock rootfs files;
* decompiled vendor DTS;
* BL31 disassembly;
* binary images.

Documentation may explain that an artifact is old, misleading in isolation, or superseded.

The artifact itself remains evidence.

When adding a new capture, include enough context to identify:

* date;
* OS/build;
* kernel;
* relevant branch/commit if known;
* hardware condition such as charger/card state;
* command/tool used where useful.

---

# Confidence and provenance

For important claims, prefer links to the actual supporting artifact or upstream source.

Avoid circular sourcing where page A cites page B and page B merely cites page A.

When possible, the chain should end at:

* measurement/log;
* stock artifact;
* source code;
* datasheet/TRM;
* commit;
* external primary source.

Community sources are valid evidence when clearly attributed.

Do not represent community packaging or inference as an official Miyoo statement.

---

# Code and script changes

This is primarily a documentation/reference repository, but some executable tools exist.

For shell:

* quote variables;
* validate destructive targets;
* fail visibly;
* preserve explicit user intent for destructive actions;
* do not replace hardware readiness/verification with arbitrary sleeps;
* preserve rollback where available.

For Python:

* prefer the standard library for small diagnostic tools;
* make device/port assumptions explicit;
* fail with actionable errors.

Do not refactor working hardware tools merely because their style differs from normal application code.

Correctness and recoverability outrank elegance.

---

# Agent workflow

Before changing a subsystem page:

1. read the page completely;
2. read directly linked evidence/reference pages;
3. search the repository for the subsystem/topic;
4. distinguish hardware facts from implementation choices;
5. distinguish current Zlyme state from historical ROCKNIX state;
6. distinguish historical observations from current conclusions;
7. make the smallest coherent documentation change.

Before changing a hardware conclusion:

1. find the evidence;
2. identify its version/date;
3. check whether newer evidence contradicts it;
4. preserve uncertainty honestly.

Before changing operational scripts:

1. understand the hardware operation;
2. understand failure/recovery behavior;
3. preserve existing safety gates;
4. make no unrelated changes.

---

# Phase separation

Documentation restructuring must not silently change technical conclusions.

A documentation-only task may:

* move pages;
* split mixed pages;
* add implementation-status sections;
* clarify evidence status;
* fix links;
* improve headings;
* remove duplicated prose after verifying equivalence.

It must not, without explicit instruction:

* alter register values;
* change hardware recommendations;
* rewrite scripts;
* replace drivers;
* change binary artifacts;
* reinterpret experimental results;
* declare an untested feature working.

---

# Validation for documentation changes

Before completion:

* search for stale moved paths;
* inspect changed links;
* search for references to old headings;
* verify code blocks were not accidentally altered;
* verify numbers/register values survived moves unchanged;
* verify implementation-specific claims remain correctly attributed;
* verify archived ROCKNIX state is not described as current;
* verify current project implementation references point to Zlyme;
* check root `README.md` and `docs/README.md` agree about structure.

If a link checker is available, run it.

Do not claim a hardware fact was revalidated merely because documentation was reorganized.

---

# Commit discipline

Prefer one conceptual reason per commit.

Good examples:

```text
docs: define distro-independent documentation model
docs: mark ROCKNIX Flip implementation as archived
docs: establish Zlyme as active implementation
docs: separate implementation status from suspend mechanism
docs: consolidate Miyoo Flip input hardware reference
```

Avoid vague commits such as:

```text
cleanup wiki
```

if they mix moves, technical corrections, script changes and new conclusions.

---

# What not to do

Do not:

* turn this into a ROCKNIX wiki;
* turn this into a Zlyme architecture manual;
* treat the archived ROCKNIX fork as current;
* try to keep the archived ROCKNIX fork synchronized;
* treat upstream ROCKNIX as authoritative for Zlyme;
* delete historical ROCKNIX evidence because Zlyme replaced it;
* delete stock/BSP evidence because mainline works;
* erase failed investigations;
* generalize one tested unit into unsupported claims;
* infer hardware population solely from a DTS;
* treat patch numbering as architecture;
* treat compilation as hardware validation;
* edit raw logs to match current expectations;
* normalize unpacked vendor files;
* change flash tools during unrelated documentation work;
* invent missing provenance;
* silently resolve conflicting evidence;
* make destructive commands easier to run accidentally.

The goal is not to make the repository look cleaner.

The goal is to make the accumulated Miyoo Flip knowledge easier to trust and easier to reuse.
