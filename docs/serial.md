# Serial Console (UART)

How to obtain a serial console on the Miyoo Flip for debugging and login. Serial is essential for diagnosing boot issues.

---

## Hardware summary

| Item | Detail |
|------|--------|
| UART | ttyS2 (fe660000), 1,500,000 baud, 3.3V |
| Location | Test pads on the board (accessible when case is opened) |
| Pinout / photos | [steward-fu pin mapping](https://steward-fu.github.io/website/handheld/miyoo_flip_pin.htm), [specs](https://steward-fu.github.io/website/handheld/miyoo_flip_spec.htm) |

---

## Adapter and voltage

Use a USB-to-TTL adapter with **3.3V logic** (e.g. FT232RL, CP2102, CH340G). Set the adapter to **3.3V**; do **not** use 5V — the RK3566 is 3.3V and 5V can damage the SoC.

---

## Wiring

| Miyoo Flip | Adapter |
|------------|---------|
| TX | RX |
| RX | TX |
| GND | GND |

Do not connect adapter VCC to the Flip if the Flip is powered by battery or USB. If you see no output, try swapping TX and RX.

---

## Baud rate

**1,500,000** (1.5M baud). The kernel uses `console=ttyS2,1500000n8`. Garbage output usually means the terminal is at the wrong baud rate.

---

## Connecting

```bash
# Find the adapter
ls /dev/ttyUSB*

# minicom (with capture)
sudo minicom -D /dev/ttyUSB0 -b 1500000 -C boot_log.txt

# picocom
picocom -b 1500000 /dev/ttyUSB0

# screen
screen /dev/ttyUSB0 1500000
```

Reference boot logs in this repo root: `boot_log_ROCKNIX.txt` (mainline; **may not match the latest build**—kept as **proof** of a past capture), `boot_log_STOCK_INCLUDE_SLEEP_POWEROFF_AND_DEBUG.txt` (stock + debug), `boot_log_STOCK_INCLUDE_SLEEP_POWEROFF.txt` (stock).

---

## Getting a login shell

The kernel prints to ttyS2; the rootfs must run a getty on ttyS2 for a login prompt. Typical setup:

- **inittab** (or equivalent): getty on ttyS1 and ttyS2 at 1,500,000 baud.
- WiFi/BT init as needed (load module, init Bluetooth).

If the rootfs was not built with serial getty, you will see kernel messages but no login. Rebuild and reflash rootfs (and boot if needed) according to your distro.

---

## No login after boot

1. Confirm the rootfs was built with serial getty (ttyS2).
2. Check for `VFS: Mounted root` in the log — if missing, the kernel may hang before mounting root (see [Troubleshooting](troubleshooting.md)).
3. Try `init=/bin/sh` in DTS bootargs for a debug shell.
4. Verify the UART is ttyS2 (fe660000). Some boards use ttyS1 (fe650000); try the other TX/RX pads if available.

---

## SD card slot mapping

| Physical location | SPL name | U-Boot device | DT address |
|-------------------|----------|---------------|------------|
| Left (near volume) | MMC2 | mmc@fe2c0000 | fe2c0000 |
| Right (near power) | MMC1 | mmc@fe2b0000 | fe2b0000 |
