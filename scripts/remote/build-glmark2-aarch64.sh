#!/usr/bin/env bash
# Выполняется НА build-хосте. Собирает glmark2 с flavor drm-glesv2 под aarch64.
#
# Env: GLMARK_VER (2023.01), SYSROOT, TOOLS_DIR, DEST, CLEAN
#
# Зависимости: libdrm/gbm/libudev (sysroot), libjpeg + libpng (обязательны для
# glmark2 независимо от flavor), EGL/GLESv2 — из staging нашей Mesa
# (scripts/build-mesa-aarch64.sh кладёт её в sysroot, поэтому pkg-config её
# видит через pkg_config_libdir).
set -euo pipefail

GLMARK_VER=${GLMARK_VER:-2023.01}
SYSROOT=${SYSROOT:-/home/l/t1100-sysroot}
TOOLS_DIR=${TOOLS_DIR:-/home/l/t1100-tools}
DEST=${DEST:-$TOOLS_DIR/glmark2-install}
CLEAN=${CLEAN:-0}
CROSS=cross-aarch64-glmark2.txt
JOBS=${JOBS:-$(nproc)}

cd "$TOOLS_DIR"

sysroot_pkg() { # $1 = file inside sysroot, $2 = pkg:arch
	[ -f "$SYSROOT$1" ] && return 0
	( cd /tmp && apt-get download "$2" >/dev/null 2>&1 \
	  && echo 0 | sudo -S dpkg -x "${2%%:*}_"*.deb "$SYSROOT" )
	echo "sysroot: $2 -> $1"
}
# dev + runtime (runtime нужны линкеру: libpng16.so.16, libjpeg.so.8)
sysroot_pkg /usr/include/jpeglib.h              libjpeg-turbo8-dev:arm64
sysroot_pkg /usr/lib/aarch64-linux-gnu/libjpeg.so.8    libjpeg-turbo8:arm64
sysroot_pkg /usr/include/png.h                  libpng-dev:arm64
sysroot_pkg /usr/lib/aarch64-linux-gnu/libpng16.so.16  libpng16-16t64:arm64

# Mesa staging должна уже лежать в sysroot (libEGL/gbm/glesv2 .pc и заголовки)
if [ ! -f "$SYSROOT/usr/lib/pkgconfig/egl.pc" ]; then
	echo "в sysroot нет Mesa staging — сначала scripts/build-mesa-aarch64.sh" >&2
	exit 1
fi

if [ ! -f "glmark2-$GLMARK_VER.tar.gz" ]; then
	curl -sSL -o "glmark2-$GLMARK_VER.tar.gz" \
		"https://github.com/glmark2/glmark2/archive/refs/tags/$GLMARK_VER.tar.gz"
fi
rm -rf glmark2-src
tar xf "glmark2-$GLMARK_VER.tar.gz"
mv "glmark2-$GLMARK_VER" glmark2-src

cd glmark2-src
[ "$CLEAN" = 1 ] && rm -rf build-glmark2
if [ ! -d build-glmark2 ]; then
	meson setup build-glmark2 . --cross-file "../$CROSS" \
		-Dbuildtype=release -Dprefix=/usr -Dflavors=drm-glesv2
fi
ninja -C build-glmark2 -j "$JOBS"
rm -rf "$DEST"
DESTDIR="$DEST" ninja -C build-glmark2 install

echo "== installed =="
ls -la "$DEST/usr/bin/" && du -sh "$DEST/usr/share/glmark2"
