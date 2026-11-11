#!/bin/sh
# Wi-Fi M3, шаг «деплой модулей»: положить вендорский connectivity-стек на
# планшет и подготовить автозагрузку — НИЧЕГО не загружая и не прошивая.
#
#   tools/host/wifi-deploy.sh                 # только план (по умолчанию)
#   tools/host/wifi-deploy.sh --apply         # .ko + depmod + unit (без запуска)
#   tools/host/wifi-deploy.sh --apply --enable
#                                             # ещё и systemctl enable (не start)
#   tools/host/wifi-deploy.sh --load wmt      # M3: modprobe wmt_drv + dmesg
#   tools/host/wifi-deploy.sh --load all      # wmt_drv, затем wlan_drv_gen3
#   tools/host/wifi-deploy.sh --status        # что лежит/загружено на планшете
#
# Что кладётся (все из одних и тех же артефактов, см. отчёт в
# docs/wifi-port-log.md «M3»):
#   /lib/modules/<release>/updates/wifi/wmt_drv.ko         build/wifi/common/
#   /lib/modules/<release>/updates/wifi/wlan_drv_gen3.ko   build/wifi/wlan/
#   /lib/modules/<release>/updates/wifi/{cfg80211,mac80211,rfkill}.ko
#                                                          build/remote/modules/
#   /etc/systemd/system/t1100-wifi.service                 rootfs-overlay/
#
# Почему проверяется vermagic: ядро и модули должны быть из одной сборки,
# иначе insmod откажет («version magic ... should be ...»). Скрипт сравнивает
# `uname -r` на планшете с vermagic самих .ko и отказывается работать при
# расхождении (обойти: --force, но тогда модули всё равно не загрузятся).
#
# Ничего не прошивает: boot_a меняет только tools/host/flash-ssh.sh.
set -eu

HOST=${T1100_HOST:-10.42.66.66}
MODE=plan
DO_ENABLE=0
FORCE=0
LOAD=

while [ $# -gt 0 ]; do
	case "$1" in
		--apply)  MODE=apply ;;
		--plan|--dry-run) MODE=plan ;;
		--enable) DO_ENABLE=1 ;;
		--force)  FORCE=1 ;;
		--load)   MODE=load; LOAD=${2:-wmt}; shift ;;
		--status) MODE=status ;;
		-h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "неизвестный аргумент: $1" >&2; exit 2 ;;
	esac
	shift
done

REPO=$(cd "$(dirname "$0")/../.." && pwd)
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8"
SSH="ssh $SSH_OPTS root@$HOST"
SCP="scp -q $SSH_OPTS"

UNIT="$REPO/rootfs-overlay/etc/systemd/system/t1100-wifi.service"
KO_LIST="
$REPO/build/wifi/common/wmt_drv.ko
$REPO/build/wifi/wlan/wlan_drv_gen3.ko
$REPO/build/remote/modules/cfg80211.ko
$REPO/build/remote/modules/mac80211.ko
$REPO/build/remote/modules/rfkill.ko
"

# --- локальные предпосылки -------------------------------------------------
missing=0
for f in $KO_LIST $UNIT; do
	[ -f "$f" ] || { echo "нет файла: $f" >&2; missing=1; }
done
[ "$missing" -eq 0 ] || {
	echo "Собери: scripts/build-wifi-remote.sh (модули вендора) и" >&2
	echo "        scripts/build-kernel-remote.sh --modules EXTRA_FRAGMENTS=configs/t1100-wifi.fragment" >&2
	exit 1
}

# --- release из самих модулей (не из дерева) -------------------------------
RELEASE=$(strings "$REPO/build/wifi/common/wmt_drv.ko" \
	| sed -n 's/^vermagic=\([^ ]*\) .*/\1/p' | head -n1)
[ -n "$RELEASE" ] || { echo "не нашёл vermagic в wmt_drv.ko" >&2; exit 1; }
MODDIR="/lib/modules/$RELEASE/updates/wifi"

echo "== t1100 wifi deploy =="
echo "host      : root@$HOST"
echo "release   : $RELEASE (vermagic из wmt_drv.ko)"
echo "moddir    : $MODDIR"
for f in $KO_LIST; do
	printf '  %-58s %10s  %s\n' "$(sha256sum "$f" | cut -c1-16)…" \
		"$(stat -c%s "$f")" "$(basename "$f")"
done

if [ "$MODE" = plan ]; then
	cat <<EOF

План (ничего не выполнено):
  1. ssh root@$HOST mkdir -p $MODDIR
  2. scp wmt_drv.ko wlan_drv_gen3.ko cfg80211.ko mac80211.ko rfkill.ko -> $MODDIR
  3. ssh root@$HOST depmod -a $RELEASE
  4. scp t1100-wifi.service -> /etc/systemd/system/ && systemctl daemon-reload
  5. (--enable) systemctl enable t1100-wifi.service   # без start
Модули НЕ загружаются: первый insmod делает человек по плану M3
(docs/wifi-port-log.md, раздел «M3 подготовка»).
EOF
	exit 0
fi

# --- общая проверка, что планшет на нужном ядре ----------------------------
DEV_RELEASE=$($SSH 'uname -r')
echo "ядро на планшете: $DEV_RELEASE"
if [ "$DEV_RELEASE" != "$RELEASE" ]; then
	echo "ВНИМАНИЕ: vermagic модулей ($RELEASE) != uname -r ($DEV_RELEASE)." >&2
	echo "          insmod откажет. Сначала загрузить boot-образ этой сборки." >&2
	[ "$FORCE" -eq 1 ] || exit 3
fi

case "$MODE" in
status)
	echo
	echo "== на планшете =="
	$SSH "ls -l $MODDIR 2>/dev/null || echo 'нет $MODDIR'; \
	      echo; lsmod | grep -E '^(wmt_drv|wlan_drv_gen3|cfg80211|mac80211|rfkill) ' || echo 'модули не загружены'; \
	      echo; systemctl is-enabled t1100-wifi.service 2>&1; systemctl is-active t1100-wifi.service 2>&1"
	;;
apply)
	echo
	echo "== раскладываю .ko =="
	$SSH "mkdir -p $MODDIR"
	for f in $KO_LIST; do
		$SCP "$f" "root@$HOST:$MODDIR/" && echo "  -> $(basename "$f")"
	done
	echo
	echo "== depmod =="
	$SSH "depmod -a $RELEASE && echo depmod ok; \
	      grep -c '' /lib/modules/$RELEASE/modules.dep 2>/dev/null | sed 's/^/modules.dep строк: /'; \
	      grep -E '^(wmt_drv|wlan_drv_gen3|cfg80211):' /lib/modules/$RELEASE/modules.dep || true"
	echo
	echo "== unit =="
	$SCP "$UNIT" "root@$HOST:/etc/systemd/system/t1100-wifi.service"
	$SSH "systemctl daemon-reload && echo daemon-reload ok"
	if [ "$DO_ENABLE" -eq 1 ]; then
		$SSH "systemctl enable t1100-wifi.service" && echo "unit включён (не запущен)"
	fi
	echo
	echo "Готово: модули лежат, ничего не загружено и не запущено."
	echo "Следующий шаг (M3, на устройстве):"
	echo "  tools/host/wifi-deploy.sh --load wmt   # modprobe wmt_drv + dmesg"
	;;
load)
	echo
	case "$LOAD" in
		wmt) $SSH "/sbin/modprobe -v wmt_drv; sleep 2; dmesg | grep -iE 'wmt|consys|EMI' | tail -n 60" ;;
		wlan) $SSH "/sbin/modprobe -v wlan_drv_gen3; sleep 2; dmesg | grep -iE 'wmt|wlan|cfg80211|HIF' | tail -n 60" ;;
		all) $SSH "/sbin/modprobe -v wmt_drv; sleep 3; dmesg | grep -iE 'wmt|consys|EMI' | tail -n 60; \
			   /sbin/modprobe -v wlan_drv_gen3; sleep 3; dmesg | grep -iE 'wlan|HIF|cfg80211' | tail -n 60; \
			   ip -br link | grep -E 'wlan|eth' || true" ;;
		*) echo "неизвестный набор модулей: $LOAD (wmt|wlan|all)" >&2; exit 2 ;;
	esac
	;;
esac
