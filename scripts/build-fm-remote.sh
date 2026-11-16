#!/usr/bin/env bash
#
# build-fm-remote.sh — собрать вендорский MTK FM-драйвер (fmradio/) под
# out-дерево ядра на build-хосте и забрать .ko в build/fm/.
#
# Устройство не участвует: build-only.
#
# Env:
#   BUILD_HOST  (default l@172.17.141.172)
#   BUILD_PASS  (default 0)
#   KERNEL_OUT  (default /home/l/t1100-ubuntu-build/out-wifi)
#   KERNEL_SRC  (default /home/l/t1100-ubuntu-build/src-nonwifi)
#   FM_DIR      (default /home/l/t1100-fm) — рабочая копия fmradio/ на хосте
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_HOST="${BUILD_HOST:-l@172.17.141.172}"
BUILD_PASS="${BUILD_PASS:-0}"
KERNEL_OUT="${KERNEL_OUT:-/home/l/t1100-ubuntu-build/out-wifi}"
KERNEL_SRC="${KERNEL_SRC:-/home/l/t1100-ubuntu-build/src-nonwifi}"
FM_DIR="${FM_DIR:-/home/l/t1100-fm}"
LOCALVERSION="${LOCALVERSION-}"
# mtk_wcn_* экспортируются вендорским wmt_drv, а не ядром
EXTRA_SYMBOLS="${EXTRA_SYMBOLS:-/home/l/t1100-wifi-build/work/common/Module.symvers}"

ssh_cmd() { sshpass -p "$BUILD_PASS" ssh -o StrictHostKeyChecking=no "$BUILD_HOST" "$@"; }

echo "== rsync fmradio/ -> $BUILD_HOST:$FM_DIR"
sshpass -p "$BUILD_PASS" ssh -o StrictHostKeyChecking=no "$BUILD_HOST" "mkdir -p '$FM_DIR'"
rsync -a --delete --exclude '*.ko' --exclude '*.o' --exclude '.*.cmd' \
	-e "sshpass -p $BUILD_PASS ssh -o StrictHostKeyChecking=no" \
	"$REPO_ROOT/fmradio/" "$BUILD_HOST:$FM_DIR/"

echo "== build modules against $KERNEL_OUT"
ssh_cmd "cd '$FM_DIR' && make -C '$KERNEL_SRC' O='$KERNEL_OUT' M='$FM_DIR' \
	ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION='$LOCALVERSION' \
	KBUILD_EXTRA_SYMBOLS='$EXTRA_SYMBOLS' \
	-j\$(nproc) modules" 2>&1 | tail -40

mkdir -p "$REPO_ROOT/build/fm"
echo "== collect .ko"
sshpass -p "$BUILD_PASS" scp -o StrictHostKeyChecking=no \
	"$BUILD_HOST:$FM_DIR/*.ko" "$REPO_ROOT/build/fm/" >/dev/null
for f in "$REPO_ROOT"/build/fm/*.ko; do
	printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$(basename "$f")"
done
