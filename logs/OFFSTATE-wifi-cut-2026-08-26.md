# Off-state drain test — Wi-Fi chip cut before power-off (2026-08-26)

**Ran 02:52:12 → 08:36:02. Valid test, no measurable drain, and the fuel gauge
proved unusable for this kind of measurement.**

(Copy held on NVMe because the SPCC USB drive silently lost the first version of
this file.)

## Procedure

The RTL8733BU combo chip was fully powered down before `poweroff`:

1. `rfkill block all`
2. `rmmod btusb`, `rmmod btrtl`
3. `rmmod 8733bu` (bounded to 25 s — this driver can hang in `netdev_close()`)
4. `echo rtl8733bu-power > /sys/bus/platform/drivers/rtl8733bu-power/unbind`,
   whose `remove()` de-asserts the chip-enable GPIO
5. `poweroff`

**No PMIC registers were modified** — `0xf4`, `0xb4`, `0xe6` were left at their
running defaults (`0x20`, `0x02`, `0x40`), isolating the Wi-Fi variable. Charger
absent throughout (`USB_EXS = 0x80`). Script and log: `/storage/offtest.sh`,
`/storage/offtest.log`. Baseline file:
`OFFSTATE-wifi-cut-baseline-20260826-025045.txt`.

## Result

| | Value |
|---|---|
| Off duration | 5 h 43 min 50 s |
| `ON_SOURCE` at next boot | `0x80` — power key. **Test valid**, no self-wake |
| `OFF_SOURCE` | `0x08` — SLPPIN_DN, clean power-down |
| Teardown | every step confirmed in `/storage/offtest.log`, chip reported unbound |

Battery, measured under near-identical load at both ends:

| | Before power-off | After 5.7 h off |
|---|---|---|
| voltage_avg | 3 785 130 µV | 3 784 990 µV |
| current_avg | −781 912 µA | −769 012 µA |
| capacity | 66 % | 81 % |
| charge_now | 1 968 540 µAh | 2 437 240 µAh |

**Terminal voltage is identical to within 140 µV at the same current, so the
state of charge did not change.** No meaningful energy was lost in 5.7 hours.
For scale, the 37.5 mA claimed in §19a would have removed ~215 mAh — about 7 %
of the pack — which would show as tens of millivolts of sag.

Meanwhile the gauge reported a **gain** of 469 mAh with no charger attached.

## The fuel gauge cannot measure this, in either direction

The jump happened at boot rather than gradually, which is the signature of an
OCV-based re-initialisation: after hours at rest the cell relaxes, the gauge
samples the open-circuit voltage, maps it through the OCV table, and overwrites
its accumulated coulomb count. Separately, at ~780 mA the IR drop across the
pack's internal resistance biases any loaded reading low.

So the 66 % carried into the shutdown was probably drifted low after an evening
of reboots under heavy load, and ~81 % is the more trustworthy figure. The
device was likely near 80 % throughout.

**Consequence: the "10 % lost over 8 hours" that started this investigation is
not credible.** The same mechanism moved the reading 15 points in the *opposite*
direction here, so a 10-point swing sits inside its error bars. §19a's 37.5 mA
must be treated as an artefact until an independent method reproduces it.

Valid methods from here:

- compare voltage at matched load, as above;
- the external ammeter from §14;
- a 24–48 h off period, so any real drain far exceeds the ~15-point gauge error.

## Caveat

This is one valid trial. It does not separate "cutting Wi-Fi fixed the
self-wake" from "this attempt happened not to wake": 2 of 6 unmodified attempts
also held for minutes, and the weaker 02:43 Wi-Fi-cut run (rfkill + unbind, no
`rmmod`) **did** self-wake after roughly 6 minutes. Repeat two or three times
before concluding.

Note also that all the short watches used last night (3–4 minutes) were too
brief: the 02:43 wake happened at ~6 minutes. Any future "stayed off" claim
needs either a long window or an `ON_SOURCE` check at the following boot.
