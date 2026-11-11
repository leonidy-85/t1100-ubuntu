#!/bin/busybox sh
# T1100 (MT6771) initramfs init: boot Ubuntu from eMMC, and open a debug
# channel over USB *before* switching root.
#
# Channels (no UART on this tablet):
#   1. dmesg snapshot -> expdb (p3), readable from recovery with dd/grep
#   2. ramoops/pstore in RAM (own region at 0x70000000 from the DTB)
#   3. RNDIS gadget + busybox telnetd on port 2323 (survives switch_root,
#      because the process keeps running after the initramfs is deleted)
#   4. the same logs copied into /var/log/pstore on the rootfs
set -x

/bin/busybox --install -s /bin
export PATH=/bin
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev 2>/dev/null
mkdir -p /dev/pts /mnt /sys/kernel/config
# busybox telnetd needs a pty; devtmpfs alone gives /dev/ptmx but no pts
mount -t devpts none /dev/pts 2>/dev/null
mount -t configfs none /sys/kernel/config 2>/dev/null

expdb_dump() {
  # p3 = expdb (2 MiB, vendor debug area, safe to overwrite)
  {
    echo "=== T1100-INITRAMFS $1 uptime=$(cat /proc/uptime) ==="
    dmesg
    echo "=== UDC: $(ls /sys/class/udc 2>/dev/null | tr '\n' ' ') ==="
    echo "=== net: $(ifconfig 2>/dev/null | tr '\n' '|') ==="
    if [ -f /tmp/sshd_t ]; then
      echo "=== sshd -t ==="
      cat /tmp/sshd_t
    fi
    echo "=== END $1 ==="
  } | dd of=/dev/mmcblk0p3 bs=4096 conv=fsync 2>/dev/null
  sync
}

# --- USB: RNDIS + telnet shell ------------------------------------------------
usb_up() {
  udc=$(ls /sys/class/udc 2>/dev/null | head -n 1)
  [ -n "$udc" ] || { echo "no UDC yet"; return 1; }
  G=/sys/kernel/config/usb_gadget/t1100
  [ -d "$G" ] && return 0
  mkdir -p "$G" || return 1
  echo 0x1d6b > "$G/idVendor"
  echo 0x0104 > "$G/idProduct"
  echo 0x0100 > "$G/bcdDevice"
  echo 0x0200 > "$G/bcdUSB"
  mkdir -p "$G/strings/0x409"
  echo "T1100-0001" > "$G/strings/0x409/serialnumber"
  echo "Fplus"      > "$G/strings/0x409/manufacturer"
  echo "T1100 Ubuntu" > "$G/strings/0x409/product"
  mkdir -p "$G/configs/c.1/strings/0x409"
  echo "RNDIS" > "$G/configs/c.1/strings/0x409/configuration"
  echo 250    > "$G/configs/c.1/MaxPower"
  mkdir -p "$G/functions/rndis.usb0"
  ln -s "$G/functions/rndis.usb0" "$G/configs/c.1/" 2>/dev/null
  # busybox telnetd gives a shell even if systemd never comes up
  telnetd -p 2323 -l /bin/sh >/dev/null 2>&1 &
  echo "$udc" > "$G/UDC"
  echo "UDC set to $udc"
  sleep 2
  for n in usb0 usb1 eth0; do
    ifconfig "$n" 10.42.66.66 netmask 255.255.255.248 up 2>/dev/null && break
  done
  ifconfig -a
}

# --- wait for the root partition -------------------------------------------------
i=0
while [ $i -lt 30 ]; do
  [ -b /dev/mmcblk0p54 ] && break
  sleep 1; i=$((i+1))
done
echo "rootfs wait ${i}s"

expdb_dump "before-usb"
usb_up || echo "usb_up failed"
expdb_dump "after-usb"

if mount -t ext4 -o rw /dev/mmcblk0p54 /mnt; then
  # is sshd startable at all? (its config/keys/users were repaired by hand)
  { chroot /mnt /usr/sbin/sshd -t; echo "sshd -t rc=$?"; } > /tmp/sshd_t 2>&1
  expdb_dump "pre-switch"
  mkdir -p /mnt/var/log/pstore
  # Hand the kernel filesystems over to the new root: switch_root() leaves
  # the rootfs with its own bare, empty /dev, /proc and /sys otherwise.
  mkdir -p /mnt/dev /mnt/proc /mnt/sys
  mount --move /dev /mnt/dev 2>/dev/null
  mount --move /proc /mnt/proc 2>/dev/null
  mount --move /sys /mnt/sys 2>/dev/null
  # A raw fallback shell that needs no pty at all (works even if devpts is
  # missing); harmless under systemd, which ignores /etc/inittab.
  mkdir -p /mnt/dev/pts /mnt/dev/shm
  if ! grep -q 'nc -l -p 2222' /mnt/etc/inittab 2>/dev/null; then
    echo '::respawn:/bin/busybox nc -l -p 2222 -e /bin/sh' >> /mnt/etc/inittab
  fi
  dmesg > /mnt/var/log/pstore/dmesg-initramfs.txt 2>/dev/null
  cp /sys/fs/pstore/* /mnt/var/log/pstore/ 2>/dev/null
  cp /proc/uptime /mnt/var/log/pstore/ 2>/dev/null
  sync
  echo "switching root"
  exec switch_root /mnt /sbin/init
fi

echo "rootfs mount FAILED, keeping telnet shell"
while true; do sleep 3600; done
