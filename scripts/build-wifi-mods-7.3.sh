#!/usr/bin/env bash
#
# build-wifi-mods-7.3.sh — build the MT6631 vendor stack against the Linux 7.3
# Wi-Fi out-tree.
#
# Expects the three work trees already staged and patched:
#   $WIFI_WORK/common  Motorola common + patches/wifi + patches/wifi-7.3
#   $WIFI_WORK/wlan    Motorola wlan-core-gen3 + patches/wifi + patches/wifi-7.3
#   $BTIF_WORK         Rabbit BTIF + m23 glue + patches/wifi-7.3
#
# The kernel out-tree must have been configured with the Wi-Fi fragment and
# built (Image modules dtbs) so that Module.symvers exists.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

KERNEL_SRC="${KERNEL_SRC:-${REPO_ROOT}/../linux-t1100-7.3}"
OUT="${OUT:-${REPO_ROOT}/../build/t1100-7.3-wifi}"
WIFI_WORK="${WIFI_WORK:-/tmp/opencode/wifi-work}"
BTIF_WORK="${BTIF_WORK:-/tmp/opencode/btif-work}"
JOBS="${JOBS:-$(nproc)}"
LOCALVERSION="${LOCALVERSION:--wifi1}"

if [ -z "${CROSS_COMPILE:-}" ]; then
	for tc in "${REPO_ROOT}"/../toolchains/*/bin/aarch64-none-linux-gnu-; do
		[ -x "${tc}gcc" ] && { CROSS_COMPILE="$tc"; break; }
	done
fi
: "${CROSS_COMPILE:?set CROSS_COMPILE or install the arm-gnu toolchain}"
[ -d "$WIFI_WORK/common" ] || { echo "missing $WIFI_WORK/common" >&2; exit 1; }
[ -d "$WIFI_WORK/wlan" ]   || { echo "missing $WIFI_WORK/wlan" >&2; exit 1; }
[ -d "$BTIF_WORK" ]        || { echo "missing $BTIF_WORK" >&2; exit 1; }
[ -f "$OUT/Module.symvers" ] || { echo "missing $OUT/Module.symvers; build the kernel first" >&2; exit 1; }

make_args=(-C "$KERNEL_SRC" O="$OUT" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE"
	   LOCALVERSION="$LOCALVERSION" -j"$JOBS")

echo "== mtk_btif_drv =="
make "${make_args[@]}" M="$BTIF_WORK" modules
echo "== wmt_drv =="
make "${make_args[@]}" KBUILD_EXTRA_SYMBOLS="$BTIF_WORK/Module.symvers" \
	M="$WIFI_WORK/common" modules
echo "== wlan_drv_gen3 =="
make "${make_args[@]}" \
	KBUILD_EXTRA_SYMBOLS="$WIFI_WORK/common/Module.symvers $BTIF_WORK/Module.symvers" \
	M="$WIFI_WORK/wlan" modules

echo "== artifacts =="
ls -l "$BTIF_WORK/mtk_btif_drv.ko" \
      "$WIFI_WORK/common/wmt_drv.ko" \
      "$WIFI_WORK/wlan/wlan_drv_gen3.ko"
sha256sum "$BTIF_WORK/mtk_btif_drv.ko" \
	  "$WIFI_WORK/common/wmt_drv.ko" \
	  "$WIFI_WORK/wlan/wlan_drv_gen3.ko"
