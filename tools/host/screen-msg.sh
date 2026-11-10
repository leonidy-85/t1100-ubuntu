#!/bin/sh
# Вывести сообщение на экран планшета (tty1/консоль) — чтобы было видно,
# что от владельца ждут действий (например, касаний).
#
#   tools/host/screen-msg.sh "Текст"
#   tools/host/screen-msg.sh --touch          # «прикасайтесь к экрану»
#   tools/host/screen-msg.sh --touch --read N  # сообщение + чтение event1 N секунд
#   tools/host/screen-msg.sh --clear
#
# Почему tty1: панель отдана fbcon на tty1 (VT), запись в /dev/tty1 видна на
# экране. Если на панели работает композитор (weston/kmscube), он держит DRM
# master — сообщение не покажется; для этого есть --stop-drm.
set -eu
HOST=${T1100_HOST:-10.42.66.66}
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 root@$HOST"
REPO=$(cd "$(dirname "$0")/../.." && pwd)

MSG=""
TOUCH=0
CLEAR=0
READ=0
STOP_DRM=0
while [ $# -gt 0 ]; do
	case "$1" in
		--touch) TOUCH=1 ;;
		--clear) CLEAR=1 ;;
		--stop-drm) STOP_DRM=1 ;;
		--read) READ=${2:-10}; shift ;;
		-h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) MSG="$*"; break ;;
	esac
	shift
done

if [ "$STOP_DRM" = 1 ]; then
	echo "== останавливаю композитор (освобождаю DRM master)"
	[ -x "$REPO/tools/host/weston-test.sh" ] && "$REPO/tools/host/weston-test.sh" stop >/dev/null 2>&1 || true
	$SSH 'pkill -x kmscube 2>/dev/null; pkill -x glmark2-es2-dr 2>/dev/null; sleep 1' >/dev/null 2>&1 || true
fi

# ВАЖНО: в консольном шрифте планшета нет кириллицы (rootfs минимальный, нет
# kbd/setfont) — кириллица рисуется квадратами. Пишем латиницей.
if [ "$TOUCH" = 1 ] && [ -z "$MSG" ]; then
	MSG="TOUCH THE SCREEN NOW
  several times, in different places"
fi
[ -n "$MSG" ] || MSG="t1100"

if [ "$CLEAR" = 1 ]; then
	$SSH 'printf "\033[2J\033[H" > /dev/tty1' || true
	echo "== экран очищен"
	exit 0
fi

# Печатаем рамку, чтобы сообщение было видно на чёрном фоне.
$SSH "sh -s" <<EOF
MSG='$MSG'
{
	printf '\033[2J\033[H'
	printf '\n\n\n'
	printf '  ============================================\n'
	printf '%s\n' "\$MSG" | while IFS= read -r l; do
		printf '   %s\n' "\$l"
	done
	printf '  ============================================\n'
} > /dev/tty1
# дублируем в printk — попадёт и в dmesg, если fbcon перехватит
printf 't1100: %s\n' "\$MSG" > /dev/kmsg
echo written
EOF

echo "== сообщение выведено на панель"

if [ "$READ" -gt 0 ]; then
	echo "== читаю /dev/input/event1 ${READ} с (касайтесь)"
	$SSH "timeout $READ cat /dev/input/event1 | od -An -tu4 > /tmp/screen-msg-read.log 2>&1 || true
		echo bytes=\$(wc -c < /tmp/screen-msg-read.log)"
fi
