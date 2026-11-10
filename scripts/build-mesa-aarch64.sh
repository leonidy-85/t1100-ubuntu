#!/usr/bin/env bash
# Собрать Mesa (panfrost) + kmscube + egl-probe под aarch64 на build-хосте.
#
# Всё тяжёлое — на 172.17.141.172 (AGENTS.md); локально только rsync и scp.
#
#   scripts/build-mesa-aarch64.sh            # сборка (инкрементальная) + забор артефактов
#   scripts/build-mesa-aarch64.sh --clean    # снести build-каталог Mesa и собрать заново
#   scripts/build-mesa-aarch64.sh --fetch    # только забрать артефакты в build/mesa-aarch64
#
# Env: BUILD_HOST, BUILD_PASS, MESA_VER (25.0.7), SYSROOT, JOBS
#
# Платформы EGL: wayland + surfaceless + drm (`-Dplatforms=wayland`; drm и
# surfaceless включаются сами). Wayland нужен клиентам Weston (weston-simple-egl),
# drm/surfaceless — kmscube/glmark2/egl-probe. См. docs/mesa-cross.md.
#
# Сама сборка — scripts/remote/build-mesa-aarch64.sh (копируется на хост).
# Результат — build/mesa-aarch64/{lib,lib/gbm,bin}; на планшет это кладёт
# tools/host/mesa-test.sh deploy (в /usr/local, rootfs не трогается).
#
# Почему Mesa 25.0.7, а не новее: с 25.1 (и в 26.x) meson включает CLC для
# panfrost (`with_driver_using_cl` содержит with_gallium_panfrost), а CLC
# требует LLVM — то есть кросс-сборку LLVM ради GLES. В 25.0.7 panfrost и
# kmsro те же.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_HOST="${BUILD_HOST:-l@172.17.141.172}"
BUILD_PASS="${BUILD_PASS:-0}"
MESA_VER="${MESA_VER:-25.0.7}"
SYSROOT="${SYSROOT:-/home/l/t1100-sysroot}"
TOOLS_DIR="${TOOLS_DIR:-/home/l/t1100-tools}"
DEST="${DEST:-${TOOLS_DIR}/mesa-install}"
LOCAL_OUT="${LOCAL_OUT:-${REPO_ROOT}/build/mesa-aarch64}"

CLEAN=0; FETCH_ONLY=0
for arg in "$@"; do
	case "$arg" in
		-c|--clean) CLEAN=1 ;;
		--fetch) FETCH_ONLY=1 ;;
		-h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown argument: $arg" >&2; exit 2 ;;
	esac
done

command -v sshpass >/dev/null || { echo "нужен sshpass" >&2; exit 1; }
SSH=(sshpass -p "${BUILD_PASS}" ssh -o StrictHostKeyChecking=no \
	-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${BUILD_HOST}")
RSYNC=(rsync -a -e "sshpass -p ${BUILD_PASS} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null")

fetch() {
	mkdir -p "${LOCAL_OUT}/lib/gbm" "${LOCAL_OUT}/bin"
	"${RSYNC[@]}" "${BUILD_HOST}:${DEST}/usr/lib/libEGL.so.1.0.0" \
		"${BUILD_HOST}:${DEST}/usr/lib/libGLESv2.so.2.0.0" \
		"${BUILD_HOST}:${DEST}/usr/lib/libgbm.so.1.0.0" \
		"${BUILD_HOST}:${DEST}/usr/lib/libgallium-${MESA_VER}.so" "${LOCAL_OUT}/lib/"
	"${RSYNC[@]}" "${BUILD_HOST}:${DEST}/usr/lib/gbm/dri_gbm.so" "${LOCAL_OUT}/lib/gbm/"
	"${RSYNC[@]}" "${BUILD_HOST}:${SYSROOT}/usr/lib/aarch64-linux-gnu/libdrm.so.2.125.0" \
		"${LOCAL_OUT}/lib/" 2>/dev/null || true
	"${RSYNC[@]}" "${BUILD_HOST}:${TOOLS_DIR}/kmscube-src/kmscube" \
		"${BUILD_HOST}:${TOOLS_DIR}/egl-probe" "${LOCAL_OUT}/bin/"
	echo "== artifacts in ${LOCAL_OUT} =="
	find "${LOCAL_OUT}" -type f -printf '%10s  %P\n' | sort -k2
}

if [ "${FETCH_ONLY}" = 1 ]; then fetch; exit 0; fi

"${SSH[@]}" "mkdir -p '${TOOLS_DIR}'"
"${RSYNC[@]}" "${REPO_ROOT}/tools/cross-aarch64-mesa.txt" \
	"${REPO_ROOT}/tools/egl-probe/egl-probe.c" \
	"${REPO_ROOT}/scripts/remote/build-mesa-aarch64.sh" "${BUILD_HOST}:${TOOLS_DIR}/"

"${SSH[@]}" "cd '${TOOLS_DIR}' && chmod +x build-mesa-aarch64.sh && \
	MESA_VER='${MESA_VER}' SYSROOT='${SYSROOT}' TOOLS_DIR='${TOOLS_DIR}' \
	DEST='${DEST}' CLEAN='${CLEAN}' ./build-mesa-aarch64.sh"

fetch
