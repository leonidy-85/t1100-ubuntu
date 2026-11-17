#!/bin/sh
# Запуск GUI-программы в уже поднятой сессии KDE/Wayland на планшете.
#
#   tools/host/session-run.sh librewolf https://www.youtube.com/
#   tools/host/session-run.sh --shot /tmp/openyoutube.png spectacle -b -n -o /tmp/s.png
#
# Зачем: ssh-сессия не наследует окружение графической сессии, и GUI-программа
# падает с «no DISPLAY environment variable specified» (Firefox/LibreWolf на
# Wayland смотрит именно WAYLAND_DISPLAY, а не только XDG_RUNTIME_DIR).
# Скрипт вытаскивает XDG_RUNTIME_DIR/WAYLAND_DISPLAY/DBUS_SESSION_BUS_ADDRESS
# из /proc/<kwin_wayland>/environ и запускает команду оттуда.
#
# --shot FILE  после команды снять скриншот (spectacle) и забрать его в FILE.
#
# Хост — $T1100_HOST (по умолчанию 10.42.66.66), доступ root по ключу.
set -eu
HOST=${T1100_HOST:-10.42.66.66}
SHOT=
if [ "${1:-}" = "--shot" ]; then
	SHOT=${2:?--shot требует имя файла}
	shift 2
fi
[ $# -gt 0 ] || { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

SSHOPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o BatchMode=yes"

# Окружение сессии -> /root/.t1100-session-env на планшете.
ssh $SSHOPT "root@$HOST" '
	pid=$(pgrep -x kwin_wayland | head -1)
	[ -n "$pid" ] || { echo "нет kwin_wayland: сессия KDE не поднята" >&2; exit 1; }
	tr "\0" "\n" < /proc/$pid/environ \
		| grep -E "^(XDG_RUNTIME_DIR|WAYLAND_DISPLAY|DISPLAY|DBUS_SESSION_BUS_ADDRESS)=" \
		> /root/.t1100-session-env
	# У самого kwin_wayland WAYLAND_DISPLAY нет: сокет создаёт он. Берём имя
	# сокета из его каталога (обычно wayland-0).
	if ! grep -q "^WAYLAND_DISPLAY=" /root/.t1100-session-env; then
		rt=$(sed -n "s/^XDG_RUNTIME_DIR=//p" /root/.t1100-session-env)
		wl=$(ls "$rt" 2>/dev/null | grep -E "^wayland-[0-9]+$" | head -1)
		[ -n "$wl" ] && echo "WAYLAND_DISPLAY=$wl" >> /root/.t1100-session-env
	fi
	cat /root/.t1100-session-env
'

# Команду собираем в одну строку с экранированием: аргументы уходят как есть.
CMD=
for a in "$@"; do
	CMD="$CMD $(printf "%s" "$a" | sed "s/'/'\\\\''/g; s/^/'/; s/\$/'/")"
done
ssh $SSHOPT "root@$HOST" "set -a; . /root/.t1100-session-env; set +a; exec$CMD"

if [ -n "$SHOT" ]; then
	ssh $SSHOPT "root@$HOST" "set -a; . /root/.t1100-session-env; set +a; spectacle -b -n -o /tmp/t1100-shot.png" >/dev/null 2>&1
	scp -q $SSHOPT "root@$HOST:/tmp/t1100-shot.png" "$SHOT"
	echo "скриншот: $SHOT"
fi
