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
tar -C "$REPO/rootfs-overlay" --owner=0 --group=0 --numeric-owner -cf - . |
	$SSH 'tar -C / --numeric-owner --no-same-owner -xf - && echo OVERLAY_OK'

echo "== выставляю права и чиню владельцев"
$SSH 'set -e
	chown -R root:root /root /etc/pam.d /etc/pipewire /etc/wireplumber /etc/systemd/user \
		/usr/share/alsa/ucm2 /usr/local/bin 2>/dev/null || true
	chmod 755 /usr/local/bin/t1100-audio-mixer.sh 2>/dev/null || true
	systemctl daemon-reload
	systemctl enable --now t1100-audio-mixer.service 2>/dev/null || true
	echo "== проверка доступа:"
	ls -ld /root /root/.ssh; ls -l /root/.ssh/authorized_keys'

echo "== ssh проверка"
$SSH 'echo SSH_OK; systemctl is-active t1100-audio-mixer.service'
