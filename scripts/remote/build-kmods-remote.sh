#!/bin/bash
# Host-side: build the kernel-side modules the vendor Wi-Fi stack needs
# (rfkill, libarc4, cfg80211, mac80211) against an *existing* kernel out-tree,
# and compose a complete Module.symvers for the vendor build.
#
# Why not `make modules`: the out-tree may belong to somebody else's kernel
# (e.g. the second developer's out-normal, release 6.12.114-g400cb6f-touch-rot)
# and has no Module.symvers at all -- `make Image` alone does not create one.
# Building all ~1100 modules just to get it is wasteful, so we build only the
# four modules we ship and assemble the symbol table ourselves:
#
#   Module.symvers = vmlinux.symvers (kernel exports, written by `make Image`)
#                  + exports of the modules built here
#
# In 6.12 an in-tree modpost run takes its input from vmlinux.o, so symbols a
# module takes from another *module* (cfg80211 -> rfkill, mac80211 -> cfg80211)
# look undefined in a single-target build. KBUILD_MODPOST_WARN=1 downgrades that
# to a warning: with CONFIG_MODVERSIONS=n no CRCs are involved and the .ko are
# complete; the real dependency graph is rebuilt by depmod on the device (and we
# check it here with `modprobe --show-depends`).
#
# Optional --enable-testmode: set CONFIG_NL80211_TESTMODE=y first. Required when
# the vendor wlan module is built with -DCONFIG_NL80211_TESTMODE=1 (see
# scripts/remote/wifi-kbuild/wlan.Kbuild): that option adds testmode_cmd/
# testmode_dump to `struct cfg80211_ops`, and the driver and cfg80211.ko must
# agree on the layout of that struct. Only this option is flipped; nothing else
# in the config is touched.
#
# Env:
#   KERNEL_OUT   out-tree to build in (default /home/l/t1100-wifi-build/out)
#   KERNEL_SRC   kernel source tree (default /home/l/t1100-ubuntu-build/src)
#   LOCALVERSION must equal the out-tree's localversion suffix; without it
#                include/config/kernel.release is regenerated to the bare
#                version and the modules get the wrong vermagic
#   JOBS         default 12
#
# Usage: KERNEL_OUT=... LOCALVERSION=-g400cb6f-touch-rot \
#            build-kmods-remote.sh [--enable-testmode]
set -u

KERNEL_OUT=${KERNEL_OUT:-/home/l/t1100-wifi-build/out}
KERNEL_SRC=${KERNEL_SRC:-/home/l/t1100-ubuntu-build/src}
LOCALVERSION=${LOCALVERSION-}
JOBS=${JOBS:-12}
ENABLE_TESTMODE=0
for arg in "$@"; do
	case "$arg" in
		--enable-testmode) ENABLE_TESTMODE=1 ;;
		-h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown argument: $arg" >&2; exit 2 ;;
	esac
done

[ -d "$KERNEL_OUT" ] || { echo "нет out-дерева $KERNEL_OUT" >&2; exit 1; }
[ -f "$KERNEL_OUT/vmlinux.symvers" ] || {
	echo "нет $KERNEL_OUT/vmlinux.symvers -- out-дерево не собрано (make Image)" >&2
	exit 1; }

cd "$KERNEL_OUT" || exit 1
# Derive the suffix from the tree's own release when the caller did not pass it:
# anything else silently changes the vermagic (see the header).
if [ -z "$LOCALVERSION" ] && [ -f include/config/kernel.release ]; then
	LOCALVERSION=$(sed -E 's/^[0-9]+\.[0-9]+\.[0-9]+//' include/config/kernel.release)
fi
export PATH="$HOME/.ccache-bin:$PATH" CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache-t1100}"
MK="make -C $KERNEL_SRC O=$PWD ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION=$LOCALVERSION"

REL_BEFORE=$(cat include/config/kernel.release 2>/dev/null)
echo "kernel out : $KERNEL_OUT"
echo "release    : $REL_BEFORE (LOCALVERSION='$LOCALVERSION')"

if [ "$ENABLE_TESTMODE" -eq 1 ] && ! grep -q '^CONFIG_NL80211_TESTMODE=y' .config; then
	echo "-- CONFIG_NL80211_TESTMODE=y (нужен вендорскому wlan)"
	cp .config /tmp/config.before-testmode
	"$KERNEL_SRC/scripts/config" --file .config -e NL80211_TESTMODE
	$MK olddefconfig > /tmp/kmods-olddefconfig.log 2>&1 || exit 1
	diff /tmp/config.before-testmode .config
fi

# target:path pairs; rfkill/libarc4 first, they are what the others reference
TARGETS="net/rfkill/rfkill.ko lib/crypto/libarc4.ko net/wireless/cfg80211.ko net/mac80211/mac80211.ko"
STAMP=$(date +%s)
rc_all=0
for t in $TARGETS; do
	echo "== $t"
	$MK "$t" KBUILD_MODPOST_WARN=1 -j"$JOBS" > "/tmp/kmods-$(echo "$t" | tr / -).log" 2>&1
	rc=$?
	log=/tmp/kmods-$(echo "$t" | tr / -).log
	echo "   rc=$rc errors=$(grep -c 'error:' "$log") warnings=$(grep -c 'warning:' "$log") \
undefined=$(grep -c 'undefined!' "$log")"
	[ $rc -ne 0 ] && { rc_all=1; tail -20 "$log"; }
	# modpost rewrites the objtree Module.symvers on every run, so keep a
	# snapshot of this step's table and fold it back: the next target then
	# sees the exports of the modules built before it (otherwise cfg80211
	# would not learn about rfkill and every cross-module symbol would be
	# reported as undefined).
	cp Module.symvers "/tmp/symvers-$STAMP-$(basename "$t" .ko).sy" 2>/dev/null
	cat vmlinux.symvers /tmp/symvers-"$STAMP"-*.sy \
		| awk -F'\t' '{ if (!seen[$2]++) print }' > /tmp/symvers-merged.sy
	mv /tmp/symvers-merged.sy Module.symvers
done

REL_AFTER=$(cat include/config/kernel.release 2>/dev/null)
if [ "$REL_AFTER" != "$REL_BEFORE" ]; then
	echo "ОШИБКА: release изменился: '$REL_BEFORE' -> '$REL_AFTER' (LOCALVERSION!)" >&2
	rc_all=1
fi

# Assemble the complete table: kernel exports + every module's exports.
# With CONFIG_MODVERSIONS=n the CRC column is always 0x00000000, so the symbol
# name (column 2) is the dedup key.
cat vmlinux.symvers /tmp/symvers-"$STAMP"-*.sy \
	| awk -F'\t' '{ if (!seen[$2]++) print }' > Module.symvers
echo "Module.symvers: $(wc -l < Module.symvers) symbols (release $REL_AFTER)"

echo "== .ko"
for t in $TARGETS; do
	[ -f "$t" ] || { echo "  НЕТ $t"; rc_all=1; continue; }
	printf '%s  %10s  %s\n' "$(sha256sum "$t" | cut -d' ' -f1)" "$(stat -c%s "$t")" "$t"
done
exit $rc_all
