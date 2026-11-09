#!/usr/bin/env bash
#
# build-tools-aarch64.sh — собрать aarch64 userspace-утилиты на build-хосте.
#
# Зачем: на планшете (Ubuntu 24.04 arm64, без сети) нет пакетов вроде
# `modetest`, а apt там недоступен. Собираем статические бинарники
# кросс-компилятором на 172.17.141.172 и кладём в build/tools-aarch64/,
# оттуда — scp на планшет.
#
# Использование:
#   scripts/build-tools-aarch64.sh            # собрать всё, что можно сейчас
#   scripts/build-tools-aarch64.sh modetest   # только modetest
#   scripts/build-tools-aarch64.sh --list
#
# Env:
#   BUILD_HOST (default l@172.17.141.172)   BUILD_PASS (default 0)
#   LIBDRM_VER (default 2.4.131)
#   REMOTE_DIR (default /home/l/t1100-tools)
#   LOCAL_OUT  (default <repo>/build/tools-aarch64)
#
# Что собирается и почему:
#   modetest — из libdrm (`tests/modetest`), нужен только libdrm: проверка KMS
#              (фаза 2). Статическая линковка: на планшете нет libdrm.so.
#   kmscube  — НЕ собирается: требует GBM/EGL/GLESv2, то есть собранной под
#              aarch64 Mesa и работающего panfrost (фаза 3).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_HOST="${BUILD_HOST:-l@172.17.141.172}"
BUILD_PASS="${BUILD_PASS:-0}"
LIBDRM_VER="${LIBDRM_VER:-2.4.131}"
REMOTE_DIR="${REMOTE_DIR:-/home/l/t1100-tools}"
LOCAL_OUT="${LOCAL_OUT:-${REPO_ROOT}/build/tools-aarch64}"

WANT=("$@")
[ ${#WANT[@]} -eq 0 ] && WANT=(modetest)
for w in "${WANT[@]}"; do
	case "$w" in
		--list) echo "доступно: modetest (kmscube — после panfrost, фаза 3)"; exit 0 ;;
		modetest) ;;
		*) echo "неизвестная цель: $w (см. --list)" >&2; exit 2 ;;
	esac
done

command -v sshpass >/dev/null || { echo "нужен sshpass" >&2; exit 1; }
SSH=(sshpass -p "${BUILD_PASS}" ssh -o StrictHostKeyChecking=no \
	-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${BUILD_HOST}")
SCP=(sshpass -p "${BUILD_PASS}" scp -o StrictHostKeyChecking=no \
	-o UserKnownHostsFile=/dev/null)

mkdir -p "${LOCAL_OUT}"

echo "== t1100 userspace tools (aarch64, build host) =="
echo "host    : ${BUILD_HOST}"
echo "libdrm  : ${LIBDRM_VER}"
echo "remote  : ${REMOTE_DIR}"
echo "out     : ${LOCAL_OUT}"

"${SSH[@]}" "REMOTE_DIR='${REMOTE_DIR}' LIBDRM_VER='${LIBDRM_VER}' bash -s" <<'REMOTE'
set -euo pipefail
mkdir -p "${REMOTE_DIR}"
cd "${REMOTE_DIR}"

[ -f "libdrm-${LIBDRM_VER}.tar.xz" ] ||
	curl -fsSLO "https://dri.freedesktop.org/libdrm/libdrm-${LIBDRM_VER}.tar.xz"
rm -rf "libdrm-${LIBDRM_VER}" build-libdrm
tar -xf "libdrm-${LIBDRM_VER}.tar.xz"

cat > cross-aarch64.txt <<'XFILE'
[binaries]
c = 'aarch64-linux-gnu-gcc'
ar = 'aarch64-linux-gnu-ar'
strip = 'aarch64-linux-gnu-strip'
pkg-config = 'pkg-config'

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
XFILE

meson setup build-libdrm "libdrm-${LIBDRM_VER}" \
	--cross-file cross-aarch64.txt \
	--buildtype=release \
	-Ddefault_library=static \
	-Dtests=true -Dman-pages=disabled -Dvalgrind=disabled \
	-Dcairo-tests=disabled -Dudev=false \
	-Dc_args='-static' -Dc_link_args='-static' > meson-setup.log 2>&1 || {
		echo '--- meson setup failed:'; tail -25 meson-setup.log; exit 1; }

ninja -C build-libdrm > ninja.log 2>&1 || {
	echo '--- ninja failed:'; tail -25 ninja.log; exit 1; }

bin=$(find build-libdrm -type f -name modetest | head -1)
[ -n "${bin}" ] || { echo '--- modetest не найден после сборки'; exit 1; }
ls -l "${bin}"
file "${bin}" || true
printf '%s\n' "${PWD}/${bin}" > modetest.path
REMOTE

remote_bin="$("${SSH[@]}" "cat '${REMOTE_DIR}/modetest.path'")"
"${SCP[@]}" "${BUILD_HOST}:${remote_bin}" "${LOCAL_OUT}/" 2>&1 | tail -2

echo
echo "== результат =="
file "${LOCAL_OUT}/modetest"
ls -l "${LOCAL_OUT}/modetest"
sha256sum "${LOCAL_OUT}/modetest" | tee "${LOCAL_OUT}/modetest.sha256"
echo
echo "Установка на планшет (когда он на связи):"
echo "  scp ${LOCAL_OUT}/modetest root@10.42.66.66:/root/ && ssh root@10.42.66.66 chmod +x /root/modetest"
