#!/usr/bin/env bash
# Build a minimal initramfs (cpio.gz) for the first mainline boot on T1100.
#
# Purpose: prove "our kernel reached userspace" and leave a *persistent* trace.
# There is no UART; the only log channel is ramoops/pstore in RAM, so the
# initramfs prints markers through printk and then either sleeps, reboots or
# powers off — see --action.
#
# Requires an aarch64 static busybox:
#   apt-get download busybox-static:arm64 && dpkg-deb -x busybox-static*.deb /tmp/bb
#
# Usage:
#   scripts/make_initramfs.sh --busybox /tmp/bb/usr/bin/busybox \
#       --action sleep --out build/initramfs.cpio.gz
set -euo pipefail

BUSYBOX=${BUSYBOX:-/tmp/bb/usr/bin/busybox}
ACTION=sleep
OUT=build/initramfs.cpio.gz
SLEEP=3600

while [ $# -gt 0 ]; do
  case $1 in
    --busybox) BUSYBOX=$2; shift 2 ;;
    --action)  ACTION=$2; shift 2 ;;
    --sleep)   SLEEP=$2; shift 2 ;;
    --out)     OUT=$2; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

case $ACTION in sleep|reboot|poweroff) ;; *) echo "--action: sleep|reboot|poweroff" >&2; exit 2 ;; esac
[ -x "$BUSYBOX" ] || { echo "busybox not found: $BUSYBOX" >&2; exit 1; }
file "$BUSYBOX" | grep -q 'ARM aarch64' || { echo "busybox is not aarch64" >&2; exit 1; }

ROOT=$(mktemp -d /tmp/initramfs.XXXXXX)
trap 'rm -rf "$ROOT"' EXIT

mkdir -p "$ROOT"/{bin,sbin,dev,proc,sys,tmp,etc,lib}
cp "$BUSYBOX" "$ROOT/bin/busybox"
for a in sh ls cat echo mount umount sleep reboot poweroff dmesg free \
         grep head tail sed awk mkdir mknod date uname dd hexdump; do
  ln -sf busybox "$ROOT/bin/$a"
done
: > "$ROOT/etc/mtab"

cat > "$ROOT/init" <<EOF
#!/bin/busybox sh
# --- T1100 mainline bring-up initramfs ---
/bin/busybox --install -s /bin
export PATH=/bin
export HOME=/
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev 2>/dev/null
echo ""
echo "=== T1100-INITRAMFS-START ==="
echo "kernel: \$(uname -a)"
echo "cmdline: \$(cat /proc/cmdline)"
echo "mem: \$(grep MemTotal /proc/meminfo)"
echo "block:"; cat /proc/partitions
echo "clocks: \$(ls /sys/kernel/debug 2>/dev/null | head -1)"
echo "tty: \$(ls /dev/ttyS* 2>/dev/null)"
echo "=== T1100-INITRAMFS-OK ==="
sync
case "$ACTION" in
  sleep)    echo "sleeping $SLEEP s (device stays here; logs captured by pstore)"; sleep $SLEEP ;;
  reboot)   echo "rebooting"; sleep 2; reboot -f ;;
  poweroff) echo "powering off"; sleep 2; poweroff -f ;;
esac
EOF
chmod +x "$ROOT/init"

mkdir -p "$(dirname "$OUT")"
( cd "$ROOT" && find . -print0 | cpio --null -o -H newc --quiet ) | gzip -9 > "$OUT"
echo "wrote $OUT: $(stat -c%s "$OUT") bytes (action=$ACTION)"
echo "busybox: $BUSYBOX ($(stat -c%s "$BUSYBOX") bytes)"
