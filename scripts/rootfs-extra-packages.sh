#!/bin/sh
# Установка пакетов, которые ставились на планшет вручную, в rootfs Ubuntu.
#
# Запускать внутри собранного rootfs (chroot) или на самом устройстве:
#
#   scripts/rootfs-extra-packages.sh                # всё из configs/rootfs-packages.txt
#   LOCAL_DEB_DIR=/root/Downloads/arm scripts/rootfs-extra-packages.sh
#
# Для локальных .deb ai.storyteller (~364 МБ) их нужно положить в
# $LOCAL_DEB_DIR (по умолчанию /root/Downloads/arm); в git они не входят.
# На build-хосте копия лежит в /home/l/t1100-extra/debs — при сборке образа
# вызывать: LOCAL_DEB_DIR=/home/l/t1100-extra/debs /extra-packages.sh
# Без них скрипт предупредит и продолжит с остальными пакетами.
set -e

LIST=${LIST:-$(dirname "$0")/../configs/rootfs-packages.txt}
LOCAL_DEB_DIR=${LOCAL_DEB_DIR:-/root/Downloads/arm}

APT="apt-get install -y --no-install-recommends"

if [ ! -f "$LIST" ]; then
	echo "нет списка пакетов: $LIST" >&2
	exit 1
fi

apt-get update

while IFS= read -r line; do
	# комментарии и пустые строки
	case "$line" in
	''|\#*) continue ;;
	esac

	case "$line" in
	local:ai.storyteller)
		if ls "$LOCAL_DEB_DIR"/*.deb >/dev/null 2>&1; then
			echo "== локальные .deb: $LOCAL_DEB_DIR"
			( cd "$LOCAL_DEB_DIR" && apt-get install -y ./*.deb )
		else
			echo "!! пропущено: в $LOCAL_DEB_DIR нет .deb приложений ai.storyteller" >&2
		fi
		;;
	*)
		echo "== $line"
		# shellcheck disable=SC2086
		$APT $line
		;;
	esac
done < "$LIST"

echo "готово: пакеты из $LIST установлены"
