#!/usr/bin/env bash
# Собрать Weston (DRM/KMS + GL, без X11/Wayland-доков) под aarch64 на build-хосте.
#
# Всё тяжёлое — на 172.17.141.172 (AGENTS.md); локально только rsync/scp.
#
#   scripts/build-weston-aarch64.sh            # сборка (инкрементальная) + забор bundle
#   scripts/build-weston-aarch64.sh --clean    # снести build-каталог Weston и собрать заново
#   scripts/build-weston-aarch64.sh --fetch    # только забрать bundle в build/weston-aarch64
#
# Env: BUILD_HOST, BUILD_PASS, WESTON_VER (13.0.0), SYSROOT, JOBS
#
# Сама сборка — scripts/remote/build-weston-aarch64.sh (копируется на хост).
# Результат — build/weston-aarch64/ = дерево для /usr/local планшета
# (bin/weston, lib/aarch64-linux-gnu/{libweston-13.so*,weston/*.so,сторонние .so},
#  libexec/weston/*, share/{weston,X11/xkb}); на планшет это кладёт
# tools/host/weston-test.sh deploy.
#
# Почему Weston 13.0.0 (= версия в noble) и без demo-clients:
#  * зависимости Weston 13 совпадают с noble (wayland 1.22, wayland-protocols
#    1.34, libxkbcommon 1.6, libinput 1.25, libseat 0.8, libdisplay-info 0.1.1);
#  * demo-clients (toytoolkit) тянут cairo+pangocairo+freetype+fontconfig и
#    X11-библиотеки в рантайм — для проверки композитора это лишний вес;
#    weston-simple-egl/simple-shm собираются опцией simple-clients и не требуют cairo.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_HOST="${BUILD_HOST:-l@172.17.141.172}"
BUILD_PASS="${BUILD_PASS:-0}"
WESTON_VER="${WESTON_VER:-13.0.0}"
SYSROOT="${SYSROOT:-/home/l/t1100-sysroot}"
TOOLS_DIR="${TOOLS_DIR:-/home/l/t1100-tools}"
BUNDLE="${BUNDLE:-${TOOLS_DIR}/weston-runtime}"
LOCAL_OUT="${LOCAL_OUT:-${REPO_ROOT}/build/weston-aarch64}"

CLEAN=0; FETCH_ONLY=0
for arg in "$@"; do
	case "$arg" in
		-c|--clean) CLEAN=1 ;;
		--fetch) FETCH_ONLY=1 ;;
		-h|--help) sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown argument: $arg" >&2; exit 2 ;;
	esac
done

command -v sshpass >/dev/null || { echo "нужен sshpass" >&2; exit 1; }
SSH=(sshpass -p "${BUILD_PASS}" ssh -o StrictHostKeyChecking=no \
	-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${BUILD_HOST}")
RSYNC=(rsync -a -e "sshpass -p ${BUILD_PASS} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null")

fetch() {
	rm -rf "${LOCAL_OUT}"
	mkdir -p "${LOCAL_OUT}"
	"${RSYNC[@]}" "${BUILD_HOST}:${BUNDLE}/" "${LOCAL_OUT}/"
	echo "== artifacts in ${LOCAL_OUT} =="
	du -sh "${LOCAL_OUT}"
	find "${LOCAL_OUT}" -type f -printf '%10s  %P\n' | sort -k2
}

if [ "${FETCH_ONLY}" = 1 ]; then fetch; exit 0; fi

"${SSH[@]}" "mkdir -p '${TOOLS_DIR}'"
"${RSYNC[@]}" "${REPO_ROOT}/tools/cross-aarch64-weston.txt" \
	"${REPO_ROOT}/scripts/remote/build-weston-aarch64.sh" "${BUILD_HOST}:${TOOLS_DIR}/"

"${SSH[@]}" "cd '${TOOLS_DIR}' && chmod +x build-weston-aarch64.sh && \
	WESTON_VER='${WESTON_VER}' SYSROOT='${SYSROOT}' TOOLS_DIR='${TOOLS_DIR}' \
	BUNDLE='${BUNDLE}' CLEAN='${CLEAN}' ./build-weston-aarch64.sh"

fetch
