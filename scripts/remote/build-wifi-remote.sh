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
KB=${WIFI_DIR}/out
LOG=${WIFI_DIR}/logs
JOBS=${JOBS:-10}
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

rc_all=0
for m in $MODULES; do
	echo "== $m: make -C $KB M=$WIFI_DIR/work/$m modules (-j$JOBS) =="
	# wlan_drv_gen3.ko calls the mtk_wcn_* exports of wmt_drv.ko, so modpost
	# needs the other module's Module.symvers (KBUILD_EXTRA_SYMBOLS).
	EXTRA=""
	for dep in common wlan; do
		[ "$dep" = "$m" ] && continue
		[ -f "$WIFI_DIR/work/$dep/Module.symvers" ] && \
			EXTRA="KBUILD_EXTRA_SYMBOLS=$WIFI_DIR/work/$dep/Module.symvers"
	done
	make -C "$KB" M="$WIFI_DIR/work/$m" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
		$EXTRA -j"$JOBS" modules > "$LOG/build-$m.log" 2>&1
	rc=$?
	echo "$m rc=$rc errors=$(grep -c 'error:' "$LOG/build-$m.log") \
warnings=$(grep -c 'warning:' "$LOG/build-$m.log") \
undefined=$(grep -c 'undefined!' "$LOG/build-$m.log")"
	[ $rc -ne 0 ] && rc_all=1
done

echo "== modules =="
for f in "$WIFI_DIR"/work/*/*.ko; do
	[ -f "$f" ] || continue
	printf '%s  %10s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" \
		"$(stat -c%s "$f")" "${f#$WIFI_DIR/work/}"
done
exit $rc_all
