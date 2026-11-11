#!/usr/bin/env bash
#
# build-kernel-remote.sh — собрать ядро на build-хосте и забрать артефакты.
#
# Зачем: локальная машина (T480, 4 ядра) делит CPU с другими проектами, полная
# сборка ядра занимала часы. Build-хост — 12 ядер, отдельная машина:
#
#   host: 172.17.141.172   user: l   password: 0
#
# Использование:
#   scripts/build-kernel-remote.sh              # инкрементально (rsync + make)
#   scripts/build-kernel-remote.sh --clean      # снести out/ на хосте
#   scripts/build-kernel-remote.sh --config     # только конфиг
#   scripts/build-kernel-remote.sh --modules    # дополнительно собрать modules (cfg80211/mac80211/rfkill)
#
# Env:
#   BUILD_HOST   (default l@172.17.141.172)
#   BUILD_PASS   (default 0)
#   KERNEL_SRC   (default <repo>/../linux-t1100)
#   REMOTE_DIR   (default /home/l/t1100-ubuntu-build)
#   JOBS         (default: nproc удалённого хоста)
#   ARCH         (default arm64)
#   FRAGMENT     (default <repo>/configs/t1100.fragment)
#   EXTRA_FRAGMENTS (default: пусто) — доп. фрагменты через пробел, мержатся
#                  после FRAGMENT (например configs/t1100-wifi.fragment)
#
# Что делает:
#   1. rsync дерева ядра (без .git) и фрагмента конфига на хост;
#   2. на хосте: defconfig -> merge_config(fragment[, EXTRA_FRAGMENTS]) ->
#      olddefconfig -> Image dtbs [modules];
#   3. забирает Image + dtb в <repo>/build/remote/ и печатает версию/sha256.
#
# Кросс-компилятор на хосте: sudo apt-get install -y --no-install-recommends \
#   gcc-aarch64-linux-gnu libssl-dev bison flex libelf-dev rsync
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BUILD_HOST="${BUILD_HOST:-l@172.17.141.172}"
BUILD_PASS="${BUILD_PASS:-0}"
KERNEL_SRC="${KERNEL_SRC:-${REPO_ROOT}/../linux-t1100}"
REMOTE_DIR="${REMOTE_DIR:-/home/l/t1100-ubuntu-build}"
ARCH="${ARCH:-arm64}"
FRAGMENT="${FRAGMENT-${REPO_ROOT}/configs/t1100.fragment}"
# Дополнительные фрагменты (через пробел), мержатся после FRAGMENT.
# Нужны, например, для образа с вендорским Wi-Fi-стеком: модули
# wlan_drv_gen3/wmt_drv собраны с CONFIG_WEXT_PRIV=y + NL80211_TESTMODE=y, и
# ядро, в которое их будут грузить, должно иметь те же header-visible
# структуры (docs/wifi-port-log.md §16) — иначе cfg80211.ko из другого
# out-дерева не совпадёт по ABI.
EXTRA_FRAGMENTS="${EXTRA_FRAGMENTS:-}"
LOCAL_OUT="${LOCAL_OUT:-${REPO_ROOT}/build/remote}"

CLEAN=0
CONFIG_ONLY=0
WITH_MODULES=0
for arg in "$@"; do
	case "${arg}" in
		-c|--clean)  CLEAN=1 ;;
		--config)    CONFIG_ONLY=1 ;;
		--modules)   WITH_MODULES=1 ;;
		-h|--help)   sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown argument: ${arg}" >&2; exit 2 ;;
	esac
done

command -v sshpass >/dev/null || { echo "нужен sshpass" >&2; exit 1; }
command -v rsync   >/dev/null || { echo "нужен rsync" >&2; exit 1; }
[ -d "${KERNEL_SRC}" ] || { echo "нет дерева ядра: ${KERNEL_SRC}" >&2; exit 1; }

SSH=(sshpass -p "${BUILD_PASS}" ssh -o StrictHostKeyChecking=no \
	-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${BUILD_HOST}")
RSYNC=(rsync -a --delete -e "sshpass -p ${BUILD_PASS} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null")

LOG_DIR="${REPO_ROOT}/build/logs"
mkdir -p "${LOG_DIR}" "${LOCAL_OUT}"
LOG="${LOG_DIR}/build-remote-$(date +%Y%m%d-%H%M%S).log"

JOBS="${JOBS:-$("${SSH[@]}" nproc)}"

echo "== t1100 kernel build (remote) =="
echo "host   : ${BUILD_HOST}"
echo "src    : ${KERNEL_SRC}"
echo "remote : ${REMOTE_DIR} (src/ + out/)"
echo "jobs   : ${JOBS}"
echo "log    : ${LOG}"

"${SSH[@]}" "mkdir -p '${REMOTE_DIR}'"

echo
echo "== rsync: дерево ядра (без .git) и фрагмент конфига =="
"${RSYNC[@]}" --exclude='.git' --exclude='*.cmd' --exclude='*.o' \
	"${KERNEL_SRC}/" "${BUILD_HOST}:${REMOTE_DIR}/src/" 2>&1 | tee -a "${LOG}"
if [ -n "${FRAGMENT}" ] && [ -f "${FRAGMENT}" ]; then
	"${RSYNC[@]}" "${FRAGMENT}" "${BUILD_HOST}:${REMOTE_DIR}/fragment.config" 2>&1 | tee -a "${LOG}"
fi
EXTRA_LIST=""
i=0
for extra in ${EXTRA_FRAGMENTS}; do
	[ -f "${extra}" ] || { echo "нет фрагмента: ${extra}" >&2; exit 1; }
	i=$((i + 1))
	EXTRA_LIST="${EXTRA_LIST} fragment-extra-${i}.config"
	"${RSYNC[@]}" "${extra}" "${BUILD_HOST}:${REMOTE_DIR}/fragment-extra-${i}.config" 2>&1 | tee -a "${LOG}"
done

if [ "${CLEAN}" -eq 1 ]; then
	echo "-- wiping remote out/"
	"${SSH[@]}" "rm -rf '${REMOTE_DIR}/out'"
fi

# .git не синхронизируется, поэтому версия ядра иначе была бы просто 6.12.114.
# Передаём LOCALVERSION как в локальной сборке: -g<sha>[-dirty].
LOCALVERSION=""
if git -C "${KERNEL_SRC}" rev-parse --git-dir >/dev/null 2>&1; then
	LOCALVERSION="-g$(git -C "${KERNEL_SRC}" rev-parse --short=10 HEAD)"
	if ! git -C "${KERNEL_SRC}" diff --quiet || ! git -C "${KERNEL_SRC}" diff --cached --quiet; then
		LOCALVERSION="${LOCALVERSION}-dirty"
	fi
fi
echo "localversion: ${LOCALVERSION:-<нет>}"

# ccache на хосте: при правке пары файлов пересборка становится секундами.
# Меняется командная строка компилятора, поэтому первый прогон всё равно полный.
# ccache через маскировку: в ~/.ccache-bin лежит симлинк с именем кросс-gcc на
# ccache, каталог ставится первым в PATH. Форма CC="ccache <gcc>" не работает —
# kbuild/ccache ругаются "unknown C compiler".
if "${SSH[@]}" "command -v ccache >/dev/null 2>&1"; then
	"${SSH[@]}" 'mkdir -p ~/.ccache-bin && ln -sf "$(command -v ccache)" ~/.ccache-bin/aarch64-linux-gnu-gcc'
	echo "ccache : включён (masquerade ~/.ccache-bin, CCACHE_DIR=~/.ccache-t1100)"
else
	echo "ccache : не найден на хосте, собираю без него"
fi

MAKE=(make -C "${REMOTE_DIR}/src" O="${REMOTE_DIR}/out" ARCH="${ARCH}"
	CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION="${LOCALVERSION}")

echo
echo "== defconfig + fragment + olddefconfig =="
"${SSH[@]}" "export CCACHE_DIR=\$HOME/.ccache-t1100 PATH=\$HOME/.ccache-bin:\$PATH; set -e
	cd '${REMOTE_DIR}'
	${MAKE[*]} defconfig
	if [ -f fragment.config ]; then
		src/scripts/kconfig/merge_config.sh -m -O out out/.config fragment.config
	fi
	for extra in ${EXTRA_LIST}; do
		src/scripts/kconfig/merge_config.sh -m -O out out/.config "\$extra"
	done
	${MAKE[*]} olddefconfig
	${MAKE[*]} -s kernelversion" 2>&1 | tee -a "${LOG}"

if [ "${CONFIG_ONLY}" -eq 1 ]; then
	echo "-- только конфиг, выхожу"
	"${SSH[@]}" "grep -cE '=y|=m' '${REMOTE_DIR}/out/.config'" | tee -a "${LOG}"
	exit 0
fi

echo
echo "== make Image dtbs${WITH_MODULES:+ modules} (-j${JOBS}) =="
TARGETS="Image dtbs"
[ "${WITH_MODULES}" -eq 1 ] && TARGETS="${TARGETS} modules"
"${SSH[@]}" "export CCACHE_DIR=\$HOME/.ccache-t1100 PATH=\$HOME/.ccache-bin:\$PATH; set -e
	cd '${REMOTE_DIR}'
	${MAKE[*]} -j${JOBS} ${TARGETS}" 2>&1 | tee -a "${LOG}"

echo
echo "== забираю артефакты в ${LOCAL_OUT} =="
"${RSYNC[@]}" "${BUILD_HOST}:${REMOTE_DIR}/out/arch/arm64/boot/Image" "${LOCAL_OUT}/" 2>&1 | tee -a "${LOG}"
if "${SSH[@]}" "test -d '${REMOTE_DIR}/out/arch/arm64/boot/dts/mediatek'" 2>/dev/null; then
	"${RSYNC[@]}" "${BUILD_HOST}:${REMOTE_DIR}/out/arch/arm64/boot/dts/mediatek/" \
		"${LOCAL_OUT}/dtbs/" 2>&1 | tee -a "${LOG}"
fi
if [ "${WITH_MODULES}" -eq 1 ]; then
	# Wireless core modules of *this* out-tree: they must come from the same
	# config as the vendor modules (WEXT_PRIV/NL80211_TESTMODE change the
	# header-visible cfg80211 structures, see docs/wifi-port-log.md §16).
	mkdir -p "${LOCAL_OUT}/modules"
	for ko in net/wireless/cfg80211.ko net/mac80211/mac80211.ko net/rfkill/rfkill.ko; do
		"${RSYNC[@]}" "${BUILD_HOST}:${REMOTE_DIR}/out/${ko}" "${LOCAL_OUT}/modules/" 2>&1 | tee -a "${LOG}"
	done
fi

echo
echo "== результат =="
ls -l "${LOCAL_OUT}/Image"
sha256sum "${LOCAL_OUT}/Image" | tee "${LOCAL_OUT}/Image.sha256"
if [ "${WITH_MODULES}" -eq 1 ]; then
	sha256sum "${LOCAL_OUT}"/modules/*.ko
fi
"${SSH[@]}" "cat '${REMOTE_DIR}/out/include/config/kernel.release'" | sed 's/^/kernel release: /'
