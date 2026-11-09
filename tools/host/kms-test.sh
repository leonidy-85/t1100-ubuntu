#!/bin/sh
# KMS-проверка на планшете (фаза 2): установить modetest и выставить режим.
#
#   tools/host/kms-test.sh            # отчёт + выставить режим DSI-1 (10 с)
#   tools/host/kms-test.sh --dump     # только снять отчёты (ничего не менять)
#   tools/host/kms-test.sh --hold 30  # держать режим 30 с (смотреть на экран)
#
# Требует: build/tools-aarch64/modetest (scripts/build-tools-aarch64.sh),
# ssh-доступ root@10.42.66.66. Ничего не пишет на диск планшета, кроме /root/modetest.
set -eu
HOST=${T1100_HOST:-10.42.66.66}
MODE=set
HOLD=10
while [ $# -gt 0 ]; do
	case "$1" in
		--dump) MODE=dump ;;
		--hold) HOLD=${2:-10}; shift ;;
		-h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "неизвестный аргумент: $1" >&2; exit 2 ;;
	esac
	shift
done

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/build/tools-aarch64/modetest"
[ -x "$BIN" ] || { echo "нет $BIN — собери scripts/build-tools-aarch64.sh" >&2; exit 1; }

SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 root@$HOST"

echo "== ставлю modetest на планшет"
scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$BIN" "root@$HOST:/root/modetest"
$SSH 'chmod +x /root/modetest; /root/modetest --help >/dev/null 2>&1 && echo "modetest запускается"'

echo
echo "== connectors:"
$SSH '/root/modetest -M mediatek -c' > /tmp/opencode/modetest-c.txt 2>&1 || true
sed -n '/Connectors:/,$p' /tmp/opencode/modetest-c.txt | head -12

CID=$($SSH '/root/modetest -M mediatek -c' 2>/dev/null | awk '/DSI-1/ && /connected/ {print $1; exit}')
[ -n "$CID" ] || { echo "не нашёл connector DSI-1 в состоянии connected" >&2; exit 1; }
CMODE=$($SSH '/root/modetest -M mediatek -c' 2>/dev/null | awk '/#0/ {print $2; exit}')
[ -n "$CMODE" ] || CMODE=1600x2176
echo "connector=$CID mode=$CMODE"

if [ "$MODE" = dump ]; then
	echo "== planes:"; $SSH '/root/modetest -M mediatek -p' | head -20
	echo "== encoders:"; $SSH '/root/modetest -M mediatek -e' | head -20
	exit 0
fi

echo
echo "== выставляю режим ($HOLD с) — смотри на экран"
$SSH "timeout $HOLD /root/modetest -M mediatek -s $CID:$CMODE; echo rc=\$?"
echo
echo "== состояние DRM после прогона:"
$SSH 'cat /sys/class/drm/card0-DSI-1/status; cat /sys/class/drm/card0-DSI-1/enabled 2>/dev/null || true'
