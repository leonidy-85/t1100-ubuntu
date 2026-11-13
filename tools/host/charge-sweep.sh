#!/bin/sh
# Ступенчатый замер заряда Fplus T1100 через powered hub (по SSH/RNDIS).
#
#   tools/host/charge-sweep.sh [host] [--steps "100 250 500 750 900 1200 1500"]
#                              [--hold 60] [--restore auto|hub|off|none]
#
# Что делает: на каждой ступени пишет IAICR через t1100-charge.sh на планшете,
# выдерживает --hold секунд, снимает одну строку `sample` (online/status/
# charge_type/iaicr/ichg/cv/vbus/ibus/vbat/ibat/tmax) и проверяет, жив ли
# RNDIS/SSH (ping + ssh). Если SSH отвалился — ступень помечается LOST, дальше
# не идём (иначе нечем откатить лимиты), в конце печатается сводка.
#
# Результат: таблица в stdout + TSV в build/charge-sweep-<host>-<дата>.tsv.
# build/ в .gitignore: цифры переносятся в docs/STATUS.md руками.
#
# Требования: ssh-ключ root@host работает (tools/host/usb-net.sh), на планшете
# разложен rootfs-overlay (t1100-charge.sh). Устройство — эксклюзивный ресурс:
# запускать только когда lead/владелец подтвердил, что оно свободно.
set -u

HOST=10.42.66.66
STEPS="100 250 500 750 900 1200 1500"
HOLD=60
RESTORE=auto

while [ $# -gt 0 ]; do
	case $1 in
	--steps) shift; STEPS=${1:-} ;;
	--hold) shift; HOLD=${1:-60} ;;
	--restore) shift; RESTORE=${1:-auto} ;;
	-h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) HOST=$1 ;;
	esac
	shift
done

SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 root@$HOST"
REPO=$(cd "$(dirname "$0")/../.." && pwd)
OUT="$REPO/build/charge-sweep-$HOST-$(date +%Y%m%d-%H%M%S).tsv"
CHG=/usr/local/bin/t1100-charge.sh

log() { printf '%s\n' "$*"; }
warn() { printf 'charge-sweep: %s\n' "$*" >&2; }

remote() { $SSH "$CHG $1" 2>&1; }

link_alive() {
	# RNDIS жив, если отвечает ping и открывается SSH. Один короткий заход.
	ping -c1 -W2 "$HOST" >/dev/null 2>&1 || return 1
	$SSH true >/dev/null 2>&1
}

[ -d "$REPO/build" ] || mkdir -p "$REPO/build"

log "== цель $HOST, ступени: $STEPS мА, выдержка ${HOLD}s, restore=$RESTORE"
log "== файл: $OUT"

if ! link_alive; then
	warn "нет SSH до $HOST — плата недоступна, замер не начат"
	exit 1
fi

sample() { $SSH "$CHG sample" 2>/dev/null; }

# Что было до замера, чтобы вернуть в конце.
BEFORE=$(sample)
log "== до замера: $BEFORE"
if ! printf '%s\n' "$BEFORE" | grep -q 'vbus='; then
	warn "не удалось снять sample, проверьте $CHG на плате"
	exit 1
fi

printf 'iaicr_req\tiaicr_get\tichg\tvbus_mv\tibus_ma\tvbat_mv\tibat_ma\ttmax_c\tstatus\trndis\n' >"$OUT"

MAX_OK=0
for ma in $STEPS; do
	log ""
	log "== ступень IAICR=$ma мА (${HOLD}s)"
	r=$(remote "set --iaicr $ma")
	rc=$?
	printf '%s\n' "$r" | sed 's/^/   /'
	case $rc in
	0) ;;
	2) warn "ступень $ma: сработала защита (VBUS просел или лимит не встал)" ;;
	*) warn "ступень $ma: set вернул $rc" ;;
	esac

	sleep "$HOLD"

	if link_alive; then
		alive=YES
	else
		alive=LOST
	fi
	s=$(sample)
	if [ -z "$s" ]; then
		warn "ступень $ma: SSH не отвечает, RNDIS потерян — стоп"
		printf '%s\t\t\t\t\t\t\t\tLOST\tLOST\n' "$ma" >>"$OUT"
		break
	fi

	get() { printf '%s\n' "$s" | tr ' ' '\n' | sed -n "s/^$1=//p"; }
	ia=$(get iaicr)
	ic=$(get ichg)
	vb=$(get vbus)
	ib=$(get ibus)
	bt=$(get vbat)
	bc=$(get ibat)
	tm=$(get tmax)
	st=$(get status)
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$ma" "$ia" "$ic" "$vb" "$ib" "$bt" "$bc" "$tm" "$st" "$alive" >>"$OUT"
	printf '   %-10s iaicr=%-8s vbus=%-5s ibus=%-5s vbat=%-5s ibat=%-5s T=%-5s %-10s RNDIS=%s\n' \
		"$ma" "$ia" "$vb" "$ib" "$bt" "$bc" "$tm" "$st" "$alive"

	if [ "$alive" = LOST ]; then
		warn "RNDIS/SSH потерян на $ma мА — останавливаюсь, лимиты не трогаю по SSH"
		break
	fi
	if [ "$rc" = 0 ] && [ "${vb:-0}" -ge 4600 ] 2>/dev/null; then
		MAX_OK=$ma
	fi
done

if [ "$RESTORE" != none ]; then
	log ""
	log "== восстановление профиля $RESTORE"
	remote "$RESTORE" | sed 's/^/   /'
fi

log ""
log "== сводка (TSV: $OUT)"
awk -F'\t' 'NR > 1 { printf "  %6s мА  ibus=%-5s vbat=%-5s ibat=%-5s T=%-5s RNDIS=%s\n", $1, $5, $6, $7, $8, $10 }' "$OUT"
log "  максимум с VBUS >= 4.6 В и живым RNDIS: ${MAX_OK} мА"
log "  (впишите найденное в /etc/default/t1100-charge: HUB_IAICR_UA; если оно"
log "   выше 900000 — проверьте нагрев за 10 минут и только потом фиксируйте)"
if [ "$MAX_OK" -gt 900 ]; then
	warn "внимание: ${MAX_OK} мА выше проверенных 900 мА — профиль hub по умолчанию не меняйте без прогона на нагрев"
fi
