#!/usr/bin/env bash
# Build the relocation shim + real kernel into a boot image.
#
# The shim (shim.S) is prepended to the arm64 Image, compressed as one blob and
# put into the kernel slot. `lk` jumps to the shim, which copies the kernel to
# 0x44000000 (2 MiB aligned) and branches there — see the comment in shim.S.
#
# Usage:
#   tools/shim/build.sh --dtb build/t1100/arch/arm64/boot/dts/mediatek/mt6771-fplus-t1100.dtb \
#       --out build/boot_shim.img
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
CROSS=${CROSS:-aarch64-linux-gnu-}
IMAGE=${IMAGE:-$ROOT/build/t1100/arch/arm64/boot/Image}
DTB=${DTB:-$ROOT/build/t1100/arch/arm64/boot/dts/mediatek/mt6771-fplus-t1100.dtb}
REF=${REF:-$ROOT/../t1100/backup_5.1.6.110/boot_a_5.1.6.110.img}
INITRAMFS=${INITRAMFS:-$ROOT/build/initramfs.cpio.gz}
OUT=${OUT:-$ROOT/build/boot_shim.img}
CMDLINE=${CMDLINE:-"console=tty0 maxcpus=1 nokaslr panic=10 pstore.backend=ramoops loglevel=7"}
KERNEL_ADDR=${KERNEL_ADDR:-0x40080000}

while [ $# -gt 0 ]; do
  case $1 in
    --out) OUT=$2; shift 2 ;;
    --dtb) DTB=$2; shift 2 ;;
    --image) IMAGE=$2; shift 2 ;;
    --cmdline) CMDLINE=$2; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

WORK=$(mktemp -d /tmp/shim.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

cp "$IMAGE" "$WORK/kernel.bin"
"${CROSS}gcc" -c -nostdlib -ffreestanding \
  -DKERNEL_BIN="\"$WORK/kernel.bin\"" -o "$WORK/shim.o" "$HERE/shim.S"
"${CROSS}ld" -Ttext=0 -nostdlib -o "$WORK/shim.elf" "$WORK/shim.o"
"${CROSS}objcopy" -O binary "$WORK/shim.elf" "$WORK/blob.bin"

python3 - "$WORK/blob.bin" "$WORK/kernel.bin" <<'PY'
import struct, sys
blob_path, kern_path = sys.argv[1], sys.argv[2]
b = bytearray(open(blob_path, "rb").read())
kern = open(kern_path, "rb").read()
assert b[56:60] == b"ARM\x64", "shim blob lost its arm64 magic"
assert kern[56:60] == b"ARM\x64", "kernel is not an arm64 Image"
assert b.endswith(kern), "kernel not appended as expected"
struct.pack_into("<Q", b, 16, len(b))
# keep the kernel's own image_size/flags inside the embedded copy (untouched)
open(blob_path, "wb").write(b)
print(f"blob: {len(b)} bytes (shim {len(b) - len(kern)}, kernel {len(kern)})")
PY

gzip -9 -c "$WORK/blob.bin" > "$WORK/blob.bin.gz"
python3 "$ROOT/scripts/repack_boot.py" \
  --ref "$REF" --kernel "$WORK/blob.bin.gz" --ramdisk "$INITRAMFS" \
  --dtb "$DTB" --kernel-addr "$KERNEL_ADDR" --cmdline "$CMDLINE" --out "$OUT"
sha256sum "$OUT"
