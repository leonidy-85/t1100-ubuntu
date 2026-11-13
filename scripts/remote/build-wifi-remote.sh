#!/bin/bash
# Host-side: prepare the vendor trees and build the connectivity modules.
#
# Runs on the build host (172.17.141.172); driven by
# scripts/build-wifi-remote.sh from the repo. Everything happens outside both
# git trees: ../linux-t1100 is never modified, the vendor sources are a
# throw-away copy rebuilt from the pristine clones on every run.
#
# Layout under $WIFI_DIR (/home/l/t1100-wifi-build):
#   vendor/{common,wlan}     pristine Motorola Pie-9 clones (read-only input)
#   wifi-patches/*.patch     our 4.14 -> 6.12 port, applied with `patch -p1`
#   kbuild/*.Kbuild          our Kbuild wrappers (replace the vendor Makefiles)
#   compat/include/          our compat/stub headers (force-included)
#   stubs/                   our stub .c files (MTK-only subsystems)
#   work/{common,wlan}       what actually gets compiled
#   out/                     kernel out-tree (Module.symvers comes from here)
#   logs/
#
# Usage: build-wifi-remote.sh [--prepare-only] [module ...]
set -u

WIFI_DIR=${WIFI_DIR:-/home/l/t1100-wifi-build}
# Kernel out-tree the modules are linked against. Defaults to the out-tree this
# script's companion kernel build produced; KERNEL_OUT points it at somebody
# else's tree (e.g. out-normal of the second developer, see docs/wifi-port-log.md
# "M3: модули под -touch-rot"). It must have Module.symvers and the same
# UTS_RELEASE as the kernel that runs on the device.
KB=${KERNEL_OUT:-${WIFI_DIR}/out}
LOG=${WIFI_DIR}/logs
JOBS=${JOBS:-10}
LOCALVERSION=${LOCALVERSION-}
PREPARE_ONLY=0
MODULES=""

for arg in "$@"; do
	case "$arg" in
		--prepare-only) PREPARE_ONLY=1 ;;
		*) MODULES="$MODULES $arg" ;;
	esac
done
MODULES=${MODULES:-common wlan}

mkdir -p "$LOG" || exit 1

echo "== prepare work trees =="
for m in common wlan; do
	# Keep the symbol table of a previous build: --delete would wipe it, and
	# a single-module run (e.g. "build wlan") still needs the other module's
	# Module.symvers for modpost.
	[ -f "$WIFI_DIR/work/$m/Module.symvers" ] && \
		cp "$WIFI_DIR/work/$m/Module.symvers" "$WIFI_DIR/.symvers-$m.saved"
	rsync -a --delete "$WIFI_DIR/vendor/$m/" "$WIFI_DIR/work/$m/" || exit 1
	for p in "$WIFI_DIR"/wifi-patches/*"$m"*.patch; do
		[ -f "$p" ] || continue
		echo "-- apply $(basename "$p")"
		( cd "$WIFI_DIR/work/$m" && patch -p1 -s --no-backup-if-mismatch < "$p" ) || exit 1
	done
	[ -f "$WIFI_DIR/.symvers-$m.saved" ] && \
		mv "$WIFI_DIR/.symvers-$m.saved" "$WIFI_DIR/work/$m/Module.symvers"
	cp "$WIFI_DIR/kbuild/$m.Kbuild" "$WIFI_DIR/work/$m/Makefile" || exit 1
done
rm -rf "$WIFI_DIR/work/compat" "$WIFI_DIR/work/stubs"
cp -a "$WIFI_DIR/compat" "$WIFI_DIR/work/compat" || exit 1
if [ -d "$WIFI_DIR/stubs" ]; then
	# Every module gets its own copy; the Kbuild wrappers list only the stub
	# objects they need.
	for m in common wlan; do
		mkdir -p "$WIFI_DIR/work/$m/stubs"
		cp -a "$WIFI_DIR/stubs/"*.c "$WIFI_DIR/work/$m/stubs/" 2>/dev/null || true
	done
fi
echo "work trees ready"

[ "$PREPARE_ONLY" -eq 1 ] && exit 0

[ -f "$KB/Module.symvers" ] || {
	echo "нет $KB/Module.symvers -- сначала собери ядро" >&2
	exit 1
}

# CONFIG_WIRELESS_EXT is not cosmetic here: it adds two pointers to
# struct net_device (wireless_handlers/wireless_data), so a module built against
# an out-tree without it sees every net_device field past that point shifted by
# 16 bytes relative to the running kernel. The result is silent memory
# corruption (num_tx_queues reads as garbage, netif_tx_stop_all_queues stores
# into rodata, kernel oops) -- see docs/wifi-port-log.md §29. The out-tree must
# therefore be the one that built the running kernel, WEXT included.
if ! grep -q '^CONFIG_WIRELESS_EXT=y' "$KB/.config" 2>/dev/null; then
	echo "$KB/.config has no CONFIG_WIRELESS_EXT=y -- refusing to build:" >&2
	echo "  struct net_device would not match the running kernel" >&2
	echo "  (running kernel: /home/l/t1100-merge2-out, see docs/wifi-port-log.md §29)" >&2
	exit 1
fi

# LOCALVERSION is not cosmetic: every `make -C <kernel>` run regenerates
# include/config/kernel.release (filechk + FORCE), and without the suffix the
# release collapses to the bare version -- the module then gets the wrong
# vermagic and insmod rejects it. Pass it explicitly, deriving it from the
# out-tree's own release when the caller did not.
if [ -z "$LOCALVERSION" ] && [ -f "$KB/include/config/kernel.release" ]; then
	LOCALVERSION=$(sed -E 's/^[0-9]+\.[0-9]+\.[0-9]+//' "$KB/include/config/kernel.release")
fi
REL_BEFORE=$(cat "$KB/include/config/kernel.release" 2>/dev/null || true)
echo "kernel out : $KB"
echo "release    : $REL_BEFORE (LOCALVERSION='$LOCALVERSION')"

rc_all=0
for m in $MODULES; do
	echo "== $m: make -C $KB M=$WIFI_DIR/work/$m modules (-j$JOBS) =="
	# wlan_drv_gen3.ko calls the mtk_wcn_* exports of wmt_drv.ko, so modpost
	# needs the other module's Module.symvers (KBUILD_EXTRA_SYMBOLS).
	EXTRA=""
	for dep in common wlan; do
		[ "$dep" = "$m" ] && continue
		[ -f "$WIFI_DIR/work/$dep/Module.symvers" ] && \
			EXTRA="$EXTRA ${WIFI_DIR}/work/${dep}/Module.symvers"
	done
	# M23: wmt_drv's stp_btif.o calls the mtk_wcn_btif_* exports of the BTIF
	# driver, which is built separately (scripts/remote/build-btif-remote.sh,
	# tree $BTIF_DIR). Its Module.symvers has to be on the modpost path too.
	if [ "$m" = "common" ] && [ -f "${BTIF_DIR:-/home/l/m23-btif}/Module.symvers" ]; then
		EXTRA="$EXTRA ${BTIF_DIR:-/home/l/m23-btif}/Module.symvers"
	fi
	# KBUILD_EXTRA_SYMBOLS is a space separated list, so it cannot go on the
	# make command line: MAKEOVERRIDES puts it into the sub-make invocation,
	# which /bin/sh re-parses and dies on ("Syntax error: Unterminated quoted
	# string", seen 13.11). Handing it over as an environment variable makes
	# it a plain make variable without touching MAKEOVERRIDES.
	# Chip selection. In the vendor build glue this was
	# CONFIG_MTK_COMBO_CHIP="CONSYS_6771". Our Kbuild wrappers spell the same
	# choice out in ccflags (-DMT6631 for the A-die 0x6771 -> firmware 6759
	# mapping in wlan, common_main/platform/mt6771.o in the WMT object list),
	# so the variable itself is not passed to make. Keep it in the log only,
	# so the architecture choice stays visible.
	echo "-- chip selection: MT6631 / CONSYS_6771 (spelled out in *.Kbuild)"
	[ -n "$EXTRA" ] && echo "-- KBUILD_EXTRA_SYMBOLS:$EXTRA"
	KBUILD_EXTRA_SYMBOLS="${EXTRA# }" \
	make -C "$KB" M="$WIFI_DIR/work/$m" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
		LOCALVERSION="$LOCALVERSION" \
		-j"$JOBS" modules \
		> "$LOG/build-$m.log" 2>&1
	rc=$?
	echo "$m rc=$rc errors=$(grep -c 'error:' "$LOG/build-$m.log") \
warnings=$(grep -c 'warning:' "$LOG/build-$m.log") \
undefined=$(grep -c 'undefined!' "$LOG/build-$m.log")"
	[ $rc -ne 0 ] && rc_all=1
done

REL_AFTER=$(cat "$KB/include/config/kernel.release" 2>/dev/null || true)
if [ "$REL_AFTER" != "$REL_BEFORE" ]; then
	echo "ОШИБКА: release out-дерева изменился при сборке: '$REL_BEFORE' -> '$REL_AFTER'" >&2
	echo "        (значит LOCALVERSION не передан; .ko получат чужой vermagic)" >&2
	rc_all=1
else
	echo "release after build: $REL_AFTER (не изменился)"
fi

echo "== modules =="
for f in "$WIFI_DIR"/work/*/*.ko; do
	[ -f "$f" ] || continue
	printf '%s  %10s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" \
		"$(stat -c%s "$f")" "${f#$WIFI_DIR/work/}"
done
exit $rc_all
