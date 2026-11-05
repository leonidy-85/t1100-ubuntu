#!/bin/sh
# Battery/charging report from the running T1100 over SSH.
# Usage: tools/host/check-power.sh [host]
HOST=${1:-10.42.66.66}
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 \
    root@"$HOST" 'sh -s' <<'EOF'
echo "=== power_supply:"
ls /sys/class/power_supply/ 2>/dev/null || echo "  (none)"
for ps in /sys/class/power_supply/*; do
	[ -d "$ps" ] || continue
	echo "--- $ps"
	for f in online status charge_type usb_type capacity voltage_now current_now \
	         constant_charge_current constant_charge_voltage input_current_limit; do
		[ -r "$ps/$f" ] && printf '  %-24s %s\n' "$f" "$(cat "$ps/$f" 2>/dev/null)"
	done
done
echo "=== IIO (vbat/ibus/ibat):"
for l in /sys/bus/iio/devices/iio:device*/in_*_label; do
	[ -r "$l" ] || continue
	n=${l%_label}
	echo "  $(cat "$l"): raw=$(cat ${n}_raw 2>/dev/null) scale=$(cat ${n}_scale 2>/dev/null)"
done
echo "=== charger/tcpc в dmesg:"
dmesg | grep -iE "mt6370|tcpci|tcpm|charger" | tail -12
echo "=== typec:"
ls /sys/class/typec 2>/dev/null || echo "  (no typec class)"
EOF
