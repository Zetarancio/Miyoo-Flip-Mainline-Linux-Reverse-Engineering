#!/bin/sh
# Miyoo Flip — power / PMIC / charger investigation dump (ROCKNIX on device).
# Mirrors captures from Steward-fu-FLIP logs/Stock-dump.txt and logs/Rocknix-dump-Before-ChargerFIX.txt:
#   I2C scan, RK817 (0x20) + RK8600 (0x40) dumps, RK817 register spot-reads, GPIO, pinmux,
#   pinconf, regulator_summary, pm_genpd_summary, clk_summary.
#
# Requires: root, CONFIG_DEBUG_FS, i2c-tools (i2cdetect, i2cdump, i2cget), /sys mounted.
#
# Usage on device:
#   sh miyoo-flip-power-dump.sh
#   sh miyoo-flip-power-dump.sh /storage/.miyoo-dump.txt
#
# From PC (wiki repo):
#   scp test-scripts/miyoo-flip-power-dump.sh root@<flip-ip>:/tmp/
#   ssh root@<flip-ip> 'sh /tmp/miyoo-flip-power-dump.sh && cat /tmp/miyoo-flip-power-dump-*.txt' | tee flip-dump-new.txt

OUT="${1:-/tmp/miyoo-flip-power-dump-$(date +%Y%m%d-%H%M%S).txt}"

# i2cdetect: busybox vs i2c-tools; -f is not universal (see old ROCKNIX dump).
I2CDETECT_YA="-y -a"
if i2cdetect -h 2>&1 | grep -q '[[:space:]]-f[[:space:]]'; then
	I2CDETECT_YA="-f -y -a"
fi

# i2cdump/i2cget: use -f when it works (driver may own the bus).
I2C_FORCE=""
if i2cget -f -y 0 0x20 0x99 >/dev/null 2>&1; then
	I2C_FORCE="-f"
fi

section() {
	printf '\n\n========== %s ==========\n' "$1"
	date
}

{
	section "META / OS"
	uname -a 2>/dev/null
	cat /etc/os-release 2>/dev/null || true
	echo "hostname: $(hostname 2>/dev/null || echo '?')"
	ls -l /dev/i2c-* 2>/dev/null || true

	section "I2C BUS LIST"
	i2cdetect -l 2>/dev/null || true

	section "I2C BUS SCAN (i2cdetect $I2CDETECT_YA BUS)"
	for bus in 0 1 2 3 4 5 6 7; do
		[ -c "/dev/i2c-${bus}" ] || continue
		echo "--- bus ${bus} ---"
		i2cdetect $I2CDETECT_YA "$bus" 2>&1 || true
	done

	section "RK817 PMIC (bus 0 addr 0x20) full byte dump"
	i2cdump $I2C_FORCE -y 0 0x20 b 2>&1 || i2cdump $I2C_FORCE -y 0 0x20 2>&1 || true

	section "RK817 spot reads (same regs as stock manual i2cget)"
	for reg in 0xf2 0x99 0xa4 0xb1 0xb2 0xb3 0xb4 0x20; do
		printf 'i2cget %s -y 0 0x20 %s -> ' "$I2C_FORCE" "$reg"
		i2cget $I2C_FORCE -y 0 0x20 "$reg" 2>&1 || echo "(fail)"
	done

	section "CPU rail RK8600 (bus 0 addr 0x40)"
	if i2cdump $I2C_FORCE -y 0 0x40 b 2>&1; then
		:
	else
		i2cdump $I2C_FORCE -y 0 0x40 2>&1 || true
	fi

	section "CPU rail TCS4525 (bus 0 addr 0x1c) if present"
	if i2cdump $I2C_FORCE -y 0 0x1c b 2>&1; then
		:
	else
		i2cdump $I2C_FORCE -y 0 0x1c 2>&1 || echo "(no device or NAK — expected on RK8600 boards)"
	fi

	section "Bus 3 addr 0x3d (stock dump; skip if no i2c-3)"
	if [ -c /dev/i2c-3 ]; then
		i2cdump $I2C_FORCE -y 3 0x3d b 2>&1 || i2cdump $I2C_FORCE -y 3 0x3d 2>&1 || true
	else
		echo "/dev/i2c-3 not present"
	fi

	section "/sys/class/power_supply"
	for d in /sys/class/power_supply/*; do
		[ -d "$d" ] || continue
		echo "--- $d ---"
		for f in uevent type status voltage_now voltage_avg current_now current_avg capacity charge_type model_name; do
			[ -r "$d/$f" ] && printf '%s: %s\n' "$f" "$(cat "$d/$f" 2>/dev/null)"
		done
	done 2>/dev/null || echo "(none)"

	section "/sys/kernel/debug/gpio"
	if [ -r /sys/kernel/debug/gpio ]; then
		cat /sys/kernel/debug/gpio
	else
		echo "MISSING: mount debugfs (mount -t debugfs none /sys/kernel/debug) or enable CONFIG_DEBUG_FS"
	fi

	section "/sys/kernel/debug/pinctrl/pinctrl-rockchip-pinctrl/pinmux-pins"
	if [ -r /sys/kernel/debug/pinctrl/pinctrl-rockchip-pinctrl/pinmux-pins ]; then
		cat /sys/kernel/debug/pinctrl/pinctrl-rockchip-pinctrl/pinmux-pins
	else
		echo "MISSING pinmux-pins"
	fi

	section "/sys/kernel/debug/pinctrl/pinctrl-rockchip-pinctrl/pinconf-pins"
	if [ -r /sys/kernel/debug/pinctrl/pinctrl-rockchip-pinctrl/pinconf-pins ]; then
		cat /sys/kernel/debug/pinctrl/pinctrl-rockchip-pinctrl/pinconf-pins
	else
		echo "MISSING pinconf-pins"
	fi

	section "/sys/kernel/debug/regulator/regulator_summary"
	if [ -r /sys/kernel/debug/regulator/regulator_summary ]; then
		cat /sys/kernel/debug/regulator/regulator_summary
	else
		echo "MISSING regulator_summary"
	fi

	section "/sys/kernel/debug/pm_genpd/pm_genpd_summary"
	if [ -r /sys/kernel/debug/pm_genpd/pm_genpd_summary ]; then
		cat /sys/kernel/debug/pm_genpd/pm_genpd_summary
	else
		echo "MISSING pm_genpd_summary"
	fi

	section "/sys/kernel/debug/clk/clk_summary"
	if [ -r /sys/kernel/debug/clk/clk_summary ]; then
		cat /sys/kernel/debug/clk/clk_summary 2>&1
	else
		echo "MISSING clk_summary"
	fi

	section "DONE"
	echo "i2cdetect options used: $I2CDETECT_YA"
	echo "i2c force flag: ${I2C_FORCE:-(none)}"
	echo "Output file (this run was also tee'd to): $OUT"
} 2>&1 | tee "$OUT"

echo "Wrote: $OUT" >&2
