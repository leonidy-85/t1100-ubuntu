#!/bin/bash
# Host-side: stage and build the MT6771 BTIF driver (M23).
#
# Runs on the build host; driven by scripts/build-btif-remote.sh. The driver
# sources are the public mainline-style port from the Rabbit (mt6765) kernel
# tree, which is a read-only input here -- never edited in place:
#
#   $BTIF_SRC  /home/l/wifi-src/rb/drivers/staging/mtk-connectivity/btif
#
# Layout under $BTIF_DIR (/home/l/m23-btif):
#   <work tree>      pristine copy of the port + patches/wifi/0010-btif-*.patch
#   m23_board.c/.h   our MT6771 glue (scripts/remote/m23-btif/)
#   Makefile         our Kbuild wrapper (scripts/remote/m23-btif/Makefile)
#   Module.symvers   consumed by the wmt_drv build (stp_btif.o calls into it)
#
# Usage: build-btif-remote.sh [--prepare-only]
set -u

BTIF_DIR=${BTIF_DIR:-/home/l/m23-btif}
BTIF_SRC=${BTIF_SRC:-/home/l/wifi-src/rb/drivers/staging/mtk-connectivity/btif}
GLUE=${GLUE:-$BTIF_DIR/glue}
KB=${KERNEL_OUT:-/home/l/t1100-merge2-out}
JOBS=${JOBS:-10}
PREPARE_ONLY=0

[ "${1:-}" = "--prepare-only" ] && PREPARE_ONLY=1

set -e
echo "== stage $BTIF_DIR from $BTIF_SRC =="
mkdir -p "$BTIF_DIR"
rsync -a --delete --exclude '*.o' --exclude '*.ko' --exclude '*.mod*' \
	"$BTIF_SRC/" "$BTIF_DIR/"

# Our glue and Kbuild wrapper.
cp "$GLUE/m23_board.c" "$GLUE/m23_board.h" "$BTIF_DIR/"
cp "$GLUE/Makefile" "$BTIF_DIR/Makefile"

# Our port patches, applied on top of the pristine copy.
if [ -d "$GLUE/patches" ]; then
	for p in "$GLUE"/patches/*.patch; do
		[ -f "$p" ] || continue
		echo "-- apply $(basename "$p")"
		( cd "$BTIF_DIR" && patch -p1 -s --no-backup-if-mismatch < "$p" )
	done
fi
echo "tree ready"

[ "$PREPARE_ONLY" -eq 1 ] && exit 0

LOCALVERSION=${LOCALVERSION:-$(sed -E 's/^[0-9]+\.[0-9]+\.[0-9]+//' \
	"$KB/include/config/kernel.release" 2>/dev/null || true)}
echo "== make -C $KB M=$BTIF_DIR modules (LOCALVERSION='$LOCALVERSION') =="
make -C "$KB" M="$BTIF_DIR" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
	LOCALVERSION="$LOCALVERSION" -j"$JOBS" modules
ls -l "$BTIF_DIR/mtk_btif_drv.ko"
sha256sum "$BTIF_DIR/mtk_btif_drv.ko"
