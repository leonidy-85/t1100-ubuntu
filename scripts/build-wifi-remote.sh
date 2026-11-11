#!/usr/bin/env bash
#
# build-wifi-remote.sh — собрать вендорский connectivity-стек MT6771
# (`wmt_drv.ko` + `wlan_drv_gen3.ko`) под mainline 6.12 на build-хосте.
#
# Фаза 5 (Wi-Fi/BT, путь A), см. docs/wifi-plan.md §3 и docs/wifi-port-log.md.
# Собираются МОДУЛИ, устройство не участвует: это build-only рубеж.
#
# Что делает:
#   1. rsync наших частей порта (Kbuild-обёртки, compat-заголовки, stub'ы,
#      патчи 4.14 -> 6.12) в /home/l/t1100-wifi-build на хосте;
#   2. если в out-дереве ядра нет Module.symvers — готовит конфиг
#      (defconfig + configs/t1100.fragment + configs/t1100-wifi.fragment) и
#      собирает Image+modules (иначе внешние модули не линкуются);
#   3. на хосте: чистая копия вендорских исходников -> патчи -> make modules;
#   4. печатает rc, число ошибок, sha256/размер полученных .ko.
#
# Ядро (../linux-t1100) не модифицируется: используется out-дерево, собранное
# scripts/build-kernel-remote.sh (src snapshot), а модули — out-of-tree.
#
# Использование:
#   scripts/build-wifi-remote.sh                # подготовить + собрать
#   scripts/build-wifi-remote.sh --prepare      # только разложить/пропатчить
#   scripts/build-wifi-remote.sh --kernel       # (пере)собрать ядро+модули ядра
#   scripts/build-wifi-remote.sh --clean        # снести out/ ядра и work/
#   scripts/build-wifi-remote.sh wlan           # только один модуль
#
# Env:
#   BUILD_HOST  (default l@172.17.141.172)
#   BUILD_PASS  (default 0)
#   WIFI_DIR    (default /home/l/t1100-wifi-build)
#   KERNEL_SRC  (default <repo>/../linux-t1100)  — только для --kernel
#   JOBS        (default: nproc на хосте)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_HOST="${BUILD_HOST:-l@172.17.141.172}"
BUILD_PASS="${BUILD_PASS:-0}"
WIFI_DIR="${WIFI_DIR:-/home/l/t1100-wifi-build}"
KERNEL_SRC="${KERNEL_SRC:-${REPO_ROOT}/../linux-t1100}"
KERNEL_BUILD="${KERNEL_BUILD:-/home/l/t1100-ubuntu-build}"
ARCH="${ARCH:-arm64}"
FRAGMENT="${REPO_ROOT}/configs/t1100.fragment"
WIFI_FRAGMENT="${REPO_ROOT}/configs/t1100-wifi.fragment"

DO_PREPARE=1
DO_BUILD=1
DO_KERNEL=0
CLEAN=0
MODULES=()
for arg in "$@"; do
	case "${arg}" in
		--prepare) DO_BUILD=0 ;;
		--kernel)  DO_KERNEL=1 ;;
		--clean)   CLEAN=1 ;;
		-h|--help) sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
		common|wlan) MODULES+=("${arg}") ;;
		*) echo "unknown argument: ${arg}" >&2; exit 2 ;;
	esac
done

command -v sshpass >/dev/null || { echo "нужен sshpass" >&2; exit 1; }
command -v rsync   >/dev/null || { echo "нужен rsync" >&2; exit 1; }

SSH=(sshpass -p "${BUILD_PASS}" ssh -o StrictHostKeyChecking=no \
	-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${BUILD_HOST}")
RSYNC=(rsync -a --delete -e "sshpass -p ${BUILD_PASS} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null")

LOG_DIR="${REPO_ROOT}/build/logs"
mkdir -p "${LOG_DIR}"
LOG="${LOG_DIR}/wifi-$(date +%Y%m%d-%H%M%S).log"
JOBS="${JOBS:-$("${SSH[@]}" nproc)}"

echo "== t1100 wifi vendor modules (remote) ==" | tee "${LOG}"
echo "host   : ${BUILD_HOST}" | tee -a "${LOG}"
echo "wifi   : ${WIFI_DIR}" | tee -a "${LOG}"
echo "jobs   : ${JOBS}" | tee -a "${LOG}"
echo "log    : ${LOG}" | tee -a "${LOG}"

"${SSH[@]}" "mkdir -p '${WIFI_DIR}'/{out,work,logs,kbuild,compat,stubs,wifi-patches,vendor}" </dev/null

if [ "${CLEAN}" -eq 1 ]; then
	echo "-- clean: сношу out/ ядра и work/" | tee -a "${LOG}"
	"${SSH[@]}" "rm -rf '${WIFI_DIR}/out' '${WIFI_DIR}/work'" </dev/null
	exit 0
fi

echo
echo "== rsync: наш порт (kbuild, compat, stubs, патчи) ==" | tee -a "${LOG}"
"${RSYNC[@]}" "${REPO_ROOT}/scripts/remote/wifi-kbuild/"   "${BUILD_HOST}:${WIFI_DIR}/kbuild/"       2>&1 | tee -a "${LOG}"
"${RSYNC[@]}" "${REPO_ROOT}/scripts/remote/wifi-compat/"   "${BUILD_HOST}:${WIFI_DIR}/compat/include/" 2>&1 | tee -a "${LOG}"
"${RSYNC[@]}" "${REPO_ROOT}/scripts/remote/wifi-stubs/"    "${BUILD_HOST}:${WIFI_DIR}/stubs/"         2>&1 | tee -a "${LOG}"
"${RSYNC[@]}" --exclude='*.orig' "${REPO_ROOT}/patches/wifi/" "${BUILD_HOST}:${WIFI_DIR}/wifi-patches/" 2>&1 | tee -a "${LOG}"

# Вендорские клоны — вход для патчей; кладём их на хост, если их там нет.
if ! "${SSH[@]}" "test -d '${WIFI_DIR}/vendor/wlan/include'" </dev/null; then
	echo "-- вендорские исходники на хосте отсутствуют, копирую из ${WIFI_DIR%/t1100-wifi-build}/t1100-wifi-src/vendor" | tee -a "${LOG}"
	SRC_VENDOR="/home/l/t1100-wifi-src/vendor/mediatek/kernel_modules/connectivity"
	"${SSH[@]}" "test -d '${SRC_VENDOR}/wlan'" </dev/null || {
		echo "нет ${SRC_VENDOR} на хосте (клоны из майлстоуна 1)" >&2; exit 1; }
	"${SSH[@]}" "cp -a '${SRC_VENDOR}/common' '${SRC_VENDOR}/wlan' '${WIFI_DIR}/vendor/'" </dev/null
fi

if [ "${DO_KERNEL}" -eq 1 ] || ! "${SSH[@]}" "test -f '${WIFI_DIR}/out/Module.symvers'" </dev/null; then
	echo
	echo "== kernel: конфиг + Image + modules (нужен Module.symvers) ==" | tee -a "${LOG}"
	"${RSYNC[@]}" "${FRAGMENT}"       "${BUILD_HOST}:${WIFI_DIR}/fragment-base.config" 2>&1 | tee -a "${LOG}"
	"${RSYNC[@]}" "${WIFI_FRAGMENT}"  "${BUILD_HOST}:${WIFI_DIR}/fragment-wifi.config" 2>&1 | tee -a "${LOG}"
	LOCALVERSION=""
	if git -C "${KERNEL_SRC}" rev-parse --git-dir >/dev/null 2>&1; then
		LOCALVERSION="-g$(git -C "${KERNEL_SRC}" rev-parse --short=10 HEAD)"
		if ! git -C "${KERNEL_SRC}" diff --quiet || ! git -C "${KERNEL_SRC}" diff --cached --quiet; then
			LOCALVERSION="${LOCALVERSION}-dirty"
		fi
	fi
	SRC="${KERNEL_BUILD}/src"
	"${SSH[@]}" "set -e
		export CCACHE_DIR=\$HOME/.ccache-t1100 PATH=\$HOME/.ccache-bin:\$PATH
		cd '${WIFI_DIR}'
		MK='make -C ${SRC} O=${WIFI_DIR}/out ARCH=${ARCH} CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION=${LOCALVERSION}'
		\$MK defconfig
		[ -f fragment-base.config ] && ${SRC}/scripts/kconfig/merge_config.sh -m -O out out/.config fragment-base.config >/dev/null
		${SRC}/scripts/kconfig/merge_config.sh -m -O out out/.config fragment-wifi.config >/dev/null
		\$MK olddefconfig
		\$MK -j${JOBS} Image modules" 2>&1 | tee -a "${LOG}"
fi

PREP_FLAG=""
[ "${DO_BUILD}" -eq 0 ] && PREP_FLAG="--prepare-only"
echo
echo "== подготовка/сборка вендорских модулей${PREP_FLAG:+ (только prepare)} ==" | tee -a "${LOG}"
"${RSYNC[@]}" "${REPO_ROOT}/scripts/remote/build-wifi-remote.sh" "${BUILD_HOST}:${WIFI_DIR}/build-modules.sh" 2>&1 | tee -a "${LOG}"
"${SSH[@]}" "chmod +x '${WIFI_DIR}/build-modules.sh' && WIFI_DIR='${WIFI_DIR}' JOBS=${JOBS} '${WIFI_DIR}/build-modules.sh' ${PREP_FLAG} ${MODULES[*]:-}" 2>&1 | tee -a "${LOG}"

echo
echo "== забираю .ko в build/wifi/ ==" | tee -a "${LOG}"
mkdir -p "${REPO_ROOT}/build/wifi"
"${RSYNC[@]}" --include='*/' --include='*.ko' --exclude='*' --prune-empty-dirs \
	"${BUILD_HOST}:${WIFI_DIR}/work/" "${REPO_ROOT}/build/wifi/" 2>&1 | tee -a "${LOG}"
find "${REPO_ROOT}/build/wifi" -name '*.ko' -printf '%s\t%p\n' 2>/dev/null | tee -a "${LOG}"
