#!/bin/sh
#
# Miyoo Flip Multiboot — preloader repair app
#
# Installs a preloader whose SPL device tree has a working /pinctrl, so the
# SPL can mux the SD pins and read a card. Result is automatic multiboot:
#   no card                      -> stock from internal SPI NAND
#   card with a bootable U-Boot  -> that OS from SD
#   card without one            -> falls through to stock
#
# This is NOT the eraser. The eraser destroys the preloader so the bootrom
# drops into MASKROM (or falls through to SD), leaving no internal boot at
# all. This repairs the preloader instead, so stock keeps working.
#
# ─────────────────────────────────────────────────────────────────────
# CREDITS
#
# The method implemented here is not mine. It was researched, documented
# and published by apommel:
#
#     https://github.com/apommel/baseos-my355
#     docs/02-sd-boot.md          the analysis and the rationale
#     tools/mkpreloader.py        the reference patcher
#
# apommel found that Miyoo's fdtgrep run left /pinctrl in the SPL device
# tree as an empty skeleton. No pinctrl driver binds to it, so
# dwmmc@fe2b0000's pinctrl-0 is never applied, the SD pins are never
# muxed, and the SPL cannot read a card even though its code is perfectly
# capable of it. Restoring nine properties on that node fixes it. The DDR
# blob, the SPL code and the boot order all stay exactly as the vendor
# shipped them — this repairs Miyoo's own preloader rather than replacing
# it, which is why internal stock boot survives.
#
# Thanks to apommel for doing the hard part and for writing it up so
# clearly that it could be reproduced and verified independently.
# ─────────────────────────────────────────────────────────────────────
#
# WHERE THIS CAN RUN
#
# It runs on both stock and ROCKNIX, but it can only WRITE where the
# kernel exposes the preloader region as an MTD node:
#
#   ROCKNIX  mtd0 = "preloader" (2 MiB)          -> writes
#   stock    no MTD covers 0x000000-0x200000     -> refuses, reports
#
# Stock's partitions come from mtdparts= on the kernel command line and
# start at vnvm (0x200000); nothing covers the preloader, and
# CONFIG_MTD_PARTITIONED_MASTER is not set. Erasing can be done blind
# through the SFC (see ../PreloaderEraser/launch.sh) because erase needs
# no ECC. Writing cannot: NAND pages need correct ECC and only the MTD
# layer produces it. On stock this app therefore writes NOTHING and
# leaves a diagnostic report instead.
#
# USAGE
#
#   sh launch.sh                 install the patched preloader (default)
#   sh launch.sh restore         put a stock preloader back
#   sh launch.sh restore FILE    put a specific image back
#   sh launch.sh backup          read the current preloader out, no write
#
# Launchers that cannot pass arguments: create an empty file named
# RESTORE next to this script to select restore mode.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCHED="$SCRIPT_DIR/preloader-patched.img"
STOCK="$SCRIPT_DIR/preloader-stock.img"
REPORT="$SCRIPT_DIR/mtd-report.txt"
# LOG is set once the mode is known, so a restore cannot overwrite the
# record of an install.
LOG="$SCRIPT_DIR/install-log.txt"

PRELOADER_BYTES=2097152
MD5_PATCHED=c2009762b1704d5ed2ebbfa4346e6ecc
MD5_STOCK=1d525e6e6c89bd788b5245c90c97833b
# An erased 2 MiB region. Seen in the wild: if the preloader was erased
# earlier (PreloaderEraser), the "backup" taken before patching is this.
# Writing it back does not restore anything, it erases.
MD5_BLANK=b23b5d09162b92c0284923a7f628d2a5

# The DRAM init blob (ddrbin), 0x20620-0x02e000 inside the 2 MiB region:
# 55776 bytes, identical in preloader-stock.img and preloader-patched.img
# because the patch only touches the two SPL device trees. It is the
# public Rockchip rk3566 1056 MHz v1.18 binary — the same bytes appear in
# the community unbrick update.img, and ROCKNIX boots this board on a
# newer generic v1.23, so these blobs are not per-unit calibration data.
#
# Used as a gate: if a unit's EXISTING preloader carries a different
# ddrbin, its DRAM configuration differs from the bundled image and must
# not be overwritten. Aligned for bs=32 so busybox dd stays quick.
MD5_DDRBIN=4824552a71c46199c7c260d68b6a831f
DDR_BS=32
DDR_SKIP=4145
DDR_COUNT=1743

log() {
	echo "$@"
	echo "$(date '+%H:%M:%S') $*" >>"$LOG" 2>/dev/null || true
}

# A failed redirect is reported by the shell itself, so `2>/dev/null` on the
# echo does not silence it. ROCKNIX has no charger LED; stock does.
LED=/sys/class/leds/charger/trigger
led() {
	[ -w "$LED" ] && echo "$1" >"$LED" 2>/dev/null
	return 0
}

# ── Banner ────────────────────────────────────────────────────────
#
# Escape codes go to the screen only; putting them through log() would
# litter the log file. The art is 63 columns, so it fits the Flip's
# 640x480 console (80 columns at the default 8x16 font).

RED=$(printf '\033[1;31m')
NC=$(printf '\033[0m')

banner() {
	clear 2>/dev/null || printf '\033[2J\033[H'
	printf '%s' "$RED"
	echo ' █████╗ ██████╗  ██████╗ ███╗   ███╗███╗   ███╗███████╗██╗     '
	echo '██╔══██╗██╔══██╗██╔═══██╗████╗ ████║████╗ ████║██╔════╝██║     '
	echo '███████║██████╔╝██║   ██║██╔████╔██║██╔████╔██║█████╗  ██║     '
	echo '██╔══██║██╔═══╝ ██║   ██║██║╚██╔╝██║██║╚██╔╝██║██╔══╝  ██║     '
	echo '██║  ██║██║     ╚██████╔╝██║ ╚═╝ ██║██║ ╚═╝ ██║███████╗███████╗'
	echo '╚═╝  ╚═╝╚═╝      ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝'
	printf '%s\n' "$NC"
	log "SD multiboot for the Miyoo Flip — method by apommel"
	log "https://github.com/apommel/baseos-my355"
	log ""
}

die() {
	log "ERROR: $*"
	banner
	log "  ***  $MODE FAILED  —  NOTHING WAS WRITTEN  ***"
	log ""
	log "  $*"
	log ""
	log "The preloader is untouched, so the device boots exactly as it"
	log "did before. Details: $(basename "$LOG")"
	led none
	sleep 15
	exit 1
}

credits() {
	log "Method, analysis and reference patcher by apommel:"
	log "  https://github.com/apommel/baseos-my355  (docs/02-sd-boot.md)"
	log "Miyoo's fdtgrep run left the SPL's /pinctrl node empty, so the SD"
	log "pins were never muxed. apommel identified that and the nine"
	log "properties that fix it. The DDR blob, the SPL code and the boot"
	log "order remain the vendor's. Thanks to apommel for the research."
}

# ── Mode ──────────────────────────────────────────────────────────

MODE=install
case "$1" in
install | restore | backup) MODE=$1 ;;
"") [ -f "$SCRIPT_DIR/RESTORE" ] && MODE=restore ;;
*) MODE=install ;;
esac
# A BACKUP marker wins over RESTORE: it is the read-only dry run, so if
# both files exist the safe one should be the one that happens.
[ -f "$SCRIPT_DIR/BACKUP" ] && MODE=backup
[ "$BACKUP_ONLY" = "1" ] && MODE=backup

case "$MODE" in
restore) LOG="$SCRIPT_DIR/restore-log.txt" ;;
backup) LOG="$SCRIPT_DIR/backup-log.txt" ;;
esac

: >"$LOG" 2>/dev/null || true
led heartbeat
[ -f "$SCRIPT_DIR/installing.png" ] && [ -x /usr/bin/fbdisplay ] &&
	/usr/bin/fbdisplay "$SCRIPT_DIR/installing.png" &

banner
log "  Miyoo Flip Multiboot  —  mode: $MODE"
log "$(date '+%Y-%m-%d %H:%M:%S')  $(uname -srm)"
log ""
credits
log ""

[ "$(id -u)" -eq 0 ] || die "must run as root"

# ── Which system is this ──────────────────────────────────────────

PLATFORM=unknown
if grep -qi rocknix /etc/os-release 2>/dev/null; then
	PLATFORM=ROCKNIX
elif [ -d /usr/miyoo ]; then
	PLATFORM="stock"
fi
log "platform: $PLATFORM"

# ── Board gate ────────────────────────────────────────────────────
#
# The bundled image carries a DRAM init blob and assumes a fixed NAND
# geometry, so refuse anything that is not recognisably a Miyoo Flip on
# an RK3566. Both systems expose this, with different model strings:
#
#   stock    "MIYOO RK3566 355 V10 Board"
#   ROCKNIX  "Miyoo Flip"
#
# Absent properties only warn: a kernel without an unflattened DT is odd
# but not proof of wrong hardware, and the geometry and ddrbin checks
# further down are the ones that actually protect the flash.
#
# FORCE=1 overrides. Only reasonable if you have compared the ddrbin
# yourself — see README.md.

dtprop() {
	[ -f "/proc/device-tree/$1" ] || return 1
	tr '\000' ' ' <"/proc/device-tree/$1"
}

MODEL=$(dtprop model 2>/dev/null | sed 's/ *$//')
COMPAT=$(dtprop compatible 2>/dev/null | sed 's/ *$//')
log "board model: ${MODEL:-<none>}"
log "compatible : ${COMPAT:-<none>}"

GATE=
# Broad on purpose: stock says "rockchip,rk3566-miyoo-355-v10-linux",
# mainline trees may label the same silicon rk3568/rk356x. The model
# check carries the weight; this only rejects a wholly different SoC.
case "$COMPAT" in
*rk356* | *RK356*) ;;
"") log "WARNING: no device-tree compatible — cannot confirm the SoC" ;;
*) GATE="SoC is not an RK356x (compatible: $COMPAT)" ;;
esac

case "$MODEL" in
*[Mm][Ii][Yy][Oo][Oo]*) ;;
"") log "WARNING: no device-tree model — cannot confirm the board" ;;
*) GATE="${GATE:-board is not a Miyoo (model: $MODEL)}" ;;
esac

# Fingerprint only. The CPU regulator is fitted as either an RK860x or a
# FAN53555/TCS4525 and the stock kernel probes for both, so it says
# nothing about DRAM and must not gate. Recorded because it is the one
# component difference ever suspected between Flip units.
REG=$(dmesg 2>/dev/null | grep -iEm2 "rk860|fan53555|tcs4525" | sed 's/^\[[^]]*\] *//')
[ -n "$REG" ] && log "cpu regulator: $(echo "$REG" | tr '\n' ';')"
NAND=$(dmesg 2>/dev/null | grep -iEm1 "spi-nand.*(was found|MiB)" | sed 's/^\[[^]]*\] *//')
[ -n "$NAND" ] && log "spi nand: $NAND"

if [ -n "$GATE" ]; then
	if [ "$FORCE" = "1" ]; then
		log "WARNING: $GATE"
		log "WARNING: FORCE=1 given — continuing anyway"
	else
		die "$GATE — refusing (set FORCE=1 to override)"
	fi
fi

# ── Pick the image ────────────────────────────────────────────────

newest_backup() {
	# Newest backup that is a valid restore point, if any.
	#
	# Three things disqualify a file, and all three occur in practice:
	#   - wrong size
	#   - no IDB magic (a backup taken while the preloader was erased
	#     is 2 MiB of 0xff)
	#   - it IS the patched image. Running the check or a second install
	#     saves a copy of the patched preloader, and "restore" must mean
	#     undo the patch, not reapply it.
	for f in $(ls -1t "$SCRIPT_DIR"/preloader-backup-*.img 2>/dev/null); do
		[ "$(wc -c <"$f" | tr -d ' ')" = "$PRELOADER_BYTES" ] || continue
		[ "$(dd if="$f" bs=1 skip=131072 count=4 2>/dev/null)" = "RKNS" ] || continue
		if command -v md5sum >/dev/null 2>&1; then
			[ "$(md5sum "$f" | cut -d' ' -f1)" = "$MD5_PATCHED" ] && continue
		fi
		echo "$f"
		return 0
	done
	return 1
}

case "$MODE" in
install)
	if [ -n "$2" ]; then
		# Your own patched image, e.g. from mkpreloader.py against a
		# dump of this unit. Preferred over the bundled one if the
		# ddrbin gate below ever complains.
		case "$2" in
		/*) IMG=$2 ;;
		*) IMG="$SCRIPT_DIR/$2" ;;
		esac
		WANT_MD5=
		log "installing the image given on the command line"
	else
		IMG=$PATCHED
		WANT_MD5=$MD5_PATCHED
	fi
	;;
restore)
	if [ -n "$2" ]; then
		case "$2" in
		/*) IMG=$2 ;;
		*) IMG="$SCRIPT_DIR/$2" ;;
		esac
		WANT_MD5=
		log "restore image given on the command line"
	elif IMG=$(newest_backup); then
		WANT_MD5=
		log "restoring this unit's own backup: $(basename "$IMG")"
		log "  (preferred over the bundled image: entry 1 of the IDB is"
		log "   DRAM init, and it belongs to this board)"
	else
		IMG=$STOCK
		WANT_MD5=$MD5_STOCK
		log "no valid unit backup found — using bundled preloader-stock.img"
	fi
	;;
backup)
	IMG=
	WANT_MD5=
	;;
esac

# ── Validate the image ────────────────────────────────────────────

if [ -n "$IMG" ]; then
	[ -f "$IMG" ] || die "$(basename "$IMG") not found"

	SIZE=$(wc -c <"$IMG" 2>/dev/null | tr -d ' ')
	[ "$SIZE" = "$PRELOADER_BYTES" ] || die "image is $SIZE bytes, expected $PRELOADER_BYTES"

	if command -v md5sum >/dev/null 2>&1; then
		MD5=$(md5sum "$IMG" | cut -d' ' -f1)
		log "image $(basename "$IMG") md5 $MD5"
		if [ "$MD5" = "$MD5_BLANK" ]; then
			die "that image is 2 MiB of 0xff — an ERASED preloader, not a backup.
   It was almost certainly captured while the preloader was already
   erased. Writing it would erase the preloader, not restore it.
   Use preloader-stock.img, or a backup taken from a working unit."
		fi
		if [ -n "$WANT_MD5" ] && [ "$MD5" != "$WANT_MD5" ]; then
			die "image md5 does not match $WANT_MD5 (corrupt copy?)"
		fi
	fi

	# Both IDB copies must carry RKNS, or this is not a preloader at all.
	for off in 131072 524288; do
		magic=$(dd if="$IMG" bs=1 skip=$off count=4 2>/dev/null)
		[ "$magic" = "RKNS" ] || die "no RKNS magic at offset $off — not a preloader image"
	done
	log "IDB magic present at 0x20000 and 0x80000"
fi

# ── The target ────────────────────────────────────────────────────
#
# ROCKNIX names it "preloader"; a stock firmware that exposed it would
# most likely call it "spl". Accept either, but insist it is exactly
# 2 MiB so a 2 MiB image can never land on something else.

MTD=
MTDNAME=
for want in preloader spl; do
	if [ -c "/dev/mtd/by-name/$want" ]; then
		MTD=$(readlink -f "/dev/mtd/by-name/$want")
		MTDNAME=$want
		break
	fi
	n=$(grep "\"$want\"" /proc/mtd 2>/dev/null | head -n1 | cut -d: -f1)
	if [ -n "$n" ] && [ -c "/dev/$n" ]; then
		MTD="/dev/$n"
		MTDNAME=$want
		break
	fi
done

if [ -z "$MTD" ]; then
	log ""
	log "No MTD node covers the preloader region on this firmware."
	log ""
	log "This is expected on stock: its partitions come from mtdparts= on"
	log "the kernel command line and begin at vnvm (0x200000), so nothing"
	log "maps 0x000000-0x200000. Erase can bypass the kernel through the"
	log "SFC because erase needs no ECC; a write cannot, because NAND"
	log "pages need correct ECC and only the MTD layer produces it."
	log ""
	log "Do this instead, two reboots for the same end state:"
	log "  1. run ../PreloaderEraser to reach MASKROM / SD boot"
	log "  2. boot ROCKNIX from SD"
	log "  3. run this app again there (it exposes mtd0 = preloader)"
	log ""
	log "Writing a diagnostic report: $(basename "$REPORT")"
	{
		echo "Miyoo Flip multiboot — no MTD target found"
		echo "date:     $(date '+%Y-%m-%d %H:%M:%S')"
		echo "kernel:   $(uname -srvm)"
		echo "platform: $PLATFORM"
		echo "mode:     $MODE"
		echo
		echo "=== /proc/mtd ==="
		cat /proc/mtd 2>/dev/null || echo "(absent)"
		echo
		echo "=== /dev/mtd* ==="
		ls -la /dev/mtd* 2>/dev/null || echo "(none)"
		echo
		echo "=== /dev/mtd/by-name ==="
		ls -la /dev/mtd/by-name/ 2>/dev/null || echo "(none)"
		echo
		echo "=== /proc/cmdline ==="
		cat /proc/cmdline 2>/dev/null
		echo
		echo "=== mtd/spi/nand kernel messages ==="
		dmesg 2>/dev/null | grep -iE "mtd|spi-nand|sfc|nandc" | tail -40
	} >"$REPORT" 2>&1
	die "no writable preloader MTD — see $(basename "$REPORT") on the SD card"
fi

log "target $MTD (\"$MTDNAME\")"

MTDSIZE=$(grep "^$(basename "$MTD"):" /proc/mtd | awk '{print $2}')
MTDSIZE=$((0x$MTDSIZE))
[ "$MTDSIZE" = "$PRELOADER_BYTES" ] ||
	die "$MTD is $MTDSIZE bytes, refusing to write a $PRELOADER_BYTES-byte image into it"
log "size $MTDSIZE bytes — matches the image"

# The IDB header addresses its payload in 512-byte sectors laid out for
# 2 KiB pages in 128 KiB blocks. Different geometry would put the DDR
# blob and the SPL somewhere the bootrom does not look.
SYSMTD="/sys/class/mtd/$(basename "$MTD")"
WSZ=$(cat "$SYSMTD/writesize" 2>/dev/null)
ESZ=$(cat "$SYSMTD/erasesize" 2>/dev/null)
if [ -n "$WSZ" ] && [ -n "$ESZ" ]; then
	log "geometry: ${WSZ}-byte pages, ${ESZ}-byte blocks"
	[ "$WSZ" = "2048" ] && [ "$ESZ" = "131072" ] ||
		die "unexpected NAND geometry (want 2048/131072) — refusing"
else
	log "geometry unreadable from sysfs — relying on the size check"
fi

# A bad block inside the first 2 MiB is fatal for this layout: nandwrite
# skips it and every following page shifts, so the IDB sector offsets in
# the header would no longer point at the DDR blob and the SPL.
if command -v mtdinfo >/dev/null 2>&1; then
	BB=$(mtdinfo "$MTD" 2>/dev/null | grep -i "bad blocks" | head -n1 | tr -dc '0-9')
	if [ -n "$BB" ] && [ "$BB" != "0" ]; then
		die "$MTD reports $BB bad block(s); a skipped block would shift the IDB"
	fi
	log "bad blocks: ${BB:-unknown}"
else
	log "mtdinfo absent — bad-block check skipped"
fi

# ── Battery ───────────────────────────────────────────────────────

CAP=
for p in /sys/class/power_supply/*/capacity; do
	[ -f "$p" ] && CAP=$(cat "$p" 2>/dev/null) && break
done
ONLINE=0
for p in /sys/class/power_supply/*/online; do
	[ -f "$p" ] && [ "$(cat "$p" 2>/dev/null)" = "1" ] && ONLINE=1
done
if [ -n "$CAP" ]; then
	log "battery ${CAP}%, charger online=$ONLINE"
	if [ "$CAP" -lt 25 ] && [ "$ONLINE" != "1" ]; then
		die "battery ${CAP}% and not charging — plug in and retry"
	fi
else
	log "battery state unknown, continuing"
fi

# ── Read back helper ──────────────────────────────────────────────

read_mtd() {
	# $1 = destination file
	if command -v nanddump >/dev/null 2>&1; then
		nanddump -q -o /dev/null "$MTD" >/dev/null 2>&1
		nanddump -q -f "$1" "$MTD" 2>/dev/null && return 0
	fi
	if [ -c "${MTD}ro" ]; then
		dd if="${MTD}ro" of="$1" bs=2048 count=1024 2>/dev/null && return 0
	fi
	dd if="$MTD" of="$1" bs=2048 count=1024 2>/dev/null
}

# ── Backup ────────────────────────────────────────────────────────
#
# Onto the SD card, so a desktop can read it, and BEFORE anything is
# erased.

BACKUP="$SCRIPT_DIR/preloader-backup-$(date '+%Y%m%d-%H%M%S').img"
log ""
log "Backing up current preloader to $(basename "$BACKUP") ..."
if read_mtd "$BACKUP"; then
	BSIZE=$(wc -c <"$BACKUP" | tr -d ' ')
	log "  read $BSIZE bytes"
	if [ "$BSIZE" != "$PRELOADER_BYTES" ]; then
		rm -f "$BACKUP"
		die "backup is $BSIZE bytes, expected $PRELOADER_BYTES — refusing to continue"
	fi
	if command -v md5sum >/dev/null 2>&1; then
		BMD5=$(md5sum "$BACKUP" | cut -d' ' -f1)
		log "  md5 $BMD5"
		case "$BMD5" in
		"$MD5_BLANK")
			# Kept for now: it is still the honest "previous state" for
			# the rollback path below. Deleted at the end so it cannot
			# sit on the card looking like a restore point.
			BACKUP_BLANK=1
			log "  NOTE: the current preloader is ERASED (all 0xff)."
			log "  Not a restore point, so it will not be kept."
			log "  Use the bundled preloader-stock.img to get stock back."
			;;
		"$MD5_PATCHED") log "  the patched preloader is already installed" ;;
		"$MD5_STOCK") log "  currently the unmodified stock preloader" ;;
		esac
	fi

	# ── DRAM blob gate ────────────────────────────────────────
	#
	# The real risk of a shared image is imposing its DRAM init on a
	# board that needs different init. Now that this unit's current
	# preloader has been read out, compare the ddrbin directly instead
	# of arguing about it. Skipped when the region is erased, since
	# there is then nothing to compare and the user has already
	# committed to replacing it.
	if command -v md5sum >/dev/null 2>&1; then
		if [ "$BMD5" = "$MD5_BLANK" ]; then
			log "  ddrbin check skipped — current preloader is erased"
		else
			ddrbin_md5() {
				dd if="$1" bs=$DDR_BS skip=$DDR_SKIP count=$DDR_COUNT \
					2>/dev/null | md5sum | cut -d' ' -f1
			}
			HAVE=$(ddrbin_md5 "$BACKUP")
			# In backup mode there is no image to write, so compare
			# against the known-good constant instead. That makes
			# `backup` a complete read-only dry run of every gate.
			if [ -n "$IMG" ]; then
				WANT=$(ddrbin_md5 "$IMG")
				log "  ddrbin in image : $WANT"
			else
				WANT=$MD5_DDRBIN
				log "  ddrbin expected : $WANT (bundled images)"
			fi
			log "  ddrbin on device: $HAVE"
			if [ "$HAVE" = "$WANT" ]; then
				log "  DRAM init blob matches — safe to proceed"
			elif [ -z "$IMG" ]; then
				log "  NOTE: this unit's DRAM blob differs from the"
				log "  bundled images. Nothing was written (backup mode),"
				log "  but do NOT run install with the bundled image —"
				log "  patch this backup with mkpreloader.py instead."
			elif [ "$FORCE" = "1" ]; then
				log "  WARNING: ddrbin DIFFERS from the image."
				log "  WARNING: FORCE=1 given — continuing anyway."
			else
				log ""
				log "This unit's DRAM init blob differs from the one in"
				log "$(basename "$IMG"). That means a different DRAM"
				log "configuration, and writing this image could leave the"
				log "device unable to bring up RAM."
				log ""
				log "Nothing has been erased. Your preloader is intact and"
				log "also saved as $(basename "$BACKUP")."
				log ""
				log "Patch YOUR image instead, on a PC:"
				log "  python3 mkpreloader.py $(basename "$BACKUP") mine.img"
				log "  sh launch.sh install mine.img"
				die "ddrbin mismatch — refusing (set FORCE=1 to override)"
			fi
		fi
	fi
else
	die "could not read $MTD — refusing to erase something unreadable"
fi

if [ "$MODE" = "backup" ]; then
	log ""
	if [ "$BACKUP_BLANK" = "1" ]; then
		rm -f "$BACKUP"
		log "(discarded the blank copy — an erased preloader is not a"
		log " restore point, and leaving it would imply otherwise)"
	fi
	banner
	log "  ***  CHECK PASSED  —  NOTHING WAS WRITTEN  ***"
	log ""
	log "Every gate this unit has to clear was cleared: board, NAND"
	log "geometry, no bad blocks, and the DRAM blob matches the"
	log "bundled image. install-multiboot.sh is safe to run here."
	log ""
	log "Full report: $(basename "$LOG")"
	led none
	sleep 15
	exit 0
fi

# ── Write ─────────────────────────────────────────────────────────

log ""
log "Writing $(basename "$IMG"). Do not power off."
log ""

ERASE=
for c in flash_erase flash_eraseall; do
	command -v $c >/dev/null 2>&1 && ERASE=$c && break
done
[ -n "$ERASE" ] || die "no flash_erase or flash_eraseall on this system"
command -v nandwrite >/dev/null 2>&1 || die "no nandwrite on this system"

do_erase() {
	if [ "$ERASE" = "flash_erase" ]; then
		flash_erase "$MTD" 0 0 >>"$LOG" 2>&1 || log "  $ERASE returned $?"
	else
		flash_eraseall "$MTD" >>"$LOG" 2>&1 || log "  $ERASE returned $?"
	fi
}

OK=0
n=1
while [ $n -le 3 ]; do
	log "attempt $n"
	do_erase

	if nandwrite -p "$MTD" "$IMG" >>"$LOG" 2>&1; then
		VERIFY="$SCRIPT_DIR/.verify.img"
		if read_mtd "$VERIFY"; then
			if cmp -s "$VERIFY" "$IMG"; then
				rm -f "$VERIFY"
				OK=1
				log "  readback verified"
				break
			fi
			log "  readback DIFFERS from the image"
		else
			log "  could not read back"
		fi
		rm -f "$VERIFY"
	else
		log "  nandwrite failed"
	fi
	n=$((n + 1))
done

if [ "$OK" != "1" ]; then
	log ""
	log "Write could not be verified after 3 attempts."
	if [ "$BACKUP_BLANK" = "1" ]; then
		# Rolling back to 2 MiB of 0xff would just re-erase. The erase
		# above already left it that way, which IS the previous state.
		do_erase
		rm -f "$BACKUP"
		log "The preloader was already erased before this run, so there"
		log "is nothing to roll back to — it is erased again now."
		log "The device still boots from a bootable SD card, and comes up"
		log "in MASKROM with no card. Retry, or use restore-preloader.sh"
		log "to put the bundled stock preloader back."
	else
		log "Restoring the backup ..."
		do_erase
		if nandwrite -p "$MTD" "$BACKUP" >>"$LOG" 2>&1; then
			log "Backup restored. The device should boot as it did before."
		else
			log "RESTORE ALSO FAILED. Do not power off before reading this:"
			log "  Retry from ROCKNIX with:"
			log "    sh launch.sh restore $(basename "$BACKUP")"
			log "  If the device no longer boots, recover from MASKROM"
			log "  with xrock — the bootrom is not in SPI, so this is"
			log "  always possible. See the wiki, boot-and-flash/flashing.md."
		fi
	fi
	die "$MODE failed"
fi

# Succeeded, so the pre-run state is no longer interesting and a blank
# backup must not be left behind pretending to be one.
if [ "$BACKUP_BLANK" = "1" ]; then
	rm -f "$BACKUP"
	log "(discarded the blank pre-run backup)"
fi

# ── Done ──────────────────────────────────────────────────────────

banner
if [ "$MODE" = "restore" ]; then
	log "  ***  PRELOADER RESTORED  —  SUCCESS  ***"
	log ""
	log "The device boots stock from internal SPI NAND again, and"
	log "ignores cards. SD multiboot is OFF."
	log ""
	log "To turn it back on: run install-multiboot.sh"
else
	log "  ***  PRELOADER PATCHED  —  SUCCESS  ***"
	log ""
	log "  no card inserted     -> stock, from internal SPI NAND"
	log "  bootable card, RIGHT -> that OS, from SD"
	log "  charger while off    -> stock battery animation, as before"
	log ""
	log "The card must carry a U-Boot the stock SPL can load, built"
	log "for this board. ROCKNIX and apommel's MinUI base qualify;"
	log "cards made for GammaLoader (Knulli, GammaOS) do not."
	log ""
	log "To undo: run restore-preloader.sh"
fi
log ""
log "Rebooting in 15 seconds ..."

led none
sleep 15
sync
echo b >/proc/sysrq-trigger
