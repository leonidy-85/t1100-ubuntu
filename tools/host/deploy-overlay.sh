#!/bin/sh
# Разложить rootfs-overlay/ на планшет — с правами root, не владельца репозитория.
#
#   tools/host/deploy-overlay.sh [host]
#
# Почему отдельный скрипт: `tar -C rootfs-overlay -cf - . | ssh target 'tar -C / -xf -'`
# сохраняет uid/gid из репозитория (1000), и после распаковки /etc, /usr, /root
# принадлежат uid 1000. sshd с StrictModes=yes после этого **отказывает в ключе**
# («bad ownership or modes for directory /root») — проверено 12.11, доступ
# восстанавливали из recovery через chown.
#
# Поэтому: tar с --owner=0 --group=0 --numeric-owner и явный chown после распаковки.
set -eu
HOST=${1:-10.42.66.66}
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 root@$HOST"
REPO=$(cd "$(dirname "$0")/../.." && pwd)

[ -d "$REPO/rootfs-overlay" ] || { echo "нет $REPO/rootfs-overlay" >&2; exit 1; }

echo "== раскладываю rootfs-overlay -> $HOST:/ (uid/gid 0)"
# --keep-directory-symlink обязателен: Ubuntu 26.04 живёт в merged-usr, где
# /lib -> usr/lib. Без него tar, встретив в архиве ./lib/..., сносит symlink и
# создаёт настоящий каталог /lib: динамический линкер (/lib/ld-linux-*.so.1)
# исчезает, и все новые процессы падают с "No such file or directory".
# Так 13.11 лёг sshd: "fatal: rexec of /usr/lib/openssh/sshd-session failed".
tar -C "$REPO/rootfs-overlay" --owner=0 --group=0 --numeric-owner -cf - . |
	$SSH 'tar -C / --keep-directory-symlink --numeric-owner --no-same-owner -xf - && echo OVERLAY_OK'

echo "== выставляю права и чиню владельцев"
$SSH 'set -e
	# Страховка: merged-usr symlinks должны остаться symlink-ами.
	for l in lib lib64 bin sbin; do
		[ -e "/$l" ] || continue
		if [ ! -L "/$l" ]; then
			echo "OVERLAY_BROKEN: /$l не symlink (merged-usr сломан)" >&2
			exit 1
		fi
	done
	chown -R root:root /root /etc/pam.d /etc/pipewire /etc/wireplumber /etc/systemd/user \
		/usr/share/alsa/ucm2 /usr/local/bin 2>/dev/null || true
	chmod 755 /usr/local/bin/t1100-audio-mixer.sh /usr/local/bin/t1100-charge.sh \
		/usr/local/sbin/t1100-wifi-func-on /usr/local/sbin/t1100-bt-up 2>/dev/null || true
	systemctl daemon-reload
	udevadm control --reload-rules 2>/dev/null || true
	systemctl enable --now t1100-audio-mixer.service 2>/dev/null || true
	systemctl enable --now t1100-charge.service 2>/dev/null || true
	systemctl enable --now t1100-usb-keepalive.service 2>/dev/null || true
	echo "== проверка доступа:"
	ls -ld /root /root/.ssh; ls -l /root/.ssh/authorized_keys'

echo "== ssh проверка"
$SSH 'echo SSH_OK; for u in t1100-audio-mixer t1100-charge t1100-usb-keepalive; do
	printf "%s=%s\n" "$u" "$(systemctl is-active $u.service)"; done;
	P=/sys/class/power_supply/mt6370-charger;
	printf "IAICR=%s ICHG=%s online=%s\n" "$(cat $P/input_current_limit)" "$(cat $P/constant_charge_current)" "$(cat $P/online)"'
