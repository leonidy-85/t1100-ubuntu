#!/usr/bin/env bash
#
# build-iw-aarch64.sh — статический `iw` для aarch64 (nl80211) на build-хосте.
#
# Зачем: на планшете нет ни `iw`, ни `libnl`, ни сети для apt. А `wlan0` в
# вендорском gen3-драйвере создаётся ТОЛЬКО из userspace через nl80211
# (`gl_cfg80211_add_iface` -> `wlanNetCreate` -> `register_netdev`), т.е. нужен
# `iw phy <phyN> interface add wlan0 type managed`. Плюс `iw dev wlan0 scan` —
# это доказательство, что RF-часть жива (рубеж M6).
#
# Что собирается:
#   libnl 3.x (--disable-shared --enable-static, --host=aarch64-linux-gnu)
#   iw      (LDFLAGS=-static, PKG_CONFIG_LIBDIR -> собранный libnl)
#
# Использование:
#   scripts/build-iw-aarch64.sh           # собрать и забрать в build/tools-aarch64/
#   scripts/build-iw-aarch64.sh --clean   # снести build-каталоги на хосте
#
# Env:
#   BUILD_HOST (default l@172.17.141.172)   BUILD_PASS (default 0)
#   LIBNL_VER  (default 3.11.0)             IW_VER     (default 6.9)
#   REMOTE_DIR (default /home/l/t1100-tools/iw-src)
#   LOCAL_OUT  (default <repo>/build/tools-aarch64)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_HOST="${BUILD_HOST:-l@172.17.141.172}"
BUILD_PASS="${BUILD_PASS:-0}"
LIBNL_VER="${LIBNL_VER:-3.11.0}"
IW_VER="${IW_VER:-6.9}"
REMOTE_DIR="${REMOTE_DIR:-/home/l/t1100-tools/iw-src}"
LOCAL_OUT="${LOCAL_OUT:-${REPO_ROOT}/build/tools-aarch64}"

command -v sshpass >/dev/null || { echo "нужен sshpass" >&2; exit 1; }
SSH=(sshpass -p "${BUILD_PASS}" ssh -o StrictHostKeyChecking=no \
	-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${BUILD_HOST}")
SCP=(sshpass -p "${BUILD_PASS}" scp -o StrictHostKeyChecking=no \
	-o UserKnownHostsFile=/dev/null)

mkdir -p "${LOCAL_OUT}"

if [ "${1:-}" = "--clean" ]; then
	"${SSH[@]}" "rm -rf '${REMOTE_DIR}/build-libnl' '${REMOTE_DIR}/libnl-aarch64' '${REMOTE_DIR}/iw-${IW_VER}'"
	echo "очищено на ${BUILD_HOST}:${REMOTE_DIR}"
	exit 0
fi

echo "== t1100 iw (aarch64, build host) =="
echo "host   : ${BUILD_HOST}"
echo "libnl  : ${LIBNL_VER}"
echo "iw     : ${IW_VER}"
echo "remote : ${REMOTE_DIR}"
echo "out    : ${LOCAL_OUT}"

"${SSH[@]}" "REMOTE_DIR='${REMOTE_DIR}' LIBNL_VER='${LIBNL_VER}' IW_VER='${IW_VER}' bash -s" <<'REMOTE'
set -euo pipefail
mkdir -p "${REMOTE_DIR}"
cd "${REMOTE_DIR}"

# --- libnl (static, aarch64) -------------------------------------------------
if [ ! -x "${REMOTE_DIR}/libnl-aarch64/lib/libnl-3.a" ]; then
	[ -f "libnl-${LIBNL_VER}.tar.gz" ] ||
		curl -fsSL -o "libnl-${LIBNL_VER}.tar.gz" \
			"https://github.com/thom311/libnl/releases/download/libnl${LIBNL_VER//./_}/libnl-${LIBNL_VER}.tar.gz"
	rm -rf "libnl-${LIBNL_VER}"
	tar -xf "libnl-${LIBNL_VER}.tar.gz"
	cd "libnl-${LIBNL_VER}"
	./configure --host=aarch64-linux-gnu --build="$(uname -m)-linux-gnu" \
		--prefix="${REMOTE_DIR}/libnl-aarch64" \
		--disable-shared --enable-static \
		--disable-cli --disable-debug \
		> configure.log 2>&1 || { echo '--- libnl configure failed:'; tail -25 configure.log; exit 1; }
	make -j"$(nproc)" > make.log 2>&1 || { echo '--- libnl make failed:'; tail -30 make.log; exit 1; }
	make install > install.log 2>&1 || { echo '--- libnl install failed:'; tail -25 install.log; exit 1; }
	cd "${REMOTE_DIR}"
	ls -l libnl-aarch64/lib/*.a
fi

# --- iw (static, aarch64) ----------------------------------------------------
rm -rf "iw-${IW_VER}"
[ -f "iw-${IW_VER}.tar.gz" ] ||
	curl -fsSL -o "iw-${IW_VER}.tar.gz" "https://kernel.org/pub/software/network/iw/iw-${IW_VER}.tar.gz"
tar -xf "iw-${IW_VER}.tar.gz"
cd "iw-${IW_VER}"
make clean >/dev/null 2>&1 || true
make CC=aarch64-linux-gnu-gcc \
	LDFLAGS="-static -s" \
	PKG_CONFIG=pkg-config \
	PKG_CONFIG_LIBDIR="${REMOTE_DIR}/libnl-aarch64/lib/pkgconfig" \
	PKG_CONFIG_PATH="${REMOTE_DIR}/libnl-aarch64/lib/pkgconfig" \
	> make.log 2>&1 || { echo '--- iw make failed:'; tail -30 make.log; exit 1; }

[ -x iw ] || { echo '--- iw не собрался'; tail -30 make.log; exit 1; }
file iw
readelf -d iw 2>/dev/null | grep -c NEEDED || echo 'NEEDED: 0 (статический)'
ls -l iw
printf '%s\n' "${PWD}/iw" > "${REMOTE_DIR}/iw.path"
REMOTE

remote_bin="$("${SSH[@]}" "cat '${REMOTE_DIR}/iw.path'")"
"${SCP[@]}" "${BUILD_HOST}:${remote_bin}" "${LOCAL_OUT}/iw" 2>&1 | tail -2

echo
echo "== результат =="
file "${LOCAL_OUT}/iw"
ls -l "${LOCAL_OUT}/iw"
sha256sum "${LOCAL_OUT}/iw" | tee "${LOCAL_OUT}/iw.sha256"
if readelf -d "${LOCAL_OUT}/iw" 2>/dev/null | grep -q NEEDED; then
	echo "ВНИМАНИЕ: есть NEEDED — бинарник не статический:" >&2
	readelf -d "${LOCAL_OUT}/iw" | grep NEEDED >&2
	exit 1
fi
echo
echo "Установка на планшет:"
echo "  scp ${LOCAL_OUT}/iw root@10.42.66.66:/usr/local/bin/ && ssh root@10.42.66.66 chmod +x /usr/local/bin/iw"
