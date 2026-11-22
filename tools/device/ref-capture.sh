#!/system/bin/sh
# Снять эталонный обмен mnld <-> чип через pty-релей (Android, root).
# Использование: adb push gps-relay-pty ref-capture.sh /data/local/tmp/
#                adb shell su -c 'sh /data/local/tmp/ref-capture.sh [seconds]'
# Требуется SELinux-разрешение (один раз на бут):
#   magiskpolicy --live "allow mnld devpts chr_file { open read write getattr map lock }"
set -x

BASE=/data/local/tmp/ref
BIN=/data/local/tmp/gps-relay-pty
SECS=${1:-45}

setprop ctl.stop mnld
sleep 2

chmod 755 "$BIN"
rm -f "$BASE.mnld.bin" "$BASE.chip.bin"
nohup "$BIN" "$BASE" $((SECS + 20)) >/data/local/tmp/ref.relay.log 2>&1 &
RELAY=$!
sleep 1
ls -l /dev/stpgps /dev/stpgps.real

setprop ctl.start mnld
sleep "$SECS"

setprop ctl.stop mnld
sleep 1
kill -TERM "$RELAY"
sleep 2

# Релей обычно восстанавливает узел сам; страховка на случай аварийного выхода.
if [ -L /dev/stpgps ] && [ -e /dev/stpgps.real ]; then
	rm -f /dev/stpgps
	mv /dev/stpgps.real /dev/stpgps
fi
chown gps:gps /dev/stpgps 2>/dev/null
chmod 660 /dev/stpgps 2>/dev/null

setprop ctl.start mnld
sleep 2

ls -lZ /dev/stpgps "$BASE.mnld.bin" "$BASE.chip.bin"
cat /data/local/tmp/ref.relay.log
