#!/usr/bin/env bash
# Assemble a flashable boot_a image for the T1100 in one step:
#   Image.gz + initramfs + our DTB + stock header template -> boot_a_test.img
#
# Nothing is flashed here. The script only writes files under build/ and prints
# the sha256, which must be compared with the device after dd (see
# docs/boot-test.md).
#
# Usage:
#   scripts/make_test_boot.sh --dtb build/t1100/arch/arm64/boot/dts/mediatek/mt6771-fplus-t1100.dtb
#   scripts/make_test_boot.sh --dtb ... --cmdline "console=ttyS0,921600n8 maxcpus=1 panic=10"
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)

# Reference boot image: only its header (load addresses, MTK layout) is used.
# Any stock boot_a of this tablet works; keep the first existing candidate.
if [ -z "${REF:-}" ]; then
  for c in "$ROOT/refs/boot/stock_boot.img" \
           "$ROOT/../t1100/backup_5.1.6.110/boot_a_5.1.6.110.img" \
           "$ROOT/../1100/boot_a.bin"; do
    [ -f "$c" ] && { REF=$c; break; }
  done
fi
REF=${REF:-$ROOT/../t1100/backup_5.1.6.110/boot_a_5.1.6.110.img}
IMAGE=${IMAGE:-$ROOT/build/t1100/arch/arm64/boot/Image}
INITRAMFS=${INITRAMFS:-$ROOT/build/initramfs.cpio.gz}
OUT=${OUT:-$ROOT/build/boot_a_test.img}
# Kernel command line written into the boot image header. The stock reference
# carries Android/Aurora bits we do not want (security=diehard, ima_appraise=
# enforce, module.sig_enforce=1); bootopt= is kept because lk parses it.
CMDLINE=${CMDLINE:-"bootopt=64S3,32N2,64N2 console=tty0 maxcpus=1 panic=0 pstore.backend=ramoops"}
# Mainline arm64 Image has text_offset 0 and must be loaded 2 MiB aligned;
# the stock MTK header says 0x40080000, which is not. Override it.
KERNEL_ADDR=${KERNEL_ADDR:-0x40200000}
DTB=

while [ $# -gt 0 ]; do
  case $1 in
    --dtb) DTB=$2; shift 2 ;;
    --image) IMAGE=$2; shift 2 ;;
    --initramfs) INITRAMFS=$2; shift 2 ;;
    --ref) REF=$2; shift 2 ;;
    --out) OUT=$2; shift 2 ;;
    --cmdline) CMDLINE=$2; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$DTB" ] || { echo "usage: $0 --dtb <board.dtb> [--cmdline ...]" >&2; exit 2; }
for f in "$REF" "$IMAGE" "$INITRAMFS" "$DTB"; do
  [ -f "$f" ] || { echo "missing: $f" >&2; exit 1; }
done

# Ramdisk must be a gzip-compressed cpio; kernel must be gzip for the boot img.
python3 - "$IMAGE" "$INITRAMFS" <<'PY'
import sys
with open(sys.argv[1], "rb") as f:
    k = f.read(64)
if k[:2] == b"\x1f\x8b":
    kind = "Image.gz"
elif k[56:60] == b"ARM\x64":
    kind = "raw arm64 Image (will be gzipped)"
else:
    sys.exit(f"kernel {sys.argv[1]}: neither gzip nor arm64 Image")
with open(sys.argv[2], "rb") as f:
    r = f.read(2)
if r != b"\x1f\x8b":
    sys.exit(f"initramfs {sys.argv[2]}: not gzip (expected cpio.gz)")
print(f"kernel: {kind}")
PY

IMG_GZ=$(mktemp /tmp/Image.gz.XXXXXX)
trap 'rm -f "$IMG_GZ"' EXIT
if [ "${IMAGE##*.}" = "gz" ]; then cp "$IMAGE" "$IMG_GZ"; else gzip -9 -c "$IMAGE" > "$IMG_GZ"; fi

args=(--ref "$REF" --kernel "$IMG_GZ" --ramdisk "$INITRAMFS" --dtb "$DTB" --out "$OUT")
[ -n "$KERNEL_ADDR" ] && args+=(--kernel-addr "$KERNEL_ADDR")
[ -n "$CMDLINE" ] && args+=(--cmdline "$CMDLINE")
echo "cmdline: $CMDLINE"
python3 "$HERE/repack_boot.py" "${args[@]}"

echo
echo "--- verify ---"
python3 "$HERE/bootimg_extract.py" --image "$OUT" --outdir "$(dirname "$OUT")/verify" | tail -4
sha256sum "$OUT" | tee "$OUT.sha256"
echo "partition boot_a = 32 MiB; image = $(stat -c%s "$OUT") bytes"
