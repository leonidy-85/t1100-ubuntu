#!/usr/bin/env bash
# Собрать glmark2 (flavor drm-glesv2) под aarch64 на build-хосте.
#
#   scripts/build-glmark2-aarch64.sh            # сборка + забор артефактов
#   scripts/build-glmark2-aarch64.sh --clean    # снести build-каталог
#   scripts/build-glmark2-aarch64.sh --fetch    # только забрать в build/glmark2-aarch64
#
# Env: BUILD_HOST, BUILD_PASS, GLMARK_VER (2023.01), SYSROOT, JOBS
#
# Требует уже собранную Mesa (scripts/build-mesa-aarch64.sh): её staging-копия
# должна лежать в sysroot (так pkg-config находит egl/glesv2/gbm).
#
# Результат: build/glmark2-aarch64/{bin,lib,share} — бинарник
# glmark2-es2-drm, рантайм-библиотеки, которых нет в rootfs планшета
# (libjpeg.so.8, libpng16.so.16) и data-каталог. На планшет кладёт
# tools/host/mesa-test.sh deploy-glmark2.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_HOST="${BUILD_HOST:-l@172.17.141.172}"
BUILD_PASS="${BUILD_PASS:-0}"
GLMARK_VER="${GLMARK_VER:-2023.01}"
SYSROOT="${SYSROOT:-/home/l/t1100-sysroot}"
TOOLS_DIR="${TOOLS_DIR:-/home/l/t1100-tools}"
DEST="${DEST:-${TOOLS_DIR}/glmark2-install}"
LOCAL_OUT="${LOCAL_OUT:-${REPO_ROOT}/build/glmark2-aarch64}"

CLEAN=0; FETCH_ONLY=0
for arg in "$@"; do
	case "$arg" in
		-c|--clean) CLEAN=1 ;;
		--fetch) FETCH_ONLY=1 ;;
		-h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown argument: $arg" >&2; exit 2 ;;
	esac
done

command -v sshpass >/dev/null || { echo "нужен sshpass" >&2; exit 1; }
SSH=(sshpass -p "${BUILD_PASS}" ssh -o StrictHostKeyChecking=no \
	-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${BUILD_HOST}")
RSYNC=(rsync -a -e "sshpass -p ${BUILD_PASS} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null")

fetch() {
	mkdir -p "${LOCAL_OUT}/bin" "${LOCAL_OUT}/lib" "${LOCAL_OUT}/share"
	"${RSYNC[@]}" "${BUILD_HOST}:${DEST}/usr/bin/glmark2-es2-drm" "${LOCAL_OUT}/bin/"
	"${RSYNC[@]}" "${BUILD_HOST}:${DEST}/usr/share/glmark2" "${LOCAL_OUT}/share/"
	"${RSYNC[@]}" "${BUILD_HOST}:${SYSROOT}/usr/lib/aarch64-linux-gnu/libjpeg.so.8.2.2" \
		"${BUILD_HOST}:${SYSROOT}/usr/lib/aarch64-linux-gnu/libpng16.so.16.43.0" "${LOCAL_OUT}/lib/" \
		2>/dev/null || true
	echo "== artifacts in ${LOCAL_OUT} =="
	du -sh "${LOCAL_OUT}"/* && find "${LOCAL_OUT}/bin" "${LOCAL_OUT}/lib" -type f -printf '%10s  %P\n'
}

if [ "${FETCH_ONLY}" = 1 ]; then fetch; exit 0; fi

"${SSH[@]}" "mkdir -p '${TOOLS_DIR}'"
"${RSYNC[@]}" "${REPO_ROOT}/tools/cross-aarch64-glmark2.txt" \
	"${REPO_ROOT}/scripts/remote/build-glmark2-aarch64.sh" "${BUILD_HOST}:${TOOLS_DIR}/"

"${SSH[@]}" "cd '${TOOLS_DIR}' && chmod +x build-glmark2-aarch64.sh && \
	GLMARK_VER='${GLMARK_VER}' SYSROOT='${SYSROOT}' TOOLS_DIR='${TOOLS_DIR}' \
	DEST='${DEST}' CLEAN='${CLEAN}' ./build-glmark2-aarch64.sh"

fetch
