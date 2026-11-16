#!/usr/bin/env bash
#
# build-fm-remote.sh — собрать вендорский MTK FM-драйвер (gps/) под
# out-дерево ядра на build-хосте и забрать .ko в build/gps/.
#
# Устройство не участвует: build-only.
#
# Env:
#   BUILD_HOST  (default l@172.17.141.172)
#   BUILD_PASS  (default 0)
#   KERNEL_OUT  (default /home/l/t1100-ubuntu-build/out-wifi)
#   KERNEL_SRC  (default /home/l/t1100-ubuntu-build/src-nonwifi)
#   GPS_DIR      (default /home/l/t1100-gps) — рабочая копия gps/ на хосте
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_HOST="${BUILD_HOST:-l@172.17.141.172}"
BUILD_PASS="${BUILD_PASS:-0}"
KERNEL_OUT="${KERNEL_OUT:-/home/l/t1100-ubuntu-build/out-wifi}"
KERNEL_SRC="${KERNEL_SRC:-/home/l/t1100-ubuntu-build/src-nonwifi}"
GPS_DIR="${GPS_DIR:-/home/l/t1100-gps}"
LOCALVERSION="${LOCALVERSION-}"
# mtk_wcn_* экспортируются вендорским wmt_drv, а не ядром
EXTRA_SYMBOLS="${EXTRA_SYMBOLS:-/home/l/t1100-wifi-build/work/common/Module.symvers}"

ssh_cmd() { sshpass -p "$BUILD_PASS" ssh -o StrictHostKeyChecking=no "$BUILD_HOST" "$@"; }

echo "== rsync gps/ -> $BUILD_HOST:$GPS_DIR"
sshpass -p "$BUILD_PASS" ssh -o StrictHostKeyChecking=no "$BUILD_HOST" "mkdir -p '$GPS_DIR'"
rsync -a --delete --exclude '*.ko' --exclude '*.o' --exclude '.*.cmd' \
	-e "sshpass -p $BUILD_PASS ssh -o StrictHostKeyChecking=no" \
	"$REPO_ROOT/gps/" "$BUILD_HOST:$GPS_DIR/"

echo "== build modules against $KERNEL_OUT"
ssh_cmd "cd '$GPS_DIR' && make -C '$KERNEL_SRC' O='$KERNEL_OUT' M='$GPS_DIR' \
	ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION='$LOCALVERSION' \
	KBUILD_EXTRA_SYMBOLS='$EXTRA_SYMBOLS' \
	-j\$(nproc) modules" 2>&1 | tail -40

mkdir -p "$REPO_ROOT/build/gps"
echo "== collect .ko"
sshpass -p "$BUILD_PASS" scp -o StrictHostKeyChecking=no \
	"$BUILD_HOST:$GPS_DIR/*.ko" "$REPO_ROOT/build/gps/" >/dev/null
for f in "$REPO_ROOT"/build/gps/*.ko; do
	printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$(basename "$f")"
done
