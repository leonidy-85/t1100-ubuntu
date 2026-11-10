#!/usr/bin/env bash
# Выполняется НА build-хосте (172.17.141.172). Не запускать локально.
#
# Env: MESA_VER (25.0.7), SYSROOT (/home/l/t1100-sysroot),
#      TOOLS_DIR (/home/l/t1100-tools), DEST (<tools>/mesa-install), CLEAN (0/1)
#
# Собирает Mesa (panfrost, EGL+GLES2+GBM, без X11/Wayland/GLX/Vulkan/LLVM),
# kmscube и egl-probe (tools/egl-probe/egl-probe.c, копируется рядом).
set -euo pipefail

MESA_VER=${MESA_VER:-25.0.7}
SYSROOT=${SYSROOT:-/home/l/t1100-sysroot}
TOOLS_DIR=${TOOLS_DIR:-/home/l/t1100-tools}
DEST=${DEST:-$TOOLS_DIR/mesa-install}
CLEAN=${CLEAN:-0}
CROSS=cross-aarch64-mesa.txt
JOBS=${JOBS:-$(nproc)}

cd "$TOOLS_DIR"

# --- host-side зависимости ---
for p in python3-mako g++-aarch64-linux-gnu; do
	dpkg -s "$p" >/dev/null 2>&1 || echo 0 | sudo -S apt-get install -y -qq "$p"
done

# --- arm64 dev-пакеты в sysroot (noble 24.04) ---
sysroot_pkg() { # $1 = file inside sysroot, $2 = pkg:arch
	[ -f "$SYSROOT$1" ] && return 0
	( cd /tmp && apt-get download "$2" >/dev/null 2>&1 \
	  && echo 0 | sudo -S dpkg -x "${2%%:*}_"*.deb "$SYSROOT" )
	echo "sysroot: $2 -> $1"
}
sysroot_pkg /usr/include/stdlib.h      libc6-dev:arm64
sysroot_pkg /usr/include/linux/input.h linux-libc-dev:arm64
sysroot_pkg /usr/include/zlib.h        zlib1g-dev:arm64

# --- Mesa: исходники из tarball (git clone с freedesktop слишком медленный) ---
if [ ! -f "/tmp/mesa-$MESA_VER.tar.xz" ]; then
	curl -sSL -o "/tmp/mesa-$MESA_VER.tar.xz" \
		"https://archive.mesa3d.org/mesa-$MESA_VER.tar.xz"
fi
rm -rf mesa-src
tar xf "/tmp/mesa-$MESA_VER.tar.xz"
mv "mesa-$MESA_VER" mesa-src
echo "mesa $(cat mesa-src/VERSION)"

[ "$CLEAN" = 1 ] && rm -rf build-mesa
if [ ! -d build-mesa ]; then
	meson setup build-mesa mesa-src --cross-file "$CROSS" --wrap-mode=nodownload \
		-Dbuildtype=release -Dprefix=/usr -Dplatforms= \
		-Dgallium-drivers=panfrost -Dvulkan-drivers= \
		-Dglx=disabled -Degl=enabled -Dgles1=disabled -Dgles2=enabled \
		-Dgbm=enabled -Dglvnd=disabled -Dllvm=disabled -Dvideo-codecs=
fi
ninja -C build-mesa -j "$JOBS"
rm -rf "$DEST"
DESTDIR="$DEST" ninja -C build-mesa install

# --- kmscube + egl-probe ---
[ -d kmscube-src ] || git clone -q --depth 1 \
	https://gitlab.freedesktop.org/mesa/kmscube.git kmscube-src

CFLAGS_EXTRA="--sysroot=$SYSROOT -isystem $SYSROOT/usr/include/aarch64-linux-gnu -isystem $SYSROOT/usr/include"
INC="-I$DEST/usr/include -I$SYSROOT/usr/include/libdrm"
# Mesa 25: libEGL ссылается на символы, версионированные @libgallium-<ver>.so,
# и сама libgallium собрана на C++ — отсюда -l:libgallium-... и -lstdc++.
LIBS="-L$DEST/usr/lib -L$SYSROOT/usr/lib/aarch64-linux-gnu -lEGL -lGLESv2 -lgbm \
      -l:libgallium-$MESA_VER.so -ldrm -lm -lpthread -lstdc++"

( cd kmscube-src && aarch64-linux-gnu-gcc $CFLAGS_EXTRA -O2 -std=gnu99 -D_GNU_SOURCE \
	-DHAVE_GLES3 $INC -o kmscube kmscube.c common.c cube-smooth.c cube-gears.c \
	cube-tex.c drm-atomic.c drm-common.c drm-legacy.c drm-offscreen.c esTransform.c \
	frame-512x512-NV12.c frame-512x512-RGBA.c perfcntrs.c cube-shadertoy.c $LIBS )

[ -f egl-probe.c ] || { echo "нет egl-probe.c" >&2; exit 1; }
aarch64-linux-gnu-gcc $CFLAGS_EXTRA -O2 -Wall $INC -o egl-probe egl-probe.c $LIBS

echo "== built =="
ls -la kmscube-src/kmscube egl-probe
