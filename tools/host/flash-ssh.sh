#!/usr/bin/env bash
# Flash boot_a (or any partition) over SSH while Ubuntu is running on the T1100.
#
# Why: once usb0/RNDIS and sshd work, the recovery round-trip (owner pressing
# keys) is not needed to iterate on the kernel. Writing boot_a from Linux is
# safe: the running kernel does not read that partition, `lk` does at boot.
#
# Usage: tools/host/flash-ssh.sh <image> [partition] [--reboot]
#        partition defaults to /dev/mmcblk0p29 (boot_a)
# Env:   T1100_HOST=10.42.66.66, T1100_USER=root
set -euo pipefail
IMG=${1:?usage: flash-ssh.sh <image> [partition] [--reboot]}
PART=${2:-/dev/mmcblk0p29}
REBOOT=0
for a in "$@"; do [ "$a" = "--reboot" ] && REBOOT=1; done
HOST=${T1100_HOST:-10.42.66.66}
USER=${T1100_USER:-root}
SSH=(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 "$USER@$HOST")

[ -f "$IMG" ] || { echo "no such image: $IMG" >&2; exit 1; }
md5=$(md5sum "$IMG" | cut -d' ' -f1)
echo "image   : $IMG ($(stat -c%s "$IMG") bytes, md5 $md5)"
"${SSH[@]}" "test -b $PART" || { echo "not a block device: $PART" >&2; exit 1; }

echo "writing : $PART"
"${SSH[@]}" "dd of=$PART bs=4M conv=fsync 2>&1 | tail -3" < "$IMG"
"${SSH[@]}" "sync; md5sum $PART" | tee /tmp/t1100-readback.md5
if ! grep -q "$md5" /tmp/t1100-readback.md5; then
  echo "MD5 MISMATCH: expected $md5" >&2; exit 1
fi
echo "verified: $PART md5 $md5"
if [ "$REBOOT" = 1 ]; then
  echo "rebooting"
  "${SSH[@]}" "sync; reboot -f" || true
fi
