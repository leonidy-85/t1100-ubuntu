#!/usr/bin/env python3
"""Inspect / patch the arm64 `Image` header (Documentation/arm64/booting.rst).

Fields (little-endian):
   0x00  code0 / branch to entry
   0x08  text_offset   (u64)
   0x10  image_size    (u64, includes BSS; may be larger than the file)
   0x18  flags         (u64, bit1..2 page size, bit3 placement)
   0x38  magic "ARM\\x64"

Mainline 6.12 emits text_offset = 0 (`arch/arm64/kernel/head.S` hardcodes it),
which per the boot protocol requires a 2 MiB aligned load address. The MTK `lk`
of the T1100 hands over at 0x40080000 (the 4.14-era convention
text_offset = 0x80000). This tool reports the header and can rewrite
text_offset / flags for experiments (the kernel itself never reads these).

Usage:
  scripts/patch_image_header.py --print build/t1100/arch/arm64/boot/Image
  scripts/patch_image_header.py --in Image --text-offset 0x80000 --out Image.fix
"""
import argparse
import gzip
import struct
import sys

MAGIC = b"ARM\x64"


def load(path):
    d = open(path, "rb").read()
    if d[:2] == b"\x1f\x8b":
        d = gzip.decompress(d)
    return d


def read_header(d):
    if d[56:60] != MAGIC:
        sys.exit("not an arm64 Image (bad magic at 0x38)")
    text_offset, image_size, flags = struct.unpack_from("<QQQ", d, 8)
    return text_offset, image_size, flags


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", help="input Image (raw or gzip)")
    ap.add_argument("--print", dest="show", help="print header of this Image")
    ap.add_argument("--text-offset", type=lambda x: int(x, 0))
    ap.add_argument("--flags", type=lambda x: int(x, 0))
    ap.add_argument("--out")
    a = ap.parse_args()

    if a.show:
        d = load(a.show)
        t, s, f = read_header(d)
        print(f"{a.show}: file={len(d)} text_offset=0x{t:x} image_size=0x{s:x} "
              f"({s}) flags=0x{f:x} pages={["unspecified","4K","16K","64K"][(f >> 1) & 3]}")
        return

    if not a.inp or not a.out:
        sys.exit("need --in and --out (or --print)")

    d = bytearray(load(a.inp))
    t, s, f = read_header(d)
    if a.text_offset is not None:
        struct.pack_into("<Q", d, 8, a.text_offset)
        t = a.text_offset
    if a.flags is not None:
        struct.pack_into("<Q", d, 0x18, a.flags)
        f = a.flags
    open(a.out, "wb").write(d)
    print(f"wrote {a.out}: {len(d)} bytes, text_offset=0x{t:x}, image_size=0x{s:x}, flags=0x{f:x}")


if __name__ == "__main__":
    main()
