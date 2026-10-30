#!/bin/busybox sh
/bin/busybox --install -s /bin
export PATH=/bin
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev 2>/dev/null
mount -t tmpfs none /tmp
mount -t configfs none /sys/kernel/config 2>/dev/null

echo "=== T1100-INITRAMFS-START ==="
uname -a
cat /proc/cmdline
echo "mem: $(grep MemTotal /proc/meminfo)"
echo "block: $(cat /proc/partitions | tail -n +3 | head -5 | tr '\n' ' ')"
echo "udc: $(ls /sys/class/udc 2>/dev/null)"
echo "net: $(ls /sys/class/net 2>/dev/null)"

G=/sys/kernel/config/usb_gadget/t1100
mkdir -p "$G" 2>/dev/null
setup_gadget() {
  mkdir -p "$G" 2>/dev/null
  echo 0x1d6b > "$G/idVendor" 2>/dev/null
  echo 0x0104 > "$G/idProduct" 2>/dev/null
  mkdir -p "$G/strings/0x409"
  echo T1100 > "$G/strings/0x409/serialnumber"
  echo Fplus > "$G/strings/0x409/manufacturer"
  echo "T1100 mainline" > "$G/strings/0x409/product"
  mkdir -p "$G/configs/c.1/strings/0x409"
  echo rndis > "$G/configs/c.1/strings/0x409/configuration"
  mkdir -p "$G/functions/rndis.usb0" 2>/dev/null
  ln -s "$G/functions/rndis.usb0" "$G/configs/c.1/" 2>/dev/null
  for n in usb0 rndis0; do
    [ -e "/sys/class/net/$n" ] || continue
    ip link set "$n" up 2>/dev/null
    ip addr add 10.42.66.66/29 dev "$n" 2>/dev/null
    echo "iface $n = 10.42.66.66/29"
  done
}

# wait up to 60 s for a UDC to appear (mtu3 probes late)
i=0
while [ $i -lt 60 ]; do
  u=$(ls /sys/class/udc 2>/dev/null | head -1)
  [ -n "$u" ] && break
  sleep 1; i=$((i+1))
done
echo "udc after ${i}s: ${u:-none}"
if [ -n "$u" ]; then
  setup_gadget
  echo "$u" > "$G/UDC" 2>/dev/null && echo "bound $u"
  sleep 2
  setup_gadget
  telnetd -l /bin/sh -p 23 2>/dev/null && echo "telnetd on :23"
fi

# black box: last 1800 bytes of dmesg into the MTK ram_console SRAM window,
# which the recovery kernel dumps via /proc/last_kmsg (no UART needed)
if [ -c /dev/mem ]; then
  dmesg | tail -c 1800 > /tmp/log
  printf 'T1100LOG ' > /tmp/hdr
  cat /tmp/hdr /tmp/log > /tmp/dump
  dd if=/tmp/dump of=/dev/mem bs=1 seek=$((0x11d000)) conv=notrunc 2>/dev/null \
    && echo "dumped $(stat -c%s /tmp/dump) bytes to SRAM 0x11d000"
fi

# eMMC log channel: dump dmesg into the scratch partition (expdb, p03)
i=0
while [ $i -lt 20 ] && [ ! -b /dev/mmcblk0p3 ]; do sleep 1; i=$((i+1)); done
if [ -b /dev/mmcblk0p3 ]; then
  { printf 'T1100LOG v4 '; date; echo; dmesg; } > /tmp/emmc_log
  dd if=/tmp/emmc_log of=/dev/mmcblk0p3 bs=4096 seek=1024 conv=fsync 2>/dev/null \
    && echo "emmc log written ($(stat -c%s /tmp/emmc_log) bytes)"
fi

echo "=== T1100-INITRAMFS-OK ==="
# never exit (exit of pid 1 panics the kernel); refresh the SRAM black box
while :; do
  if [ -c /dev/mem ]; then
    { printf 'T1100LOG '; dmesg | tail -c 1600; } > /tmp/dump 2>/dev/null
    dd if=/tmp/dump of=/dev/mem bs=1 seek=$((0x11d000)) conv=notrunc 2>/dev/null
  fi
  sleep 20
done
