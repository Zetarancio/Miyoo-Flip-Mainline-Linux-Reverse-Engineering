# Hardware & Serial Console

## Miyoo Flip Specifications

| Component | Detail |
|-----------|--------|
| SoC | Rockchip RK3566 (quad Cortex-A55 @ 1.8 GHz) |
| GPU | Mali-G52 2EE (Bifrost), 200-800 MHz |
| RAM | LPDDR4 |
| Storage | SPI NAND 128 MB (Winbond, via SFC) |
| SD slots | 2x MicroSD (MMC1 @ fe2b0000, MMC2 @ fe2c0000) |
| Display | 640x480 MIPI DSI, FT8006M controller, 2-lane RGB888 burst |
| Backlight | PWM4-driven |
| WiFi/BT | RTL8733BU (USB combo module) |
| Audio | RK817 integrated codec, I2S, speaker amplifier |
| PMIC | RK817 (main) + RK8600 at I2C 0x40 (VDD_CPU) |
| USB | USB 2.0 OTG |
| UART | ttyS2 (fe660000), 1,500,000 baud, 3.3V |

For pinout and board photos, see
[steward-fu's pin mapping](https://steward-fu.github.io/website/handheld/miyoo_flip_pin.htm)
and [specs page](https://steward-fu.github.io/website/handheld/miyoo_flip_spec.htm).

## Serial Console (UART)

Serial is essential for debugging boot issues. The Miyoo Flip exposes UART
on test pads accessible when the case is opened.

### Adapter and Voltage

Use any USB-to-TTL adapter with **3.3V logic** (FT232RL, CP2102, CH340G).
Set the adapter jumper to **3.3V**. Do **not** use 5V -- the RK3566 is 3.3V
and 5V will damage the SoC.

### Wiring

| Miyoo Flip | Adapter |
|------------|---------|
| TX | RX |
| RX | TX |
| GND | GND |

Do **not** connect adapter VCC to the Flip if the Flip is powered by
battery or USB. If you see no output, try swapping TX/RX.

### Baud Rate

**1,500,000** (1.5M baud). The kernel command line uses
`console=ttyS2,1500000n8`. If you see garbage, your terminal is at the
wrong baud rate.

### Connecting

```bash
# Find the adapter
ls /dev/ttyUSB*

# minicom (with capture to file)
# Reference copies in this repo: boot_log_STOCK_INCLUDE_SLEEP_POWEROFF.txt (stock), boot_log_ROCKNIX.txt (mainline/ROCKNIX)
sudo minicom -D /dev/ttyUSB0 -b 1500000 -C boot_log.txt

# picocom
picocom -b 1500000 /dev/ttyUSB0

# screen
screen /dev/ttyUSB0 1500000
```

### Getting a Login Shell

The kernel prints to ttyS2, but the rootfs must start a getty on ttyS2
for a login prompt. Our Buildroot rootfs overlay (`rootfs-overlay-serial/`)
configures this automatically:

- **`etc/inittab`**: Starts getty on ttyS1 and ttyS2 at 1,500,000 baud.
- **`etc/init.d/S30wifi_bt`**: Loads WiFi module and initializes Bluetooth.

If you only rebuilt the kernel without the rootfs, the device still runs
whatever rootfs is on the rootfs partition (stock or old build), which
has no serial getty. Rebuild and reflash both boot and rootfs:

```bash
make build-kernel && make build-rootfs
make build-wifi && make build-mali
make boot-img && make rootfs-img
```

### No Login After Boot

If you see kernel messages but no login prompt:

1. Confirm the rootfs was rebuilt with the serial overlay.
2. Check for `VFS: Mounted root` in the log -- if missing, the kernel
   hangs before mounting root (see [troubleshooting](troubleshooting.md)).
3. Try `init=/bin/sh` in DTS bootargs for a debug shell.
4. Verify the UART is on ttyS2 (fe660000). Some boards bring out ttyS1
   (fe650000) -- try the other TX/RX pins if available.

### SD Card Slot Mapping

| Physical Location | SPL Name | U-Boot Device | DT Address |
|-------------------|----------|---------------|------------|
| Left (near volume) | MMC2 | mmc@fe2c0000 | fe2c0000 |
| Right (near power) | MMC1 | mmc@fe2b0000 | fe2b0000 |
