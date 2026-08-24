#!/bin/sh
#
# Miyoo Flip Preloader Eraser — MASKROM access without disassembly
#
# PRIMARY USE: reach MASKROM mode without opening the device.
#
# Erasing the SPI NAND preloader (IDBLOCK + DDR init + SPL) leaves the
# RK3566 bootrom with nothing to load internally. On the next power-on:
#
#   no SD card inserted        -> the device comes up in MASKROM,
#                                 ready for xrock / rkdeveloptool
#   bootable SD card inserted  -> the bootrom loads the card's own
#                                 idbloader and boots that OS
#
# That first behaviour is the point: MASKROM on demand, no screws, no
# button, no test point. Everything an opened-case MASKROM session can
# do — full backup, restore, reflash — becomes available from software.
#
# NOT THE WAY TO SET UP DUAL BOOT ANY MORE.
#
# Erasing removes internal boot entirely: stock no longer starts, and
# recovering it needs a PC. For running an SD distro while keeping stock
# on internal NAND, use ../apommel-multiboot instead, which REPAIRS the
# preloader rather than destroying it (method by apommel,
# https://github.com/apommel/baseos-my355). Reach for this eraser when
# you actually want MASKROM, or as the escape hatch that gets a
# stock-only device to ROCKNIX so the multiboot app can run there.
#
# HOW IT WORKS
#
# The preloader sits at SPI NAND offset 0x000000-0x200000 (2 MB,
# blocks 0-15), BEFORE the first MTD partition (vnvm at 0x200000).
# On stock, partitions come from mtdparts= on the kernel command line
# and CONFIG_MTD_PARTITIONED_MASTER is not set, so no /dev/mtd* device
# covers this area. This script therefore bypasses the kernel and sends
# SPI NAND erase commands directly through the Rockchip SFC (Serial
# Flash Controller) at 0xFE300000 via devmem + /dev/mem. Erase needs no
# ECC, which is why this is possible blind; writing would not be.
#
# CONFIG_IO_STRICT_DEVMEM is not set on the stock kernel, so MMIO
# regions claimed by drivers remain accessible through /dev/mem.
#
# On ROCKNIX the region IS exposed as mtd0 ("preloader"), so there the
# script uses flash_erase on that node instead of touching the SFC.
#
# TO UNDO
#
# From ROCKNIX: ../apommel-multiboot/restore-preloader.sh (which is
# that app's launch.sh in restore mode). From MASKROM: xrock. See
# docs/boot-and-flash/stock-rocknix-without-disassembly.md.
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

# ── Banner ────────────────────────────────────────────────────────
#
# The art is 79 columns, which is the most that fits the Flip's 640x480
# console (80 columns at the default 8x16 font). Bold yellow reads as
# amber on the framebuffer console; a 256-colour orange would not be
# safe to assume there.

ORANGE=$(printf '\033[1;33m')
NC=$(printf '\033[0m')

banner() {
    clear 2>/dev/null || printf '\033[2J\033[H'
    printf '%s' "$ORANGE"
    echo '███████╗███████╗████████╗ █████╗ ██████╗  █████╗ ███╗   ██╗ ██████╗██╗ ██████╗ '
    echo '╚══███╔╝██╔════╝╚══██╔══╝██╔══██╗██╔══██╗██╔══██╗████╗  ██║██╔════╝██║██╔═══██╗'
    echo '  ███╔╝ █████╗     ██║   ███████║██████╔╝███████║██╔██╗ ██║██║     ██║██║   ██║'
    echo ' ███╔╝  ██╔══╝     ██║   ██╔══██║██╔══██╗██╔══██║██║╚██╗██║██║     ██║██║   ██║'
    echo '███████╗███████╗   ██║   ██║  ██║██║  ██║██║  ██║██║ ╚████║╚██████╗██║╚██████╔╝'
    echo '╚══════╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝╚═╝ ╚═════╝ '
    printf '%s\n' "$NC"
}

# ── LED feedback ──────────────────────────────────────────────────
echo heartbeat > /sys/class/leds/charger/trigger 2>/dev/null || true

# ── Display splash if available ───────────────────────────────────
if [ -f "$SCRIPT_DIR/installing.png" ]; then
    /usr/bin/fbdisplay "$SCRIPT_DIR/installing.png" &
fi

banner
echo "  Miyoo Flip Preloader Eraser"
echo "  MASKROM access without disassembly"
echo ""
echo "Erasing SPI NAND preloader (blocks 0-15)."
echo ""
echo "After the reboot:"
echo "  no SD card       -> device comes up in MASKROM"
echo "  bootable SD card -> boots that OS from the card"
echo ""
echo "This REMOVES internal stock boot. To restore it you need"
echo "ROCKNIX (../apommel-multiboot/restore-preloader.sh) or"
echo "MASKROM + xrock."
echo ""
echo "Want stock AND an SD distro instead? Do not use this."
echo "Use ../apommel-multiboot, which repairs the preloader"
echo "rather than erasing it. Method by apommel:"
echo "  https://github.com/apommel/baseos-my355"
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
#
# ROCKNIX exposes the region as mtd0 ("preloader"). Prefer the MTD
# layer there: it is the supported path and it honours bad-block
# markers. Stock has no such node, hence the blind SFC path below.

MTD=
if [ -c /dev/mtd/by-name/preloader ]; then
    MTD=$(readlink -f /dev/mtd/by-name/preloader)
else
    n=$(grep '"preloader"' /proc/mtd 2>/dev/null | head -n1 | cut -d: -f1)
    [ -n "$n" ] && [ -c "/dev/$n" ] && MTD="/dev/$n"
fi

FAIL=0

if [ -n "$MTD" ] && command -v flash_erase >/dev/null 2>&1; then
    echo "Found $MTD (\"preloader\") — erasing through the MTD layer."
    echo ""
    if flash_erase "$MTD" 0 0; then
        echo ""
        echo "Preloader erased successfully."
    else
        echo ""
        echo "ERROR: flash_erase failed on $MTD"
        FAIL=1
    fi
else
    echo "No preloader MTD node — driving the SFC directly."
    echo ""

    SFC_VER=$(sfc_version)
    echo "SFC hardware version: $SFC_VER"

    if [ $SFC_VER -ge 4 ]; then
        sfc_write $OFF_LEN_CTRL 1
    fi

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
fi

banner

if [ $FAIL -gt 0 ]; then
    echo "  ***  ERASE FAILED  ***"
    echo ""
    echo "$FAIL block(s) did not erase. The preloader may be partly"
    echo "intact, so what the device does on the next boot is not"
    echo "predictable: it may still boot stock, or drop into MASKROM."
    echo ""
    echo "Recover from MASKROM with xrock if it does not come up."
    echo "The bootrom is not stored in SPI, so this is always possible."
else
    echo "  ***  PRELOADER ERASED  —  SUCCESS  ***"
    echo ""
    echo "From the next power-on:"
    echo ""
    echo "  no SD card       -> MASKROM. Connect USB and use xrock,"
    echo "                      no screws and no button needed."
    echo "  bootable SD card -> that OS boots from the card."
    echo ""
    echo "Internal stock boot is GONE until a preloader is written"
    echo "back, and with it the charging animation: plugged in while"
    echo "off, the device charges behind a black screen."
    echo ""
    echo "To put it back, from ROCKNIX: run restore-preloader.sh in"
    echo "the apommel-multiboot app. From a PC: MASKROM + xrock."
fi

echo ""
echo "Rebooting in 15 seconds ..."

echo none > /sys/class/leds/charger/trigger 2>/dev/null || true

sleep 15
sync
echo b > /proc/sysrq-trigger
