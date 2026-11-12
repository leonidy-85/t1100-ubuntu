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
#   scripts/build-wifi-remote.sh --kernel-mods  # ядерные модули + Module.symvers
#                                               # из готового out-дерева
#   scripts/build-wifi-remote.sh --clean        # снести out/ ядра и work/
#   scripts/build-wifi-remote.sh wlan           # только один модуль
#
# Env:
#   BUILD_HOST  (default l@172.17.141.172)
#   BUILD_PASS  (default 0)
#   WIFI_DIR    (default /home/l/t1100-wifi-build)
#   KERNEL_OUT  (default $WIFI_DIR/out) — против какого out-дерева линковать;
#               чужое дерево (например out-normal второго разработчика) требует
#               --kernel-mods и LOCALVERSION из его kernel.release
#   LOCALVERSION — суффикс релиза. Обязателен для чужого out-дерева: make
#               перегенерирует include/config/kernel.release на каждом запуске,
#               и без суффикса модули получают неверный vermagic
#   KERNEL_SRC  (default <repo>/../linux-t1100)  — только для --kernel
#   JOBS        (default: nproc на хосте)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_HOST="${BUILD_HOST:-l@172.17.141.172}"
BUILD_PASS="${BUILD_PASS:-0}"
WIFI_DIR="${WIFI_DIR:-/home/l/t1100-wifi-build}"
# Out-tree of the kernel the modules must link against. Default = the tree
# scripts/build-kernel-remote.sh fills; KERNEL_OUT points the module build at
# another tree (e.g. /home/l/t1100-wifi-build/out-norm — the second developer's
# out-normal, release 6.12.114-g400cb6f-touch-rot, see docs/wifi-port-log.md
# "M3: модули под -touch-rot").
KERNEL_OUT="${KERNEL_OUT:-${WIFI_DIR}/out}"
# LOCALVERSION must be passed to *every* make invocation on the out-tree:
# include/config/kernel.release is regenerated on each run (filechk+FORCE), and
# without it the release silently collapses to the bare 6.12.114, which changes
# the module vermagic. Empty = derive from the out-tree's kernel.release.
LOCALVERSION="${LOCALVERSION-}"
KERNEL_SRC="${KERNEL_SRC:-${REPO_ROOT}/../linux-t1100}"
KERNEL_BUILD="${KERNEL_BUILD:-/home/l/t1100-ubuntu-build}"
ARCH="${ARCH:-arm64}"
FRAGMENT="${REPO_ROOT}/configs/t1100.fragment"
WIFI_FRAGMENT="${REPO_ROOT}/configs/t1100-wifi.fragment"

DO_PREPARE=1
DO_BUILD=1
DO_KERNEL=0
DO_KMODS=0
CLEAN=0
MODULES=()
for arg in "$@"; do
	case "${arg}" in
		--prepare) DO_BUILD=0 ;;
		--kernel)  DO_KERNEL=1 ;;
		--kernel-mods) DO_KMODS=1 ;;
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

if [ "${DO_KERNEL}" -eq 1 ] || { ! "${SSH[@]}" "test -f '${KERNEL_OUT}/Module.symvers'" </dev/null && [ "${DO_KMODS}" -eq 0 ]; }; then
	if [ "${KERNEL_OUT}" != "${WIFI_DIR}/out" ] && [ "${DO_KERNEL}" -eq 0 ]; then
		echo "нет ${KERNEL_OUT}/Module.symvers, а это внешнее out-дерево" >&2
		echo "(своё ядро собирается только в ${WIFI_DIR}/out; см. --kernel)" >&2
		exit 1
	fi
	echo
	echo "== kernel: конфиг + Image + modules (нужен Module.symvers) ==" | tee -a "${LOG}"
	"${RSYNC[@]}" "${FRAGMENT}"       "${BUILD_HOST}:${WIFI_DIR}/fragment-base.config" 2>&1 | tee -a "${LOG}"
	"${RSYNC[@]}" "${WIFI_FRAGMENT}"  "${BUILD_HOST}:${WIFI_DIR}/fragment-wifi.config" 2>&1 | tee -a "${LOG}"
	LOCALVERSION="${LOCALVERSION-}"
	if [ -z "${LOCALVERSION}" ] && git -C "${KERNEL_SRC}" rev-parse --git-dir >/dev/null 2>&1; then
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

if [ "${DO_KMODS}" -eq 1 ]; then
	# Ядерные модули (rfkill/libarc4/cfg80211/mac80211) + полный Module.symvers
	# из существующего out-дерева: нужны, когда модули линкуются к чужому ядру.
	# CONFIG_NL80211_TESTMODE включается автоматически, если его нет в конфиге
	# (иначе вендорский wlan собирается с другим layout `struct cfg80211_ops`).
	TM_FLAG=""
	if ! "${SSH[@]}" "grep -q '^CONFIG_NL80211_TESTMODE=y' '${KERNEL_OUT}/.config'" </dev/null; then
		TM_FLAG="--enable-testmode"
	fi
	echo
	echo "== ядерные модули + Module.symvers из ${KERNEL_OUT} ${TM_FLAG} ==" | tee -a "${LOG}"
	"${RSYNC[@]}" "${REPO_ROOT}/scripts/remote/build-kmods-remote.sh" \
		"${BUILD_HOST}:${WIFI_DIR}/build-kmods.sh" 2>&1 | tee -a "${LOG}"
	"${SSH[@]}" "chmod +x '${WIFI_DIR}/build-kmods.sh' && KERNEL_OUT='${KERNEL_OUT}' KERNEL_SRC='${KERNEL_BUILD}/src' LOCALVERSION='${LOCALVERSION}' JOBS=${JOBS} '${WIFI_DIR}/build-kmods.sh' ${TM_FLAG}" 2>&1 | tee -a "${LOG}"
fi
echo
echo "== подготовка/сборка вендорских модулей${PREP_FLAG:+ (только prepare)} ==" | tee -a "${LOG}"
"${RSYNC[@]}" "${REPO_ROOT}/scripts/remote/build-wifi-remote.sh" "${BUILD_HOST}:${WIFI_DIR}/build-modules.sh" 2>&1 | tee -a "${LOG}"
"${SSH[@]}" "chmod +x '${WIFI_DIR}/build-modules.sh' && WIFI_DIR='${WIFI_DIR}' KERNEL_OUT='${KERNEL_OUT}' LOCALVERSION='${LOCALVERSION}' JOBS=${JOBS} '${WIFI_DIR}/build-modules.sh' ${PREP_FLAG} ${MODULES[*]:-}" 2>&1 | tee -a "${LOG}"

echo
echo "== забираю .ko в build/wifi/ ==" | tee -a "${LOG}"
mkdir -p "${REPO_ROOT}/build/wifi"
"${RSYNC[@]}" --include='*/' --include='*.ko' --exclude='*' --prune-empty-dirs \
	"${BUILD_HOST}:${WIFI_DIR}/work/" "${REPO_ROOT}/build/wifi/" 2>&1 | tee -a "${LOG}"
if [ "${DO_KMODS}" -eq 1 ]; then
	# ядерные модули — рядом, в build/wifi/kernel/ (deploy берёт их оттуда)
	mkdir -p "${REPO_ROOT}/build/wifi/kernel"
	for ko in net/rfkill/rfkill.ko lib/crypto/libarc4.ko \
		  net/wireless/cfg80211.ko net/mac80211/mac80211.ko; do
		"${RSYNC[@]}" "${BUILD_HOST}:${KERNEL_OUT}/${ko}" \
			"${REPO_ROOT}/build/wifi/kernel/" 2>>"${LOG}"
	done
fi
find "${REPO_ROOT}/build/wifi" -name '*.ko' -printf '%s\t%p\n' 2>/dev/null | tee -a "${LOG}"
