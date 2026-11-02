#!/usr/bin/env bash
# Build the T1100 "boot Ubuntu from eMMC" initramfs (busybox, aarch64).
#
# Usage: tools/initramfs/build-root.sh [out.cpio.gz]
# Env:   BUSYBOX=/path/to/aarch64/busybox
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BB=${BUSYBOX:-/tmp/opencode/bb/busybox}
OUT=${1:-build/initramfs_root.cpio.gz}
[ -x "$BB" ] || { echo "no aarch64 busybox at $BB (set BUSYBOX=)" >&2; exit 1; }
file "$BB" | grep -q 'ARM aarch64' || { echo "$BB is not aarch64" >&2; exit 1; }

ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT"/{bin,dev,proc,sys,tmp,etc,lib,mnt}
cp "$BB" "$ROOT/bin/busybox"
for a in sh ifconfig telnetd dmesg dd mount umount sleep cat ls echo sync cp \
         mkdir ln rm grep tr head cut poweroff reboot; do
  ln -sf busybox "$ROOT/bin/$a"
done
cp "$HERE/root-init.sh" "$ROOT/init"
chmod 0755 "$ROOT/init"
: > "$ROOT/etc/mtab"
( cd "$ROOT" && find . -print0 | cpio --null -o -H newc -R 0:0 --quiet ) | gzip -9 > "$OUT"
echo "wrote $OUT: $(stat -c%s "$OUT") bytes, sha256 $(sha256sum "$OUT" | cut -d' ' -f1)"
