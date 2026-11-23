#!/bin/bash
# Host-side: build the BT module set against an *existing* kernel out-tree
# (default: the wifi out-tree) and, if the wmt build dir is present, the
# t1100_bt HCI driver from the repo's bt/.
#
# Set needed for the 16.11 BT bring-up (see docs/STATUS.md, 16.11 (6)):
#   af_alg, algif_hash, algif_skcipher, algif_aead   (bluetoothd: AF_ALG)
#   ecc, ecdh_generic                                (SMP key derivation)
#   bluetooth, bnep, rfcomm, hidp                    (core + profiles)
#   t1100_bt                                         (HCI over STP/BTIF, wmt_drv)
#
# Same technique as build-kmods-remote.sh: build targets one by one with
# KBUILD_MODPOST_WARN=1 and fold each step's Module.symvers back into the
# objtree table, so the next module sees the previous modules' exports
# (bnep/rfcomm reference bluetooth.ko symbols). CONFIG_MODVERSIONS=n, so the
# CRC column is always 0; dependency order is enforced by modprobe/depmod.
#
# Env:
#   KERNEL_OUT   out-tree to build in (default /home/l/t1100-ubuntu-build/out-wifi)
#   KERNEL_SRC   kernel source tree (default /home/l/t1100-ubuntu-build/src)
#   LOCALVERSION pass ONLY when the out-tree's suffix is not in CONFIG_LOCALVERSION;
#                the script never derives it automatically (a wrong override
#                yields a doubled suffix like -wifi1-wifi1)
#   WIFI_SYM     wmt_drv Module.symvers for t1100_bt
#                (default /home/l/t1100-wifi-build-own48/work/common/Module.symvers;
#                 part 2 is skipped when the file does not exist)
#   BT_SRC       bt/ sources (default /home/l/t1100-ubuntu-build/bt; rsync them
#                from the repo before running)
#   JOBS         default 12
#
# Usage: KERNEL_OUT=/home/l/t1100-ubuntu-build/out-wifi build-bt-kmods-remote.sh
set -u

KERNEL_OUT=${KERNEL_OUT:-/home/l/t1100-ubuntu-build/out-wifi}
KERNEL_SRC=${KERNEL_SRC:-/home/l/t1100-ubuntu-build/src}
WIFI_SYM=${WIFI_SYM:-/home/l/t1100-wifi-build-own48/work/common/Module.symvers}
BT_SRC=${BT_SRC:-/home/l/t1100-ubuntu-build/bt}
LOCALVERSION=${LOCALVERSION-}
JOBS=${JOBS:-12}
for arg in "$@"; do
	case "$arg" in
		-h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown argument: $arg" >&2; exit 2 ;;
	esac
done

[ -d "$KERNEL_OUT" ] || { echo "нет out-дерева $KERNEL_OUT" >&2; exit 1; }
[ -f "$KERNEL_OUT/vmlinux.symvers" ] || {
	echo "нет $KERNEL_OUT/vmlinux.symvers -- out-дерево не собрано (make Image)" >&2
	exit 1; }
grep -q '^CONFIG_BT=m' "$KERNEL_OUT/.config" || {
	echo "в .config нет CONFIG_BT=m (нужен configs/t1100-wifi.fragment)" >&2; exit 1; }

cd "$KERNEL_OUT" || exit 1
export PATH="$HOME/.ccache-bin:$PATH" CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache-t1100}"
MK="make -C $KERNEL_SRC O=$PWD ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-"
# Суффикс обычно живёт в CONFIG_LOCALVERSION (для out-wifi это -wifi1);
# явный LOCALVERSION добавляем только если его передали снаружи.
[ -n "$LOCALVERSION" ] && MK="$MK LOCALVERSION=$LOCALVERSION"

REL_BEFORE=$(cat include/config/kernel.release 2>/dev/null)
echo "kernel out : $KERNEL_OUT"
echo "release    : $REL_BEFORE"

# Order matters for the symvers folding: crypto first, then bluetooth, then
# the profile modules that reference bluetooth's exports.
TARGETS="crypto/af_alg.ko crypto/algif_hash.ko crypto/algif_skcipher.ko \
crypto/algif_aead.ko crypto/ecc.ko crypto/ecdh_generic.ko \
net/bluetooth/bluetooth.ko net/bluetooth/bnep/bnep.ko \
net/bluetooth/rfcomm/rfcomm.ko net/bluetooth/hidp/hidp.ko"
STAMP=$(date +%s)
rc_all=0
for t in $TARGETS; do
	if [ "$(basename "$t" .ko)" = hidp ] && ! grep -q '^CONFIG_BT_HIDP=m' .config; then
		echo "== $t  (пропущено: CONFIG_BT_HIDP != m)"; continue
	fi
	echo "== $t"
	$MK "$t" KBUILD_MODPOST_WARN=1 -j"$JOBS" > "/tmp/btkmods-$(echo "$t" | tr / -).log" 2>&1
	rc=$?
	log=/tmp/btkmods-$(echo "$t" | tr / -).log
	echo "   rc=$rc errors=$(grep -c 'error:' "$log") warnings=$(grep -c 'warning:' "$log") \
undefined=$(grep -c 'undefined!' "$log")"
	[ $rc -ne 0 ] && { rc_all=1; tail -20 "$log"; }
	cp Module.symvers "/tmp/btsymvers-$STAMP-$(basename "$t" .ko).sy" 2>/dev/null
	cat vmlinux.symvers /tmp/btsymvers-"$STAMP"-*.sy \
		| awk -F'\t' '{ if (!seen[$2]++) print }' > /tmp/btsymvers-merged.sy
	mv /tmp/btsymvers-merged.sy Module.symvers
done

REL_AFTER=$(cat include/config/kernel.release 2>/dev/null)
if [ "$REL_AFTER" != "$REL_BEFORE" ]; then
	echo "ОШИБКА: release изменился: '$REL_BEFORE' -> '$REL_AFTER' (LOCALVERSION!)" >&2
	rc_all=1
fi

# Complete table for the out-tree: kernel + every BT module built above.
cat vmlinux.symvers /tmp/btsymvers-"$STAMP"-*.sy \
	| awk -F'\t' '{ if (!seen[$2]++) print }' > Module.symvers
echo "Module.symvers: $(wc -l < Module.symvers) symbols (release $REL_AFTER)"

ALL="$TARGETS"
# --- Часть 2: t1100_bt (HCI over STP/BTIF) из репозитория ---
if [ -d "$BT_SRC" ] && [ -f "$WIFI_SYM" ]; then
	echo "== t1100_bt (KBUILD_EXTRA_SYMBOLS=$WIFI_SYM)"
	$MK M="$BT_SRC" modules KBUILD_EXTRA_SYMBOLS="$WIFI_SYM" \
		KBUILD_MODPOST_WARN=1 -j"$JOBS" > /tmp/btkmods-t1100bt.log 2>&1
	rc=$?
	echo "   rc=$rc errors=$(grep -c 'error:' /tmp/btkmods-t1100bt.log)"
	[ $rc -ne 0 ] && { rc_all=1; tail -20 /tmp/btkmods-t1100bt.log; }
	ALL="$ALL $BT_SRC/t1100_bt.ko $BT_SRC/t1100_bt_probe.ko"
else
	echo "== t1100_bt пропущен (нет $BT_SRC или $WIFI_SYM)"
fi

echo "== .ko"
for t in $ALL; do
	[ -f "$t" ] || { echo "  НЕТ $t"; rc_all=1; continue; }
	v=$(modinfo -F vermagic "$t" 2>/dev/null)
	printf '%s  %10s  %-36s %s\n' "$(sha256sum "$t" | cut -d' ' -f1)" \
		"$(stat -c%s "$t")" "$t" "$v"
done
exit $rc_all
