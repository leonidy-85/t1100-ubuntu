#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BB=${BUSYBOX:-/tmp/bb/usr/bin/busybox}
OUT=${1:-build/initramfs_net.cpio.gz}
ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT"/{bin,dev,proc,sys,tmp,etc,lib,sbin}
cp "$BB" "$ROOT/bin/busybox"
for a in sh mount ip telnetd dmesg sleep uname cat grep ls echo; do ln -sf busybox "$ROOT/bin/$a"; done
cp "$HERE/net-init.sh" "$ROOT/init"; chmod +x "$ROOT/init"
( cd "$ROOT" && find . -print0 | cpio --null -o -H newc --quiet ) | gzip -9 > "$OUT"
echo "wrote $OUT: $(stat -c%s "$OUT") bytes"
