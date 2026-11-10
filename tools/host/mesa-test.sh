#!/usr/bin/env bash
# Залить Mesa (panfrost) / kmscube / egl-probe на планшет и прогнать GL-тест.
# Ничего не прошивает и не меняет системные пути: всё в /usr/local.
#
#   tools/host/mesa-test.sh deploy          # разложить библиотеки и утилиты
#   tools/host/mesa-test.sh probe [узел]    # egl-probe (по умолчанию renderD128, без KMS)
#   tools/host/mesa-test.sh kmscube [сек]   # kmscube на card1 (mediatek-drm, kmsro -> panfrost)
#   tools/host/mesa-test.sh kmscube-card0   # то же на card0 (panfrost; для сравнения)
#   tools/host/mesa-test.sh info            # версии, /dev/dri, dmesg-хвост
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
info)
	"${SSH[@]}" "uname -r; ls -l /dev/dri/; for f in /sys/class/drm/card*-DSI-1/status; do printf '%s: ' \$f; cat \$f; done; dmesg | grep -iE 'panfrost|mali|MMU fault|job timeout|slab' | tail -8"
	;;
clean)
	"${SSH[@]}" "rm -rf $LIB /usr/local/bin/kmscube /usr/local/bin/egl-probe /usr/local/bin/mesa-env.sh; echo cleaned"
	;;
*)
	sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
