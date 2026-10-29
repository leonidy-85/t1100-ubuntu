#!/usr/bin/env bash
# Build the "address bars" probe payload (see addr_bars.S) into a boot image.
#
# The payload is a valid arm64 Image that paints (runtime_addr >> 12) on the
# bootloader framebuffer. Flashing it answers three questions at once:
#   1. does lk jump to our image,
#   2. which framebuffer base is live (0x7cd80000 vs 0x7cb80000),
#   3. at which address the image is actually loaded.
#
# Usage: tools/payload/build.sh [--out build/payload_boot.img]
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OUT=${OUT:-$ROOT/build/payload_boot.img}
CROSS=${CROSS:-aarch64-linux-gnu-}
DTB=${DTB:-$ROOT/build/t1100/arch/arm64/boot/dts/mediatek/mt6771-fplus-t1100.dtb}
REF=${REF:-$ROOT/../t1100/backup_5.1.6.110/boot_a_5.1.6.110.img}
INITRAMFS=${INITRAMFS:-$ROOT/build/initramfs.cpio.gz}

while [ $# -gt 0 ]; do
  case $1 in
    --out) OUT=$2; shift 2 ;;
    --dtb) DTB=$2; shift 2 ;;
    --ref) REF=$2; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

WORK=$(mktemp -d /tmp/payload.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

"${CROSS}gcc" -c -nostdlib -ffreestanding -o "$WORK/addr_bars.o" "$HERE/addr_bars.S"
"${CROSS}ld" -Ttext=0 -nostdlib -o "$WORK/addr_bars.elf" "$WORK/addr_bars.o"
"${CROSS}objcopy" -O binary "$WORK/addr_bars.elf" "$WORK/payload.bin"

# Patch image_size (offset 16) so the header describes the real image.
python3 - "$WORK/payload.bin" <<'PY'
import struct, sys
p = sys.argv[1]
d = bytearray(open(p, "rb").read())
assert d[56:60] == b"ARM\x64", "payload lost its arm64 magic"
struct.pack_into("<Q", d, 16, len(d))
open(p, "wb").write(d)
print(f"payload: {len(d)} bytes, text_offset=0x{struct.unpack_from('<Q', d, 8)[0]:x}")
PY

gzip -9 -c "$WORK/payload.bin" > "$WORK/payload.bin.gz"
python3 "$ROOT/scripts/repack_boot.py" \
  --ref "$REF" --kernel "$WORK/payload.bin.gz" --ramdisk "$INITRAMFS" \
  --dtb "$DTB" --out "$OUT" \
  --cmdline "console=tty0 maxcpus=1 panic=10 pstore.backend=ramoops"
sha256sum "$OUT"
echo "payload boot image: $OUT"
