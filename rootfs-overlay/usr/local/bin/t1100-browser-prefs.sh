#!/bin/sh
# Разложить «прошивочные» настройки браузера в профили LibreWolf.
#
# Источник — /etc/librewolf/user.js (в репозитории:
# rootfs-overlay/etc/librewolf/user.js). Скрипт кладёт его как user.js в
# каждый существующий профиль root и обычных пользователей. Идемпотентно:
# если профиля ещё нет (браузер ни разу не запускали), ничего не делает —
# тогда юнит достаточно запустить после первого старта браузера:
#   systemctl start t1100-browser-prefs.service
set -eu
SRC=/etc/librewolf/user.js
[ -f "$SRC" ] || exit 0

n=0
for home in /root /home/*; do
	dir="$home/.config/librewolf/librewolf"
	[ -d "$dir" ] || continue
	for profile in "$dir"/*/; do
		name=$(basename "$profile")
		# не профили: служебные каталоги LibreWolf
		case "$name" in
		"Profile Groups"|firefox-mpris) continue ;;
		esac
		# профиль опознаём по prefs.js или times.json
		[ -f "$profile/prefs.js" ] || [ -f "$profile/times.json" ] || continue
		install -m 0644 -o "$(stat -c %u "$profile")" -g "$(stat -c %g "$profile")" \
			"$SRC" "$profile/user.js"
		n=$((n + 1))
	done
done

[ "$n" -gt 0 ] && echo "t1100-browser-prefs: user.js разложен в $n профилей"
exit 0
