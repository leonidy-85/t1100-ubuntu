#!/usr/bin/env bash
# Залить Mesa (panfrost) / kmscube / egl-probe на планшет и прогнать GL-тест.
# Ничего не прошивает и не меняет системные пути: всё в /usr/local.
#
#   tools/host/mesa-test.sh deploy[ -glmark2] # разложить библиотеки и утилиты (Mesa / glmark2)
#   tools/host/mesa-test.sh probe [узел]    # egl-probe (по умолчанию renderD128, без KMS)
#   tools/host/mesa-test.sh kmscube [сек]   # kmscube на card1 (mediatek-drm, kmsro -> panfrost)
#   tools/host/mesa-test.sh glmark2 [аргументы glmark2...]  # по умолчанию короткий прогон
#   tools/host/mesa-test.sh info            # версии, /dev/dri, dmesg-хвост
#   tools/host/mesa-test.sh power           # vbat/vsys через mt6370-adc (iio)
#   tools/host/mesa-test.sh clean           # снести /usr/local/lib/aarch64-linux-gnu
#
# Раскладка (libdir Mesa = /usr/lib, поэтому libgallium лежит рядом с libEGL):
#   /usr/local/lib/aarch64-linux-gnu/{libEGL.so.1,libGLESv2.so.2,libgbm.so.1,
#                                    libgallium-25.0.7.so,libdrm.so.2}
#   /usr/local/lib/aarch64-linux-gnu/gbm/dri_gbm.so
#   /usr/local/bin/{kmscube,egl-probe,mesa-env.sh}
#
# Окружение (mesa-env.sh): LD_LIBRARY_PATH + GBM_BACKENDS_PATH.
# LIBGL_DRIVERS_PATH не нужен: в Mesa 25 libEGL/libGBM линкуются с libgallium
# напрямую, отдельных *_dri.so нет.
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
LOCAL=${LOCAL:-$ROOT/build/mesa-aarch64}
HOST=${T1100_HOST:-10.42.66.66}
USR=${T1100_USER:-root}
SSH=(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 "$USR@$HOST")
LIB=/usr/local/lib/aarch64-linux-gnu
RUN="env LD_LIBRARY_PATH=$LIB GBM_BACKENDS_PATH=$LIB/gbm"

case "${1:-}" in
deploy)
	for f in bin/kmscube bin/egl-probe lib/libEGL.so.1.0.0 lib/libGLESv2.so.2.0.0 \
		 lib/libgbm.so.1.0.0 lib/libgallium-25.0.7.so lib/libdrm.so.2.125.0 \
		 lib/gbm/dri_gbm.so; do
		[ -f "$LOCAL/$f" ] || { echo "нет $LOCAL/$f" >&2; exit 1; }
	done
	"${SSH[@]}" "mkdir -p $LIB/gbm /usr/local/bin"
	for f in lib/libEGL.so.1.0.0 lib/libGLESv2.so.2.0.0 lib/libgbm.so.1.0.0 \
		 lib/libgallium-25.0.7.so lib/libdrm.so.2.125.0 lib/gbm/dri_gbm.so \
		 bin/kmscube bin/egl-probe; do
		case "$f" in
			lib/gbm/*) dst=$LIB/gbm/$(basename "$f") ;;
			lib/*)     dst=$LIB/$(basename "$f") ;;
			bin/*)     dst=/usr/local/bin/$(basename "$f") ;;
		esac
		"${SSH[@]}" "cat > $dst.tmp && chmod 755 $dst.tmp && mv $dst.tmp $dst" < "$LOCAL/$f"
	done
	"${SSH[@]}" "cd $LIB && ln -sf libEGL.so.1.0.0 libEGL.so.1 && \
		ln -sf libGLESv2.so.2.0.0 libGLESv2.so.2 && ln -sf libgbm.so.1.0.0 libgbm.so.1 && \
		ln -sf libdrm.so.2.125.0 libdrm.so.2 && cat > /usr/local/bin/mesa-env.sh <<'EOF'
# Окружение Mesa из /usr/local (docs/mesa-cross.md)
export LD_LIBRARY_PATH=$LIB\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
export GBM_BACKENDS_PATH=$LIB/gbm
# для отладки: MESA_DEBUG=1 EGL_LOG_LEVEL=debug LIBGL_DEBUG=verbose
EOF
		chmod 644 /usr/local/bin/mesa-env.sh"
	echo "== deployed =="
	"${SSH[@]}" "ls -l $LIB/ $LIB/gbm/ /usr/local/bin/kmscube /usr/local/bin/egl-probe | tail -20"
	;;
probe)
	NODE=${2:-/dev/dri/renderD128}
	"${SSH[@]}" "$RUN /usr/local/bin/egl-probe $NODE"
	;;
kmscube)
	SECS=${2:-8}
	# kmscube считает EOF на stdin («user interrupted!») нажатием клавиши и
	# выходит после первого кадра — поэтому stdin держим открытым через sleep.
	"${SSH[@]}" "( sleep $((SECS + 5)) ) | timeout $((SECS + 2)) $RUN /usr/local/bin/kmscube -D /dev/dri/card1 2>&1 | grep -v extensions | tail -12; echo exit=\$?"
	;;
kmscube-card0)
	SECS=${2:-8}
	"${SSH[@]}" "( sleep $((SECS + 5)) ) | timeout $((SECS + 2)) $RUN /usr/local/bin/kmscube -D /dev/dri/card0 2>&1 | grep -v extensions | tail -12; echo exit=\$?"
	;;
glmark2-deploy|deploy-glmark2)
	GM=${GM_LOCAL:-$ROOT/build/glmark2-aarch64}
	for f in bin/glmark2-es2-drm lib/libjpeg.so.8.2.2 lib/libpng16.so.16.43.0; do
		[ -f "$GM/$f" ] || { echo "нет $GM/$f — сначала scripts/build-glmark2-aarch64.sh" >&2; exit 1; }
	done
	"${SSH[@]}" "mkdir -p $LIB /usr/local/bin /usr/local/share/glmark2"
	for f in bin/glmark2-es2-drm lib/libjpeg.so.8.2.2 lib/libpng16.so.16.43.0; do
		case "$f" in
			bin/*) dst=/usr/local/bin/$(basename "$f") ;;
			lib/*) dst=$LIB/$(basename "$f") ;;
		esac
		"${SSH[@]}" "cat > $dst.tmp && chmod 755 $dst.tmp && mv $dst.tmp $dst" < "$GM/$f"
	done
	"${SSH[@]}" "cd $LIB && ln -sf libjpeg.so.8.2.2 libjpeg.so.8 && ln -sf libpng16.so.16.43.0 libpng16.so.16"
	tar -C "$GM/share/glmark2" -cf - . \
		| "${SSH[@]}" "tar -C /usr/local/share/glmark2 -xf -"
	echo "== glmark2 deployed =="
	"${SSH[@]}" "ls -l /usr/local/bin/glmark2-es2-drm; du -sh /usr/local/share/glmark2; ls $LIB/libjpeg* $LIB/libpng16*"
	;;
glmark2)
	shift || true
	# Без аргументов — короткий прогон: 4 сцены по 10 с на card1 (KMS mediatek +
	# kmsro -> panfrost). stdin держим открытым: glmark2, как и kmscube,
	# трактует EOF как «пользователь нажал клавишу».
	if [ $# -eq 0 ]; then
		set -- --data-path /usr/local/share/glmark2 \
			-b :drm-device=/dev/dri/card1:duration=10 \
			-b build -b texture -b shading -b effect2d
	fi
	CMD=$(printf '%q ' "$@")
	"${SSH[@]}" "( sleep 300 ) | $RUN timeout 240 /usr/local/bin/glmark2-es2-drm $CMD 2>&1 | grep -vE '^ *$' | tail -60; echo exit=\$?"
	;;
info)
	"${SSH[@]}" "uname -r; ls -l /dev/dri/; for f in /sys/class/drm/card*-DSI-1/status; do printf '%s: ' \$f; cat \$f; done; dmesg | grep -iE 'panfrost|mali|MMU fault|job timeout|slab' | tail -8"
	;;
power)
	"${SSH[@]}" 'D=/sys/bus/iio/devices/iio:device0; for i in 2 3; do printf "%-6s raw=%s scale=%s => %s mV\n" "$(cat $D/in_voltage${i}_label)" "$(cat $D/in_voltage${i}_raw)" "$(cat $D/in_voltage${i}_scale)" "$(( $(cat $D/in_voltage${i}_raw) * $(cat $D/in_voltage${i}_scale) ))"; done; grep POWER_SUPPLY_STATUS /sys/class/power_supply/mt6370-charger/uevent'
	;;
clean)
	"${SSH[@]}" "rm -rf $LIB /usr/local/bin/kmscube /usr/local/bin/egl-probe /usr/local/bin/mesa-env.sh; echo cleaned"
	;;
*)
	sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
