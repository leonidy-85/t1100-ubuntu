#!/usr/bin/env bash
# Залить Weston (DRM/KMS + GL) на планшет и проверить композитор.
# Ничего не прошивает и не меняет системные пути: всё в /usr/local (+ /run/user/0,
# /tmp). Зависимости Mesa (EGL/GLESv2/GBM/gallium) берутся из /usr/local от фазы 3.
#
#   tools/host/weston-test.sh verify        # офлайн-проверка сборки (file/readelf/sha256)
#   tools/host/weston-test.sh deploy        # разложить bundle в /usr/local
#   tools/host/weston-test.sh check         # готовность: Mesa, /dev/dri, xkb, /run/user/0
#   tools/host/weston-test.sh smoke [сек]   # прогон N сек (по умолчанию 10) + weston-simple-egl
#   tools/host/weston-test.sh run           # интерактивный запуск для владельца (фон + лог)
#   tools/host/weston-test.sh stop          # остановить запущенный weston
#   tools/host/weston-test.sh log [строк]   # хвост лога weston
#   tools/host/weston-test.sh undeploy      # убрать всё залитое (Mesa не трогает)
#
# Раскладка (bundle = будущий /usr/local):
#   /usr/local/bin/{weston,weston-simple-egl,weston-simple-shm,weston-env.sh}
#   /usr/local/lib/aarch64-linux-gnu/libweston-13.so.0.0.0
#   /usr/local/lib/aarch64-linux-gnu/libweston-13/{drm-backend.so,gl-renderer.so}
#   /usr/local/lib/aarch64-linux-gnu/weston/{kiosk-shell.so,libexec_weston.so.0*}
#   /usr/local/lib/aarch64-linux-gnu/{libwayland-*,libxkbcommon.so.0,libinput.so.10,
#        libevdev.so.2,libmtdev.so.1,libwacom.so.9,libseat.so.1,libdisplay-info.so.1,
#        libpixman-1.so.0,libglib-2.0.so.0,libgobject-2.0.so.0,libgudev-1.0.so.0,
#        libpcre2-8.so.0}
#   /usr/local/share/{weston,X11/xkb,libweston-13,wayland-sessions}
#
# Почему без logind: Weston 13 всегда открывает seat через libseat, а в libseat
# есть встроенный backend "builtin" (прямой доступ к /dev, работает от root).
# Поэтому LIBSEAT_BACKEND=builtin + запуск от root; ни systemd-logind, ни seatd,
# ни VT не нужны (опции --tty в Weston 13 нет вообще).
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
LOCAL=${LOCAL:-$ROOT/build/weston-aarch64}
HOST=${T1100_HOST:-10.42.66.66}
USR=${T1100_USER:-root}
SSH=(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 "$USR@$HOST")
LIB=/usr/local/lib/aarch64-linux-gnu
RUNENV="env LD_LIBRARY_PATH=$LIB GBM_BACKENDS_PATH=$LIB/gbm XDG_RUNTIME_DIR=/run/user/0 XKB_CONFIG_ROOT=/usr/local/share/X11/xkb LIBSEAT_BACKEND=builtin XDG_SEAT=seat0"
WESTON_OPTS="--backend=drm --drm-device=card1 --shell=kiosk --idle-time=0"

usage() { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

case "${1:-}" in
verify)
	[ -d "$LOCAL" ] || { echo "нет $LOCAL — сначала scripts/build-weston-aarch64.sh" >&2; exit 1; }
	echo "== ELF =="
	find "$LOCAL" -type f \( -path '*/bin/*' -o -name '*.so*' \) -print0 |
		xargs -0 file | sed 's/, BuildID.*//' | sed "s|$LOCAL/||"
	echo "== NEEDED (weston) =="
	LC_ALL=C aarch64-linux-gnu-readelf -d "$LOCAL/bin/weston" |
		awk '/NEEDED|RUNPATH/{gsub(/[\[\]]/,""); print "  " $5}'
	echo "== размеры =="
	du -sh "$LOCAL" "$LOCAL/share/X11/xkb"
	echo "== sha256 =="
	(cd "$LOCAL" && find . -type f \( -path './bin/*' -o -name '*.so*' \) \
		-exec sha256sum {} + | sort -k2)
	;;
deploy)
	[ -f "$LOCAL/bin/weston" ] || { echo "нет $LOCAL/bin/weston" >&2; exit 1; }
	tar czf - -C "$LOCAL" . | "${SSH[@]}" "tar xzf - -C /usr/local"
	"${SSH[@]}" "cat > /usr/local/bin/weston-env.sh <<'EOF'
# Окружение Weston из /usr/local (docs/wayland-plan.md)
export LD_LIBRARY_PATH=$LIB\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
export GBM_BACKENDS_PATH=$LIB/gbm
export XKB_CONFIG_ROOT=/usr/local/share/X11/xkb
export XDG_RUNTIME_DIR=/run/user/0
export LIBSEAT_BACKEND=builtin
EOF
chmod 644 /usr/local/bin/weston-env.sh"
	echo "== deployed (sha256 weston) =="
	echo "local  $(sha256sum "$LOCAL/bin/weston" | cut -c1-16)"
	"${SSH[@]}" "echo remote \$(sha256sum /usr/local/bin/weston | cut -c1-16); ls -l /usr/local/bin/weston* | head"
	;;
check)
	"${SSH[@]}" '
		fail=0
		echo "-- Mesa в /usr/local --"
		for f in libEGL.so.1 libGLESv2.so.2 libgbm.so.1 libgallium-25.0.7.so \
			 libdrm.so.2 gbm/dri_gbm.so; do
			if [ -e /usr/local/lib/aarch64-linux-gnu/$f ]; then
				echo "  ok   $f"
			else
				echo "  НЕТ  $f"; fail=1
			fi
		done
		echo "-- Weston --"
		for f in bin/weston lib/aarch64-linux-gnu/libweston-13.so.0.0.0 \
			 lib/aarch64-linux-gnu/libweston-13/drm-backend.so \
			 lib/aarch64-linux-gnu/libweston-13/gl-renderer.so \
			 lib/aarch64-linux-gnu/weston/kiosk-shell.so \
			 share/X11/xkb/rules/evdev; do
			[ -e /usr/local/$f ] && echo "  ok   $f" || { echo "  НЕТ  $f"; fail=1; }
		done
		echo "-- DRM --"
		ls -l /dev/dri/
		for c in /sys/class/drm/card*-DSI-1/status; do
			printf "  %s: %s\n" "$c" "$(cat $c)"
		done
		echo "-- runtime dir --"
		mkdir -p /run/user/0 && chmod 700 /run/user/0 && ls -ld /run/user/0
		echo "-- input --"
		ls /dev/input/ 2>/dev/null | head
		[ $fail = 0 ] && echo "READY" || echo "NOT READY"
	'
	;;
smoke)
	S=${2:-10}
	"${SSH[@]}" "mkdir -p /run/user/0 && chmod 700 /run/user/0
		rm -f /tmp/weston-smoke.log /tmp/weston-smoke.out
		pkill -f '/usr/local/bin/weston ' 2>/dev/null || true
		sleep 1
		setsid $RUNENV /usr/local/bin/weston $WESTON_OPTS \
			--socket=wayland-t1100 --log=/tmp/weston-smoke.log \
			>/tmp/weston-smoke.out 2>&1 </dev/null &
		echo started"
	echo "== ждём wayland-сокет =="
	ok=0
	for _ in $(seq 1 20); do
		if "${SSH[@]}" "test -S /run/user/0/wayland-t1100" 2>/dev/null; then ok=1; break; fi
		sleep 1
	done
	[ "$ok" = 1 ] && echo "сокет есть" || echo "СОКЕТА НЕТ"
	echo "== weston-simple-egl (${S} с) =="
	"${SSH[@]}" "$RUNENV timeout $S /usr/local/bin/weston-simple-egl 2>&1 | tail -4; echo client_exit=\$?" || true
	echo "== лог weston (ошибки/repaint) =="
	"${SSH[@]}" "grep -ciE 'error|fail|fatal' /tmp/weston-smoke.log; \
		grep -m3 -iE 'Output |repaint|kms|gbm' /tmp/weston-smoke.log; \
		echo ---; tail -15 /tmp/weston-smoke.log; \
		pkill -f '/usr/local/bin/weston ' 2>/dev/null; echo stopped"
	;;
run)
	"${SSH[@]}" "mkdir -p /run/user/0 && chmod 700 /run/user/0
		pkill -f '/usr/local/bin/weston ' 2>/dev/null || true
		rm -f /tmp/weston.log
		setsid $RUNENV /usr/local/bin/weston $WESTON_OPTS \
			--socket=wayland-0 --log=/tmp/weston.log </dev/null &
		sleep 1; pgrep -af '/usr/local/bin/weston ' | head -2"
	echo "weston запущен фоном, лог: /tmp/weston.log"
	echo "остановить: tools/host/weston-test.sh stop"
	;;
stop)
	"${SSH[@]}" "pkill -f '/usr/local/bin/weston ' && echo stopped || echo 'не запущен'; sleep 1; pgrep -af '/usr/local/bin/weston ' || true"
	;;
log)
	"${SSH[@]}" "tail -${2:-40} /tmp/weston-smoke.log /tmp/weston.log 2>/dev/null"
	;;
undeploy)
	rmlist=$(cd "$LOCAL" && find . -type f -o -type l | sed 's|^\./||' |
		grep -vE '^lib/aarch64-linux-gnu/(libEGL|libGLESv2|libgbm|libgallium|libdrm)\.so' |
		grep -vE '^share/(man|pkgconfig)/')
	printf '%s\n' "$rmlist" | "${SSH[@]}" 'cd /usr/local && xargs -r rm -f; \
		rmdir -p lib/aarch64-linux-gnu/libweston-13 lib/aarch64-linux-gnu/weston \
			share/weston share/X11/xkb share/libweston-13 share/wayland-sessions 2>/dev/null; \
		rm -f /usr/local/bin/weston-env.sh; echo undeployed'
	;;
*) usage ;;
esac
