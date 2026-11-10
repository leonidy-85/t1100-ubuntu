#!/usr/bin/env bash
# Выполняется НА build-хосте (172.17.141.172). Не запускать локально.
#
# Env: WESTON_VER (13.0.0), SYSROOT (/home/l/t1100-sysroot),
#      TOOLS_DIR (/home/l/t1100-tools), MESA_INSTALL (<tools>/mesa-install),
#      DEST (<tools>/weston-install), BUNDLE (<tools>/weston-runtime),
#      CROSS (cross-aarch64-weston.txt), CLEAN (0/1)
#
# 1) добирает arm64 dev-пакеты noble в sysroot (apt-get download + dpkg -x,
#    как docs/cross-build.md §3);
# 2) собирает Weston 13.0.0: drm-backend + GL-рендерер, без X11/Wayland/RDP/VNC,
#    без systemd/demo-clients/cairo-клиентов, kiosk-shell, simple-egl/simple-shm;
# 3) раскладывает DESTDIR в $DEST (prefix=/usr/local) и собирает $BUNDLE —
#    дерево для /usr/local планшета плюс транзитивное замыкание сторонних .so
#    из sysroot (тех, которых нет на планшете).
set -euo pipefail

WESTON_VER=${WESTON_VER:-13.0.0}
SYSROOT=${SYSROOT:-/home/l/t1100-sysroot}
TOOLS_DIR=${TOOLS_DIR:-/home/l/t1100-tools}
MESA_INSTALL=${MESA_INSTALL:-$TOOLS_DIR/mesa-install}
DEST=${DEST:-$TOOLS_DIR/weston-install}
BUNDLE=${BUNDLE:-$TOOLS_DIR/weston-runtime}
CROSS=${CROSS:-cross-aarch64-weston.txt}
CLEAN=${CLEAN:-0}
JOBS=${JOBS:-$(nproc)}
ARCH=aarch64-linux-gnu
SRC=$TOOLS_DIR/weston/weston-$WESTON_VER
DEBS=$TOOLS_DIR/debs-weston
TARBALL=$TOOLS_DIR/weston/weston-$WESTON_VER.tar.xz
SUDO() { echo 0 | sudo -S "$@"; }

cd "$TOOLS_DIR"

# --- host-side инструменты ---
for p in ninja-build meson libwayland-bin g++-$ARCH pkg-config; do
	dpkg -s "$p" >/dev/null 2>&1 || echo 0 | sudo -S apt-get install -y -qq "$p"
done

# --- arm64 dev-пакеты noble в sysroot ---
# Именно `apt-get download` + `dpkg -x` (docs/cross-build.md §3), а НЕ
# `apt-get install -d`: при мультиархе на хосте (26.04) установка arm64-пакетов
# упирается в Breaks между amd64- и arm64-версиями (например libbz2-1.0),
# потому что мультиарх требует одинаковых версий, а релизы разные.
# Поэтому список явный: dev-пакеты (.pc/заголовки/симлинки) + runtime-библиотеки
# (soname, нужны линковке) + arch:all с данными.
PKGS="libwayland-dev libwayland-client0 libwayland-server0 libwayland-cursor0
      libwayland-egl1 libxkbcommon-dev libxkbcommon0 libpixman-1-dev
      libpixman-1-0 libinput-dev libinput10 libevdev-dev libevdev2
      libmtdev-dev libmtdev1t64 libwacom-dev libwacom9 libseat-dev libseat1
      libdisplay-info-dev libdisplay-info1 libcairo2-dev libcairo2
      libfreetype-dev libfreetype6 libfontconfig-dev libfontconfig1
      libx11-dev libx11-6 libxext-dev libxext6 libxrender-dev libxrender1
      libxcb1-dev libxcb1 libxcb-render0-dev libxcb-render0 libxcb-shm0-dev
      libxcb-shm0 libxau-dev libxau6 libxdmcp-dev libxdmcp6 libbz2-dev
      libbz2-1.0 libbrotli-dev libbrotli1 libpng-dev libpng16-16t64
      zlib1g-dev zlib1g libexpat1-dev libexpat1 libffi-dev libffi8"
# x11proto-dev — arch:all, но в apt кэше хоста висит версия 26.04 (2025.1),
# а .pc-файлы протоколов (xproto.pc, xextproto.pc, renderproto.pc) нужны от
# noble (2023.2), поэтому версия запинена.
PKGS_ALL="wayland-protocols xkb-data"
X11PROTO="x11proto-dev=2023.2-1"

mkdir -p "$DEBS"
for p in $PKGS; do
	( cd "$DEBS" && apt-get download "$p:arm64" >/dev/null 2>&1 ) \
		|| echo "!! не скачался $p:arm64" >&2
done
for p in $PKGS_ALL; do
	( cd "$DEBS" && apt-get download "$p" >/dev/null 2>&1 ) \
		|| echo "!! не скачался $p" >&2
done
( cd "$DEBS" && apt-get download "$X11PROTO" >/dev/null 2>&1 ) \
	|| echo "!! не скачался $X11PROTO" >&2
for f in "$DEBS"/*.deb; do
	echo 0 | sudo -S dpkg -x "$f" "$SYSROOT"
done
echo "sysroot: $(ls "$DEBS"/*.deb | wc -l) пакетов распаковано"

# --- проверка, что pkg-config видит всё нужное ---
PC_DIRS="$MESA_INSTALL/usr/lib/pkgconfig:$SYSROOT/usr/lib/$ARCH/pkgconfig:$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
for m in wayland-server wayland-client xkbcommon pixman-1 libinput libseat \
	 libdisplay-info libdrm cairo libpng egl glesv2 gbm; do
	PKG_CONFIG_LIBDIR="$PC_DIRS" pkg-config --exists "$m" \
		|| { echo "pkg-config: нет $m" >&2; exit 1; }
	printf '%-16s %s\n' "$m" "$(PKG_CONFIG_LIBDIR="$PC_DIRS" pkg-config --modversion "$m")"
done

# --- исходники ---
mkdir -p "$TOOLS_DIR/weston"
if [ ! -f "$TARBALL" ]; then
	# wayland.freedesktop.org отдаёт 301 -> нужен -L
	curl -sSL -o "$TARBALL" \
		"https://wayland.freedesktop.org/releases/weston-$WESTON_VER.tar.xz"
fi
if [ ! -d "$SRC" ]; then
	tar -C "$TOOLS_DIR/weston" -xf "$TARBALL"
fi
grep -m1 "version:" "$SRC/meson.build"

[ "$CLEAN" = 1 ] && rm -rf build-weston
if [ ! -d build-weston ]; then
	meson setup build-weston "$SRC" --cross-file "$CROSS" --wrap-mode=nodownload \
		--buildtype=release --prefix=/usr/local --libdir=lib/$ARCH \
		-Dbackend-default=drm \
		-Dbackend-drm=true -Dbackend-drm-screencast-vaapi=false \
		-Dbackend-headless=false -Dbackend-x11=false -Dbackend-wayland=false \
		-Dbackend-rdp=false -Dbackend-vnc=false -Dbackend-pipewire=false \
		-Dscreenshare=false -Dremoting=false -Dpipewire=false \
		-Drenderer-gl=true -Dxwayland=false -Dsystemd=false \
		-Dshell-desktop=false -Dshell-kiosk=true \
		-Dshell-fullscreen=false -Dshell-ivi=false \
		-Dcolor-management-lcms=false \
		-Ddeprecated-color-management-static=false \
		-Ddeprecated-color-management-colord=false \
		-Dimage-jpeg=false -Dimage-webp=false \
		-Ddemo-clients=false -Dsimple-clients=egl,shm \
		-Dresize-pool=false -Dwcap-decode=false -Dtools= \
		-Dtests=false -Ddoc=false
fi
ninja -C build-weston -j "$JOBS"

rm -rf "$DEST"
DESTDIR="$DEST" ninja -C build-weston install

# --- bundle: дерево для /usr/local планшета + сторонние .so из sysroot ---
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE"
cp -a "$DEST/usr/local/." "$BUNDLE/"
# на планшете не нужны заголовки, .pc и man
rm -rf "$BUNDLE/include" "$BUNDLE/lib/pkgconfig" "$BUNDLE/lib/$ARCH/pkgconfig" \
	"$BUNDLE/share/man"

# xkb-данные (нужны libxkbcommon; на планшете /usr/share/X11/xkb отсутствует)
mkdir -p "$BUNDLE/share/X11"
cp -a "$SYSROOT/usr/share/X11/xkb" "$BUNDLE/share/X11/xkb"

# уже есть на планшете (rootfs noble) или всегда предоставляется glibc
ALLOW="libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0 librt.so.1 libgcc_s.so.1
       libstdc++.so.6 ld-linux-aarch64.so.1 libudev.so.1 libexpat.so.1
       libffi.so.8 libz.so.1 libcap.so.2 libselinux.so.1 libsystemd.so.0
       liblzma.so.5 liblz4.so.1 libgcrypt.so.20 libcrypto.so.3 libbz2.so.1.0
       libmount.so.1 libblkid.so.1"

have_allow() { for a in $ALLOW; do [ "$a" = "$1" ] && return 0; done; return 1; }

# где искать soname: наш bundle, sysroot, mesa-install
SEARCH="$BUNDLE/lib/$ARCH $SYSROOT/usr/lib/$ARCH $SYSROOT/lib/$ARCH $MESA_INSTALL/usr/lib"
find_soname() {
	local s=$1 d
	for d in $SEARCH; do
		[ -e "$d/$s" ] && { echo "$d/$s"; return 0; }
	done
	return 1
}

# итеративно до неподвижной точки: NEEDED всех ELF в bundle
for _pass in 1 2 3 4 5 6 7 8 9 10; do
	added=0
	while read -r f; do
		while read -r so; do
			[ -z "$so" ] && continue
			have_allow "$so" && continue
			[ -e "$BUNDLE/lib/$ARCH/$so" ] && continue
			src=$(find_soname "$so") || { echo "!! нет $so (нужен $f)" >&2; exit 1; }
			cp -a "$src" "$BUNDLE/lib/$ARCH/$so"
			added=$((added + 1))
		done < <("$ARCH-readelf" -d "$f" 2>/dev/null | awk '/NEEDED/{gsub(/[\[\]]/,"",$5); print $5}')
	done < <(find "$BUNDLE" -type f -exec sh -c 'head -c4 "$1" | grep -q ELF' _ {} \; -print)
	[ "$added" = 0 ] && break
	echo "pass $_pass: +$added библиотек"
done

echo "== weston install =="
ls -l "$BUNDLE/bin" "$BUNDLE/lib/$ARCH"/weston 2>/dev/null
echo "== bundle size =="
du -sh "$BUNDLE"
find "$BUNDLE" -name '*.so*' -type f -printf '%10s  %P\n' | sort -k2
