#!/usr/bin/env bash
# Offline answer to "will MTK LK accept this DTB on *my* device?".
#
# Three independent checks, all reproducible without booting our kernel:
#   1. hash of the DTB built from the tree
#   2. hash of the DTB physically inside the boot image that was (or will be)
#      flashed  -- use tools/lk/extract-boot-dtb.py
#   3. replay of LK's own requirements (PennyOS validator) against the vendor
#      dtbo_a of the *target* device and its live device tree
#
# Usage:
#   tools/lk/verify-dtb.sh <our.dtb> [dtbo_a.img] [live.dts]
# Defaults: build/lk/dtbo_a.img and build/lk/live.dts (this tablet's backups).
#
# Getting the two vendor inputs from another device (see docs/lk-dtb-verification.md):
#   dtbo_a.img : dd if=/dev/block/platform/bootdevice/by-name/dtbo_a of=/sdcard/dtbo_a.img
#                (or, in recovery, dd if=/dev/mmcblk0p31; entry 0 of the DTBO table
#                 is what LK applies)
#   live.dts   : dtc -I fs -O dts /proc/device-tree > live.dts   (on a booted system)
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
DTB=${1:?usage: verify-dtb.sh <our.dtb> [dtbo_a.img] [live.dts]}
DTBO=${2:-$ROOT/build/lk/dtbo_a.img}
LIVE=${3:-$ROOT/build/lk/live.dts}

[ -f "$DTB" ] || { echo "no such dtb: $DTB" >&2; exit 1; }
[ -f "$DTBO" ] || { echo "no such dtbo image: $DTBO" >&2; exit 1; }
[ -f "$LIVE" ] || { echo "no such live dts: $LIVE" >&2; exit 1; }

echo "== 1. DTB from the tree =="
stat -c 'size %s bytes' "$DTB"
sha256sum "$DTB"

echo
echo "== 2. vendor inputs (must be from the SAME device/firmware as the test) =="
stat -c '%n: %s bytes' "$DTBO" "$LIVE"
echo "dtbo_a first entry:"
python3 - "$DTBO" <<'PY'
import struct, sys, hashlib
d = open(sys.argv[1], 'rb').read()
if d[:4] != b'\xd7\xb7\xab\x1e':
    print('  plain overlay, no DTBO table')
    sys.exit()
eo = struct.unpack('>I', d[20:24])[0]
size, off = struct.unpack('>II', d[eo:eo + 8])
print(f'  entry0: {size} bytes at {off}, sha256 {hashlib.sha256(d[off:off+size]).hexdigest()}')
PY

echo
echo "== 3. replay of LK's requirements =="
set -o pipefail
python3 "$ROOT/refs/pennyos-lk/check-lk-dtb.py" "$DTB" "$DTBO" "$LIVE" | tail -15
rc=$?
echo
if [ $rc -eq 0 ]; then
  echo "RESULT: validator passed -> LK should accept this DTB"
else
  echo "RESULT: validator FAILED (rc=$rc) -> LK will ASSERT/reboot with this DTB"
fi
exit $rc
