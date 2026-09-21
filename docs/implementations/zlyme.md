# Zlyme

**Active** Miyoo Flip operating system maintained by this project: [Zetarancio/zlyme](https://github.com/Zetarancio/zlyme).

This wiki does not copy Zlyme’s architecture manual. Implementation detail belongs in that repository. This page is only the hardware-facing status a wiki reader needs.

## Recorded status

No Zlyme commit, branch, or device capture is snapshotted here yet. Do not treat archived ROCKNIX behavior as Zlyme’s behavior.

In particular, this wiki does **not** claim that Zlyme has:

- enabled deep suspend or `vdd_logic` off-in-suspend;
- shipped a replacement joypad driver;
- adopted InputPlumber;
- packaged DMC devfreq in any particular patch layout;
- shipped a Weston compatibility runtime.

Until a Zlyme revision is cited on this page, those items are **not** current.

## Roadmap (not current)

Later edits to this page are the right place for a short status of work that is actually in Zlyme: joypad driver, InputPlumber policy, deep suspend, DMC packaging, Weston. Each line needs a Zlyme commit or an explicit “not shipped” label. Planned work stays in this section until it is observed.

Hardware facts discovered while doing that work belong on the generic pages ([Input](../hardware/input.md), [Suspend](../drivers-and-dts/suspend-and-vdd-logic.md), [USB](../drivers-and-dts/board-dts-pmic-ddr-updates.md#usb)), not only here.
