#!/bin/sh
# Живой монитор питания T1100 по SSH: vbat/ibus/online + тренд заряда.
# Нужен, чтобы видеть, положительный ли баланс (на 500 мА от порта ноутбука
# работающая Ubuntu почти наверняка разряжается).
#
#   tools/host/watch-power.sh [host] [interval_sec]
#
# Ctrl-C - выход.
set -eu
HOST=${1:-10.42.66.66}
INTERVAL=${2:-15}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 \
	"root@$HOST" "sh -s $INTERVAL" <<'EOF' | awk '
function fmt(v) { return v == "" ? "?" : v }
{
	if (NR == 1) print "  время    vbat   ibus  online status        dvbat";
	split($0, f, " ");
	ts = f[1]; vb = f[2]; ib = f[3]; on = f[4]; st = f[5];
	d = (prev == "") ? "" : sprintf("%+d мВ", vb - prev);
	printf "  %s  %6s  %4s  %6s %-13s %s\n", strftime("%H:%M:%S", ts), fmt(vb), fmt(ib), fmt(on), fmt(st), d;
	if (vb != "" && vb < 3500) print "  ** НИЗКИЙ ЗАРЯД: скоро страховка выключит плату";
	prev = vb;
}'
while :; do
	vb=""
	for l in /sys/bus/iio/devices/iio:device*/in_voltage*_label; do
		[ -r "$l" ] || continue
		[ "$(cat "$l" 2>/dev/null)" = vbat ] || continue
		d=${l%_label}
		raw=$(cat "${d}_raw" 2>/dev/null) || continue
		s=$(cat "${d}_scale" 2>/dev/null); [ -n "$s" ] || s=1
		vb=$(awk -v r="$raw" -v sc="$s" 'BEGIN{v=r*sc; if(v>10000)v/=1000; printf "%d", v+0.5}')
		break
	done
	ib=""
	for l in /sys/bus/iio/devices/iio:device*/in_current*_label; do
		[ -r "$l" ] || continue
		[ "$(cat "$l" 2>/dev/null)" = ibus ] || continue
		d=${l%_label}
		raw=$(cat "${d}_raw" 2>/dev/null) || continue
		s=$(cat "${d}_scale" 2>/dev/null); [ -n "$s" ] || s=1
		ib=$(awk -v r="$raw" -v sc="$s" 'BEGIN{printf "%d", r*sc+0.5}')
		break
	done
	on=$(cat /sys/class/power_supply/mt6370-charger/online 2>/dev/null || echo "?")
	st=$(cat /sys/class/power_supply/mt6370-charger/status 2>/dev/null || echo "?")
	echo "$(date +%s) ${vb:-} ${ib:-} $on $st"
	sleep "$1"
done
EOF
