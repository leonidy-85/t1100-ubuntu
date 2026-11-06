#!/bin/sh
# Установка страховки от разряда (t1100-power-guard) на планшет.
#
#   tools/host/install-power-guard.sh [host]            # на загруженную Ubuntu по SSH
#   tools/host/install-power-guard.sh --rootfs /mnt/root # в примонтированный rootfs
#
# Юнит: /usr/local/sbin/t1100-power-guard + /etc/default/t1100-power-guard +
# t1100-power-guard.{service,timer}. Настройки - /etc/default/t1100-power-guard.
set -eu

cd "$(dirname "$0")/../.."
OVERLAY=rootfs-overlay

usage() {
	sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
	exit 1
}

[ $# -ge 1 ] || set -- 10.42.66.66   # без аргументов - планшет по умолчанию

if [ "$1" = "--rootfs" ]; then
	[ $# -ge 2 ] || usage
	DST=$2
	[ -d "$DST" ] || { echo "нет каталога $DST" >&2; exit 1; }
	echo "== копирую $OVERLAY -> $DST"
	(cd "$OVERLAY" && tar -cf - .) | tar -C "$DST" -xf -
	chmod 755 "$DST/usr/local/sbin/t1100-power-guard"
	ln -sf /etc/systemd/system/t1100-power-guard.timer \
		"$DST/etc/systemd/system/timers.target.wants/t1100-power-guard.timer" 2>/dev/null ||
		{ mkdir -p "$DST/etc/systemd/system/timers.target.wants" && ln -sf \
			/etc/systemd/system/t1100-power-guard.timer \
			"$DST/etc/systemd/system/timers.target.wants/t1100-power-guard.timer"; }
	echo "готово: при загрузке таймер включится сам"
	exit 0
fi

HOST=$1
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 root@$HOST"

echo "== копирую $OVERLAY -> root@$HOST:/"
(cd "$OVERLAY" && tar -cf - .) | $SSH 'tar -C / -xf -' || {
	echo "копирование не удалось (планшет не отвечает?)" >&2
	exit 1
}

$SSH 'sh -s' <<'EOF'
set -e
chmod 755 /usr/local/sbin/t1100-power-guard
systemctl daemon-reload
systemctl enable --now t1100-power-guard.timer
systemctl start t1100-power-guard.service
echo "== status:"
systemctl is-enabled t1100-power-guard.timer
systemctl list-timers --no-pager t1100-power-guard.timer
echo "== последний запуск:"
journalctl -t t1100-power-guard --no-pager -n 20 2>/dev/null ||
	systemctl status --no-pager -n 20 t1100-power-guard.service
EOF
