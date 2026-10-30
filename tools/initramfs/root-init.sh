#!/bin/busybox sh
/bin/busybox --install -s /bin
export PATH=/bin
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev 2>/dev/null
mkdir -p /mnt
i=0
while [ $i -lt 30 ]; do
  [ -b /dev/mmcblk0p54 ] && break
  sleep 1; i=$((i+1))
done
echo "rootfs wait ${i}s; trying mount"
if mount -t ext4 -o rw /dev/mmcblk0p54 /mnt; then
  echo "rootfs mounted, switching root"
  exec switch_root /mnt /sbin/init
fi
echo "rootfs mount FAILED, dropping to shell"
exec /bin/sh
