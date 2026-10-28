#!/usr/bin/env bash
#
# build_kernel.sh — reproducible arm64 kernel build for Fplus T1100 (MT6771).
#
# Base tree: mainline LTS 6.12.y (see docs/STATUS.md).
# Out-of-tree build dir: <repo>/build/t1100 (gitignored via /build/).
#
# Usage:
#   scripts/build_kernel.sh                # defconfig + Image dtbs modules_prepare
#   scripts/build_kernel.sh --clean        # wipe build dir first
#   scripts/build_kernel.sh --defconfig    # (re)generate .config only
#
# Environment overrides:
#   KERNEL_SRC   path to kernel source tree  (default: /home/l/projects/linux-t1100)
#   OUT          build output dir            (default: <repo>/build/t1100)
#   CROSS_COMPILE prefix                     (default: aarch64-linux-gnu-)
#   ARCH         kernel arch                 (default: arm64)
#   JOBS         parallelism                 (default: 4)
#   KCONFIG      config target               (default: defconfig)
#
# The script fails on the first error (set -euo pipefail) and always reports
# the kernel version plus size/sha256 of Image and every built DTB.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

KERNEL_SRC="${KERNEL_SRC:-/home/l/projects/linux-t1100}"
OUT="${OUT:-${REPO_ROOT}/build/t1100}"
ARCH="${ARCH:-arm64}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
JOBS="${JOBS:-4}"
KCONFIG="${KCONFIG:-defconfig}"

LOG_DIR="${REPO_ROOT}/build/logs"
mkdir -p "${LOG_DIR}"
LOG="${LOG_DIR}/build-$(date +%Y%m%d-%H%M%S).log"

CLEAN=0
CONFIG_ONLY=0
for arg in "$@"; do
	case "${arg}" in
		-c|--clean)     CLEAN=1 ;;
		--defconfig)    CONFIG_ONLY=1 ;;
		-h|--help)      sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown argument: ${arg}" >&2; exit 2 ;;
	esac
done

die() { echo "ERROR: $*" >&2; exit 1; }

echo "== t1100 kernel build =="
echo "repo         : ${REPO_ROOT}"
echo "kernel src   : ${KERNEL_SRC}"
echo "output       : ${OUT}"
echo "arch         : ${ARCH}"
echo "cross        : ${CROSS_COMPILE}"
echo "jobs         : ${JOBS}"
echo "config target: ${KCONFIG}"
echo "log          : ${LOG}"

[ -d "${KERNEL_SRC}" ]        || die "kernel source tree not found: ${KERNEL_SRC}"
[ -f "${KERNEL_SRC}/Makefile" ] || die "no Makefile in ${KERNEL_SRC}"
command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1 \
	|| die "cross compiler not found: ${CROSS_COMPILE}gcc (install gcc-aarch64-linux-gnu)"

KVERSION="$(make -s -C "${KERNEL_SRC}" kernelversion)"
GCCV="$("${CROSS_COMPILE}gcc" --version | head -1)"
DTCV="$(make -s -C "${KERNEL_SRC}" O="${OUT}" ARCH="${ARCH}" dtc-version 2>/dev/null || dtc --version 2>/dev/null || echo unknown)"

echo "kernelversion: ${KVERSION}"
echo "compiler     : ${GCCV}"
echo "dtc          : ${DTCV}"

if [ "${CLEAN}" -eq 1 ]; then
	echo "-- wiping ${OUT}"
	rm -rf "${OUT}"
fi
mkdir -p "${OUT}"

MAKE=(make -C "${KERNEL_SRC}" O="${OUT}" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}")

echo
echo "== ${KCONFIG} =="
"${MAKE[@]}" "${KCONFIG}" 2>&1 | tee -a "${LOG}"

if [ "${CONFIG_ONLY}" -eq 1 ]; then
	echo "config written: ${OUT}/.config"
	exit 0
fi

START=$(date +%s)

echo
echo "== build: Image dtbs modules_prepare (-j${JOBS}) =="
set +e
"${MAKE[@]}" -j"${JOBS}" Image dtbs modules_prepare 2>&1 | tee -a "${LOG}"
RC=${PIPESTATUS[0]}
set -e
END=$(date +%s)
ELAPSED=$((END - START))

if [ "${RC}" -ne 0 ]; then
	echo
	echo "BUILD FAILED (rc=${RC}) after $((ELAPSED / 60))m$((ELAPSED % 60))s" >&2
	echo "--- tail of ${LOG} ---" >&2
	tail -n 60 "${LOG}" >&2
	exit "${RC}"
fi

echo
echo "BUILD OK in $((ELAPSED / 60))m$((ELAPSED % 60))s"

IMAGE="${OUT}/arch/${ARCH}/boot/Image"
DTB_DIR="${OUT}/arch/${ARCH}/boot/dts"
[ -f "${IMAGE}" ] || die "Image not produced: ${IMAGE}"

WARNINGS=$(grep -c 'warning:' "${LOG}" || true)

echo
echo "== result =="
echo "kernelversion : ${KVERSION}"
echo "build time    : $((ELAPSED / 60))m$((ELAPSED % 60))s"
echo "warnings      : ${WARNINGS}"
echo
echo "-- Image --"
ls -l "${IMAGE}"
sha256sum "${IMAGE}"
echo
echo "-- dtbs (mediatek) --"
mapfile -t MEDIATEK_DTBS < <(find "${DTB_DIR}/mediatek" -name '*.dtb' -type f 2>/dev/null | sort)
if [ "${#MEDIATEK_DTBS[@]}" -eq 0 ]; then
	echo "(none)"
else
	ls -l "${MEDIATEK_DTBS[@]}"
	sha256sum "${MEDIATEK_DTBS[@]}"
fi
echo
echo "-- dtbs summary --"
ALL_DTBS=$(find "${DTB_DIR}" -name '*.dtb' -type f | wc -l)
echo "total dtbs built: ${ALL_DTBS} (mediatek: ${#MEDIATEK_DTBS[@]})"
echo "dtbs sha256 list: ${LOG%.log}.dtbs.sha256"
( cd "${DTB_DIR}" && find . -name '*.dtb' -type f | sort | xargs -r sha256sum ) \
	> "${LOG%.log}.dtbs.sha256"

echo
echo "log: ${LOG}"
