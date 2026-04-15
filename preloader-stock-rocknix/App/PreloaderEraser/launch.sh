#!/bin/sh
#
# Miyoo Flip Preloader Eraser (Stock OS App)
#
# Erases the SPI NAND preloader (IDBLOCK + DDR init + SPL) so the
# RK3566 bootrom falls through to the SD card, allowing ROCKNIX to
# boot without entering MASKROM mode.
#
# The preloader sits at SPI NAND offset 0x000000-0x200000 (2 MB,
# blocks 0-15), BEFORE the first MTD partition (vnvm at 0x200000).
# CONFIG_MTD_PARTITIONED_MASTER is not set on the stock kernel, so
# no /dev/mtd* device covers this area. We bypass the kernel and
# send SPI NAND erase commands directly through the Rockchip SFC
# (Serial Flash Controller) at 0xFE300000 via devmem + /dev/mem.
#
# CONFIG_IO_STRICT_DEVMEM is not set on the stock kernel, so MMIO
# regions claimed by drivers remain accessible through /dev/mem.
#
# After reboot the device boots from SD. To restore stock internal boot,
# write preloader.img back from ROCKNIX (see wiki:
# docs/boot-and-flash/stock-rocknix-without-disassembly.md) or reflash
# via MASKROM + xrock.
#
# SFC register offsets from mainline drivers/spi/spi-rockchip-sfc.c

SFC=0xFE300000
OFF_CTRL=0x00
OFF_ICLR=0x08
OFF_ABIT=0x18
OFF_FSR=0x20
OFF_SR=0x24
OFF_VER=0x2C
OFF_LEN_CTRL=0x88
OFF_LEN_EXT=0x8C
OFF_CMD=0x100
OFF_ADDR=0x104
OFF_DATA=0x108

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── LED feedback ──────────────────────────────────────────────────
echo heartbeat > /sys/class/leds/charger/trigger 2>/dev/null || true

# ── Display splash if available ───────────────────────────────────
if [ -f "$SCRIPT_DIR/installing.png" ]; then
    /usr/bin/fbdisplay "$SCRIPT_DIR/installing.png" &
fi

echo ""
echo "============================================"
echo "  Miyoo Flip Preloader Eraser"
echo "============================================"
echo ""
echo "Erasing SPI NAND preloader (blocks 0-15)."
echo "After reboot the device will boot from SD."
echo "To restore stock: reflash via MASKROM + xrock."
echo ""

# ── SFC helper functions ──────────────────────────────────────────

sfc_addr() {
    printf "0x%X" $(( SFC + $1 ))
}

sfc_read() {
    devmem $(sfc_addr $1)
}

sfc_write() {
    devmem $(sfc_addr $1) 32 $2
}

sfc_wait_idle() {
    local i=0
    while [ $(( $(sfc_read $OFF_SR) & 1 )) -ne 0 ]; do
        i=$((i + 1))
        if [ $i -gt 50000 ]; then
            echo "ERROR: SFC idle timeout" >&2
            return 1
        fi
    done
    return 0
}

sfc_version() {
    echo $(( $(sfc_read $OFF_VER) & 0xFFFF ))
}

# ── SPI NAND primitives ──────────────────────────────────────────

# Write Enable (opcode 0x06, no address, no data)
nand_write_enable() {
    sfc_wait_idle || return 1
    sfc_write $OFF_ICLR 0xFFFFFFFF
    if [ $SFC_VER -ge 4 ]; then
        sfc_write $OFF_LEN_EXT 0
    fi
    sfc_write $OFF_CTRL 0x2
    sfc_write $OFF_CMD 0x00000006
    sfc_wait_idle
}

# Block Erase (opcode 0xD8, 24-bit row address, no data)
# SFC_CMD = 0xD8 | ADDR_24BITS(1<<14) | DIR_WR(1<<12) = 0x50D8
nand_block_erase() {
    local row_addr=$1
    sfc_wait_idle || return 1
    sfc_write $OFF_ICLR 0xFFFFFFFF
    if [ $SFC_VER -ge 4 ]; then
        sfc_write $OFF_LEN_EXT 0
    fi
    sfc_write $OFF_CTRL 0x2
    sfc_write $OFF_CMD 0x000050D8
    sfc_write $OFF_ADDR $row_addr
    sfc_wait_idle
}

# Get Feature (opcode 0x0F, 1-byte addr at 0xC0, 1-byte read)
# Returns the SPI NAND status register value.
# SFC_CMD = 0x0F | ADDR_XBITS(3<<14); ABIT=7 for 8-bit address
nand_read_status() {
    sfc_wait_idle || return 1
    sfc_write $OFF_ICLR 0xFFFFFFFF
    sfc_write $OFF_ABIT 7
    if [ $SFC_VER -ge 4 ]; then
        sfc_write $OFF_LEN_EXT 1
        sfc_write $OFF_CTRL 0x2
        sfc_write $OFF_CMD 0x0000C00F
    else
        sfc_write $OFF_CTRL 0x2
        sfc_write $OFF_CMD 0x0001C00F
    fi
    sfc_write $OFF_ADDR 0xC0

    local i=0
    while [ $(( ($(sfc_read $OFF_FSR) >> 16) & 0x1F )) -eq 0 ]; do
        i=$((i + 1))
        if [ $i -gt 50000 ]; then
            echo "255"
            return 1
        fi
    done

    local data=$(sfc_read $OFF_DATA)
    sfc_wait_idle
    echo $(( data & 0xFF ))
}

# Poll until OIP (bit 0) clears; check E_FAIL (bit 2)
nand_wait_ready() {
    local i=0
    while true; do
        local st=$(nand_read_status)
        if [ $(( st & 1 )) -eq 0 ]; then
            if [ $(( st & 4 )) -ne 0 ]; then
                echo "ERROR: erase failure (E_FAIL)" >&2
                return 1
            fi
            return 0
        fi
        i=$((i + 1))
        if [ $i -gt 2000 ]; then
            echo "ERROR: NAND ready timeout" >&2
            return 1
        fi
        sleep 0.01 2>/dev/null || true
    done
}

# ── Erase one 128 KB block ────────────────────────────────────────

erase_one_block() {
    local block=$1
    local row_addr=$(( block * 64 ))

    printf "  Block %2d (row 0x%06X) ..." "$block" "$row_addr"

    nand_write_enable   || { echo " WRITE_EN FAIL"; return 1; }
    nand_block_erase $row_addr || { echo " ERASE FAIL"; return 1; }
    nand_wait_ready     || { echo " TIMEOUT"; return 1; }

    echo " OK"
}

# ── Main ──────────────────────────────────────────────────────────

SFC_VER=$(sfc_version)
echo "SFC hardware version: $SFC_VER"

if [ $SFC_VER -ge 4 ]; then
    sfc_write $OFF_LEN_CTRL 1
fi

FAIL=0
for block in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    if ! erase_one_block $block; then
        echo "  WARNING: block $block failed, continuing..."
        FAIL=$((FAIL + 1))
    fi
done

echo ""
if [ $FAIL -gt 0 ]; then
    echo "WARNING: $FAIL block(s) failed to erase."
else
    echo "Preloader erased successfully."
fi

echo ""
echo "============================================"
echo "  Done. Rebooting to SD card ..."
echo "============================================"

echo none > /sys/class/leds/charger/trigger 2>/dev/null || true

sleep 2
sync
echo b > /proc/sysrq-trigger
