#!/bin/sh
# t1100-charge.sh - управление зарядом MT6370 на Fplus T1100 (MT6771).
#
# Что умеет:
#   status              - человекочитаемое состояние: sysfs + IIO + тепло + PD
#   set --iaicr MA --ichg MA [--cv MV] [--force]
#                       - записать лимиты и ПРОВЕРИТЬ ФАКТОМ (перечитать
#                         лимиты, ibus/vbus/vbat/ibat через 2 с);
#                         при просадке VBUS ниже 4.6 В откатывает IAICR
#   auto                - безопасные значения по умолчанию (идемпотентно);
#                         это же и профиль «дешёвый powered hub» (см. ниже)
#   hub                 - профиль для порта powered hub (5 В, IAICR по умолчанию
#                         900 мА, настраивается HUB_IAICR_UA)
#   wall                - профиль «обычный адаптер 2 А» (IAICR 2000 мА)
#   keepalive           - запретить USB autosuspend (чтобы RNDIS не отваливался
#                         при простое хоста)
#   off                 - вернуть значения «как после probe драйвера»
#   pd                  - поднять лимиты под PD-контракт (tcpm-source-psy-*)
#   redetect            - заново запустить BC1.2 (online=1)
#   sample              - одна строка key=value для замеров/CSV
#   watch [SEC]         - печатать строку измерений каждые SEC секунд
#
# Диапазоны и шаги - из drivers/power/supply/mt6370-charger.c (linear_range):
#   IAICR 100..3250 мА шаг 50 мА (0x113[7:2]), ICHG 900..5000 мА шаг 100 мА
#   (0x117[7:2]). Драйвер округляет вниз и НЕ возвращает ошибку при выходе за
#   диапазон, поэтому доверять «sysfs принял» нельзя - только перечитыванию.
#   Подробности: refs/charge-mt6370.md
#
# Настройки по умолчанию - /etc/default/t1100-charge (AUTO_IAICR_UA,
# AUTO_ICHG_UA, PD_*_CAP_UA).

set -u

# Пути можно подменить для офлайн-проверки логики (mock sysfs).
PS=${T1100_CHARGE_PS:-/sys/class/power_supply/mt6370-charger}
BAT=${T1100_BATTERY_PS:-/sys/class/power_supply/mt6370-battery}
IIO_ROOT=${T1100_IIO_ROOT:-/sys/bus/iio/devices}
THERMAL_ROOT=${T1100_THERMAL_ROOT:-/sys/class/thermal}
DEF=${T1100_CHARGE_DEF:-/etc/default/t1100-charge}

IAICR_MIN_UA=100000
IAICR_MAX_UA=3250000
IAICR_STEP_UA=50000
ICHG_MIN_UA=900000
ICHG_MAX_UA=5000000
ICHG_STEP_UA=100000
# Выше этого без --force не идём: паспорта батареи у нас нет, вендор ставил 2 А.
ICHG_SOFT_MAX_UA=2500000

# auto: вендорские 2 А в батарею (refs/stock-mt6771.dts:4376) и 900 мА входа -
# ровно то, что уже проверено на железе (STATUS 13.11 (18)); t1100-power-guard
# пишет те же 2 А, так что юниты не спорят друг с другом.
AUTO_IAICR_UA=900000
AUTO_ICHG_UA=2000000

# hub: тот же безопасный ток, что auto (порт хаба = SDP и часто 500 мА на
# порт), но профиль выделен явно, чтобы на замерах можно было поднять и
# зафиксировать найденный максимум в /etc/default/t1100-charge.
HUB_IAICR_UA=900000
HUB_ICHG_UA=2000000

# wall: обычный зарядный адаптер (DCP), вендорские 2 А входа и заряда.
WALL_IAICR_UA=2000000
WALL_ICHG_UA=2000000

# pd: не выше этих значений даже если источник предлагает больше.
PD_IAICR_CAP_UA=2000000
PD_ICHG_CAP_UA=2000000

# Порог «вход просел»: MIVR в стоке 4.4 В, ниже 4.6 В уже подозрительно.
VBUS_MIN_MV=4600

if [ -r "$DEF" ]; then
	# shellcheck disable=SC1090
	. "$DEF"
fi

log() { echo "$*"; }
warn() { echo "t1100-charge: $*" >&2; }
die() { echo "t1100-charge: $*" >&2; exit 1; }

usage() {
	awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next }
	     NR > 1 { exit }' "$0"
	exit 2
}

# --- sysfs helpers ---------------------------------------------------------

ps_read() { cat "$PS/$1" 2>/dev/null || echo "-"; }

# Число из sysfs с безопасным дефолтом (для арифметики).
ps_num() {
	v=$(cat "$PS/$1" 2>/dev/null) || v=0
	case $v in
	''|*[!0-9]*) echo 0 ;;
	*) echo "$v" ;;
	esac
}

wait_ps() {
	i=0
	while [ ! -d "$PS" ] && [ "$i" -lt 40 ]; do
		sleep 0.5
		i=$((i + 1))
	done
	[ -d "$PS" ] || die "нет $PS: mt6370-charger не пробнился (dmesg | grep mt6370)"
}

# --- IIO helpers -----------------------------------------------------------
# Метки каналов: vbusdiv5, vbusdiv2, vsys, vbat, ts_bat, ibus, ibat
# (drivers/iio/adc/mt6370-adc.c). Масштаб читаем каждый раз: для ibus/ibat он
# зависит от текущих IAICR/ICHG (33.5 vs 50 мА/ед и 23.75/26.8 vs 50 мА/ед).

iio_prefix() { # $1=voltage|current $2=label
	for d in "$IIO_ROOT"/iio:device*; do
		[ -d "$d" ] || continue
		for l in "$d"/in_"$1"*_label; do
			[ -r "$l" ] || continue
			if [ "$(cat "$l" 2>/dev/null)" = "$2" ]; then
				echo "${l%_label}"
				return 0
			fi
		done
	done
	return 1
}

iio_mv() { # $1=label $2=fallback voltage chan -> мВ
	p=$(iio_prefix voltage "$1") || p=$IIO_ROOT/iio:device0/in_voltage"$2"
	raw=$(cat "${p}_raw" 2>/dev/null) || return 1
	sc=$(cat "${p}_scale" 2>/dev/null) || sc=1
	awk -v r="$raw" -v s="$sc" 'BEGIN { printf "%d", r * s + 0.5 }'
}

iio_ma() { # $1=label $2=fallback current chan -> мА
	p=$(iio_prefix current "$1") || p=$IIO_ROOT/iio:device0/in_current"$2"
	raw=$(cat "${p}_raw" 2>/dev/null) || return 1
	sc=$(cat "${p}_scale" 2>/dev/null) || sc=1
	awk -v r="$raw" -v s="$sc" 'BEGIN { printf "%d", r * s + 0.5 }'
}

# --- тепловые зоны ---------------------------------------------------------

thermal_lines() {
	for z in "$THERMAL_ROOT"/thermal_zone*; do
		[ -r "$z/temp" ] || continue
		t=$(cat "$z/temp" 2>/dev/null) || continue
		ty=$(cat "$z/type" 2>/dev/null) || ty=?
		awk -v t="$t" -v ty="$ty" 'BEGIN { printf "  %-18s %5.1f C\n", ty, t / 1000 }'
	done
}

thermal_max_c() {
	rmax=0
	for z in "$THERMAL_ROOT"/thermal_zone*; do
		t=$(cat "$z/temp" 2>/dev/null) || continue
		[ "$t" -gt "$rmax" ] 2>/dev/null && rmax=$t
	done
	awk -v t="$rmax" 'BEGIN { printf "%.1f", t / 1000 }'
}

# --- PD --------------------------------------------------------------------

pd_psy() {
	for p in "${PS%/*}"/tcpm-source-psy-*; do
		[ -d "$p" ] && { echo "$p"; return 0; }
	done
	return 1
}

pd_contract() { # печатает "MV MA" или пусто
	p=$(pd_psy) || return 1
	mv=$(cat "$p/voltage_now" 2>/dev/null) || return 1
	if [ "$mv" -le 0 ] 2>/dev/null; then
		# voltage_now в мкВ у tcpm psy; 0 = контракта нет
		return 1
	fi
	[ "$mv" -gt 1000 ] && mv=$((mv / 1000))
	ma=$(cat "$p/current_max" 2>/dev/null) || ma=0
	echo "$mv $ma"
}

# --- status ----------------------------------------------------------------

do_status() {
	wait_ps
	iaicr=$(ps_num input_current_limit)
	ichg=$(ps_num constant_charge_current)
	cv=$(ps_num constant_charge_voltage)
	mivr=$(ps_num input_voltage_limit)
	ieoc=$(ps_num charge_term_current)
	iprec=$(ps_num precharge_current)

	vbus=$(iio_mv vbusdiv2 1) || vbus=0
	vsys=$(iio_mv vsys 2) || vsys=0
	vbat=$(iio_mv vbat 3) || vbat=0
	ibus=$(iio_ma ibus 5) || ibus=0
	ibat=$(iio_ma ibat 6) || ibat=0

	log "== $PS"
	printf '  %-30s %s\n' online "$(ps_read online)"
	printf '  %-30s %s\n' status "$(ps_read status)"
	printf '  %-30s %s\n' charge_type "$(ps_read charge_type)"
	printf '  %-30s %s\n' usb_type "$(ps_read usb_type)"
	printf '  %-30s %s мкА (%s мА; чип 100..3250, шаг 50)\n' \
		input_current_limit "$iaicr" "$((iaicr / 1000))"
	printf '  %-30s %s мкА (%s мА; чип 900..5000, шаг 100)\n' \
		constant_charge_current "$ichg" "$((ichg / 1000))"
	printf '  %-30s %s мкВ (%s мВ)\n' constant_charge_voltage "$cv" "$((cv / 1000))"
	printf '  %-30s %s мкВ\n' input_voltage_limit "$mivr"
	printf '  %-30s %s мкА\n' charge_term_current "$ieoc"
	printf '  %-30s %s мкА\n' precharge_current "$iprec"

	log "== измерения (IIO MT6370 ADC)"
	printf '  %-8s %6s мВ\n' vbus "$vbus"
	printf '  %-8s %6s мВ\n' vsys "$vsys"
	printf '  %-8s %6s мВ\n' vbat "$vbat"
	printf '  %-8s %6s мА\n' ibus "$ibus"
	printf '  %-8s %6s мА\n' ibat "$ibat"
	awk -v v="$vbus" -v i="$ibus" -v bv="$vbat" -v bi="$ibat" 'BEGIN {
		printf "  вход ≈ %.1f Вт, в батарею ≈ %.2f Вт\n", v * i / 1e6, bv * bi / 1e6
	}'

	if c=$(pd_contract); then
		set -- $c
		printf '  PD: контракт %s мВ / %s мА (tcpm-source-psy)\n' "$1" "$2"
	else
		printf '  PD: контракта нет (pd-disable или нет PD-зарядника)\n'
	fi

	if [ -d "$BAT" ]; then
		printf '  battery: capacity=%s%% status=%s (OCV по 0053, ±5%%)\n' \
			"$(cat "$BAT/capacity" 2>/dev/null || echo -)" \
			"$(cat "$BAT/status" 2>/dev/null || echo -)"
	fi

	log "== тепло (максимум $(thermal_max_c) C)"
	thermal_lines
}

# --- запись ----------------------------------------------------------------

num() { # $1=значение $2=имя -> проверяет, что это неотрицательное целое
	case ${1:-} in
	''|*[!0-9]*) die "$2: ожидается целое число, получено '${1:-}'" ;;
	esac
}

write_prop() { # $1=свойство $2=значение мкА/мкВ
	cur=$(ps_read "$1")
	if [ "$cur" = "$2" ]; then
		log "  $1: уже $2 (мкА/мкВ) - не пишу"
		return 0
	fi
	if ! echo "$2" >"$PS/$1" 2>/dev/null; then
		die "запись $PS/$1 = $2 не удалась"
	fi
	log "  $1: $cur -> $2 (мкА/мкВ)"
}

do_set() {
	wait_ps
	iaicr_ua=
	ichg_ua=
	cv_ua=
	force=0
	while [ $# -gt 0 ]; do
		case $1 in
		--iaicr) shift; num "${1:-}" --iaicr; iaicr_ua=$(($1 * 1000)) ;;
		--ichg) shift; num "${1:-}" --ichg; ichg_ua=$(($1 * 1000)) ;;
		--cv) shift; num "${1:-}" --cv; cv_ua=$(($1 * 1000)) ;;
		--force) force=1 ;;
		-h|--help) usage ;;
		*) die "неизвестный аргумент: $1" ;;
		esac
		shift
	done
	[ -n "$iaicr_ua$ichg_ua$cv_ua" ] || usage

	if [ -n "$iaicr_ua" ]; then
		[ "$iaicr_ua" -ge "$IAICR_MIN_UA" ] && [ "$iaicr_ua" -le "$IAICR_MAX_UA" ] ||
			die "IAICR $((iaicr_ua / 1000)) мА вне 100..3250 мА"
		iaicr_ua=$((iaicr_ua / IAICR_STEP_UA * IAICR_STEP_UA))
	fi
	if [ -n "$ichg_ua" ]; then
		[ "$ichg_ua" -ge "$ICHG_MIN_UA" ] && [ "$ichg_ua" -le "$ICHG_MAX_UA" ] ||
			die "ICHG $((ichg_ua / 1000)) мА вне 900..5000 мА"
		if [ "$ichg_ua" -gt "$ICHG_SOFT_MAX_UA" ] && [ "$force" -eq 0 ]; then
			die "ICHG $((ichg_ua / 1000)) мА выше мягкого предела $((ICHG_SOFT_MAX_UA / 1000)) мА: паспорта батареи нет, повторите с --force"
		fi
		ichg_ua=$((ichg_ua / ICHG_STEP_UA * ICHG_STEP_UA))
	fi

	iaicr_old=$(ps_num input_current_limit)
	ibus_old=$(iio_ma ibus 5) || ibus_old=0

	log "== запись"
	[ -n "$ichg_ua" ] && write_prop constant_charge_current "$ichg_ua"
	[ -n "$cv_ua" ] && write_prop constant_charge_voltage "$cv_ua"
	[ -n "$iaicr_ua" ] && write_prop input_current_limit "$iaicr_ua"

	sleep 2

	# Проверка 1: драйвер отдаёт то, что мы просили (иначе - округление/ошибка).
	fail=0
	if [ -n "$iaicr_ua" ]; then
		got=$(ps_read input_current_limit)
		if [ "$got" != "$iaicr_ua" ]; then
			warn "IAICR: просили $iaicr_ua, в sysfs $got"
			fail=1
		fi
	fi
	if [ -n "$ichg_ua" ]; then
		got=$(ps_read constant_charge_current)
		if [ "$got" != "$ichg_ua" ]; then
			warn "ICHG: просили $ichg_ua, в sysfs $got"
			fail=1
		fi
	fi

	# Проверка 2: физика. VBUS просел -> источник не держит, откат IAICR.
	vbus=$(iio_mv vbusdiv2 1) || vbus=0
	ibus=$(iio_ma ibus 5) || ibus=0
	vbat=$(iio_mv vbat 3) || vbat=0
	ibat=$(iio_ma ibat 6) || ibat=0

	log "== факт через 2 с"
	printf '  vbus=%s мВ  ibus=%s мА  vbat=%s мВ  ibat=%s мА  Tmax=%s C\n' \
		"$vbus" "$ibus" "$vbat" "$ibat" "$(thermal_max_c)"
	awk -v v="$vbus" -v i="$ibus" 'BEGIN { printf "  вход ≈ %.2f Вт\n", v * i / 1e6 }'

	if [ -n "$iaicr_ua" ] && [ "$iaicr_ua" -gt 500000 ] && [ "$vbus" -gt 0 ] &&
		[ "$vbus" -lt "$VBUS_MIN_MV" ]; then
		warn "VBUS $vbus мВ < $VBUS_MIN_MV: источник не держит $((iaicr_ua / 1000)) мА (MIVR), откат IAICR -> $iaicr_old"
		echo "$iaicr_old" >"$PS/input_current_limit" 2>/dev/null
		fail=1
	fi

	if [ -n "$iaicr_ua" ] && [ "$iaicr_ua" -gt "$iaicr_old" ] &&
		[ "$ibus" -le $((ibus_old + 30)) ]; then
		warn "ibus не вырос ($ibus_old -> $ibus мА): порт/кабель ограничивает ток (SDP? дешёвый кабель?)"
	fi

	[ "$fail" -eq 0 ] || exit 2
}

do_auto() {
	log "== auto: IAICR $((AUTO_IAICR_UA / 1000)) мА, ICHG $((AUTO_ICHG_UA / 1000)) мА"
	do_set --iaicr $((AUTO_IAICR_UA / 1000)) --ichg $((AUTO_ICHG_UA / 1000))
}

do_hub() {
	log "== hub: IAICR $((HUB_IAICR_UA / 1000)) мА, ICHG $((HUB_ICHG_UA / 1000)) мА"
	do_set --iaicr $((HUB_IAICR_UA / 1000)) --ichg $((HUB_ICHG_UA / 1000))
}

do_wall() {
	log "== wall: IAICR $((WALL_IAICR_UA / 1000)) мА, ICHG $((WALL_ICHG_UA / 1000)) мА"
	do_set --iaicr $((WALL_IAICR_UA / 1000)) --ichg $((WALL_ICHG_UA / 1000))
}

do_keepalive() {
	log "== USB autosuspend off (RNDIS должен жить при простое хоста)"
	n=0
	for c in /sys/bus/usb/devices/*/power/control; do
		[ -w "$c" ] || continue
		echo on >"$c" 2>/dev/null && n=$((n + 1))
	done
	log "  power/control=on: $n устройств"
	if [ -w /sys/module/usbcore/parameters/autosuspend ]; then
		echo -1 >/sys/module/usbcore/parameters/autosuspend 2>/dev/null &&
			log "  usbcore autosuspend=-1"
	fi
}

do_off() {
	log "== off: ICHG 900 мА (значение probe драйвера), IAICR 500 мА (вендор), CV не трогаю"
	do_set --ichg 900 --iaicr 500
}

do_pd() {
	wait_ps
	if ! c=$(pd_contract); then
		die "нет PD-контракта (tcpm-source-psy-*): нужен PD-зарядник и патч 0066 (pd-disable снят). Для обычного порта: t1100-charge.sh auto"
	fi
	set -- $c
	mv=$1
	ma=$2
	iaicr=$ma
	[ "$iaicr" -gt $((PD_IAICR_CAP_UA / 1000)) ] && iaicr=$((PD_IAICR_CAP_UA / 1000))
	[ "$iaicr" -lt 100 ] && die "контракт $mv мВ / $ma мА: ток не определён"

	log "== pd: контракт $mv мВ / $ma мА -> IAICR $iaicr мА, ICHG $((PD_ICHG_CAP_UA / 1000)) мА"
	if [ "$mv" -lt 8000 ]; then
		warn "контракт $mv мВ: это не 9 В, прирост только от тока ($iaicr мА)"
	fi
	do_set --iaicr "$iaicr" --ichg $((PD_ICHG_CAP_UA / 1000))
}

do_redetect() {
	wait_ps
	log "== BC1.2 re-detect: online <- 1"
	echo 1 >"$PS/online" 2>/dev/null || die "запись online=1 не удалась"
	sleep 3
	log "  online=$(ps_read online) status=$(ps_read status) usb_type=$(ps_read usb_type)"
}

do_sample() {
	wait_ps
	vbus=$(iio_mv vbusdiv2 1) || vbus=0
	vbat=$(iio_mv vbat 3) || vbat=0
	ibus=$(iio_ma ibus 5) || ibus=0
	ibat=$(iio_ma ibat 6) || ibat=0
	printf 'online=%s status=%s charge_type=%s iaicr=%s ichg=%s cv=%s vbus=%s ibus=%s vbat=%s ibat=%s tmax=%s\n' \
		"$(ps_read online)" "$(ps_read status)" "$(ps_read charge_type)" \
		"$(ps_num input_current_limit)" "$(ps_num constant_charge_current)" \
		"$(ps_num constant_charge_voltage)" \
		"$vbus" "$ibus" "$vbat" "$ibat" "$(thermal_max_c)"
}

do_watch() {
	wait_ps
	iv=${1:-5}
	num "$iv" интервал
	log "   время    vbus   ibus   vbat   ibat   Tmax  IAICR  ICHG  status"
	while :; do
		printf '%s %5s %5s %5s %5s %5s %6s %5s  %s\n' \
			"$(date +%H:%M:%S)" \
			"$(iio_mv vbusdiv2 1)" "$(iio_ma ibus 5)" \
			"$(iio_mv vbat 3)" "$(iio_ma ibat 6)" \
			"$(thermal_max_c)" \
			"$(( $(ps_num input_current_limit) / 1000 ))" \
			"$(( $(ps_num constant_charge_current) / 1000 ))" \
			"$(ps_read status)"
		sleep "$iv"
	done
}

case ${1:-status} in
status) shift 2>/dev/null || true; do_status ;;
set) shift; do_set "$@" ;;
auto) do_auto ;;
hub) do_hub ;;
wall) do_wall ;;
keepalive) do_keepalive ;;
off) do_off ;;
pd) do_pd ;;
redetect) do_redetect ;;
sample) do_sample ;;
watch) shift; do_watch "${1:-5}" ;;
-h|--help|help) usage ;;
*) die "неизвестная команда '${1}'; см. --help" ;;
esac
