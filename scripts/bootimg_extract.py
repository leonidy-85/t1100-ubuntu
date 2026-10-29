#!/usr/bin/env python3
"""Extract kernel / ramdisk / DTB from an Android boot image (header v0-v2).

Read-only helper: does not modify the image. Used to pull the stock T1100 DTB
out of boot_a so we can diff display/clock nodes against mainline (mt8365).

Usage:
  scripts/bootimg_extract.py --image ../t1100/backup_5.1.6.110/boot_a_5.1.6.110.img \
      --outdir build/stock
"""
import argparse
import os
import struct
import sys


def align(x, p):
    return (x + p - 1) // p * p


def parse(path):
    d = open(path, "rb").read()
    if d[:8] != b"ANDROID!":
        sys.exit("not an Android boot image (missing ANDROID! magic)")
    ks, ka, rs, ra, ss, sa, ta, ps = struct.unpack_from("<8I", d, 8)
    hv = struct.unpack_from("<I", d, 0x28)[0]
    assert hv in (0, 1, 2), f"unsupported header version {hv}"

    def padded(name, size, off):
        if not size:
            return b""
        assert off + size <= len(d), f"{name} out of range"
        return d[off:off + size]

    parts = {}
    off = ps
    parts["kernel"] = padded("kernel", ks, off)
    off += align(ks, ps)
    parts["ramdisk"] = padded("ramdisk", rs, off)
    off += align(rs, ps)
    if hv >= 1:
        parts["second"] = padded("second", ss, off)
        off += align(ss, ps)
    if hv == 2:
        # MTK layout: dtb_addr is a 32-bit field at 0x674, not the AOSP u64 at
        # 0x678 (reading it there returns 0).
        dtb_size = struct.unpack_from("<I", d, 0x670)[0]
        dtb_addr = struct.unpack_from("<I", d, 0x674)[0]
        blob = padded("dtb", dtb_size, off)
        # MTK prepends its own 64-byte header before the FDT blob; strip it.
        magic = b"\xd0\x0d\xfe\xed"
        if blob[:4] != magic:
            idx = blob.find(magic, 0, 4096)
            assert idx >= 0, "no FDT magic inside dtb blob"
            blob = blob[idx:]
        parts["dtb"] = blob
        parts["dtb_addr"] = dtb_addr
        off += align(dtb_size, ps)
    cmdline = d[0x40:0x240].split(b"\0")[0].decode(errors="replace")
    return hv, ps, parts, cmdline


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True)
    ap.add_argument("--outdir", required=True)
    args = ap.parse_args()

    hv, ps, parts, cmdline = parse(args.image)
    os.makedirs(args.outdir, exist_ok=True)
    for name in ("kernel", "ramdisk", "second", "dtb"):
        blob = parts.get(name) or b""
        if not blob:
            continue
        p = os.path.join(args.outdir, name)
        with open(p, "wb") as f:
            f.write(blob)
        print(f"{name:8s} {len(blob):>9d} bytes -> {p}")
    if "dtb_addr" in parts:
        print(f"dtb load addr = 0x{parts['dtb_addr']:x}")
    print(f"header v{hv}, page size {ps}")
    print(f"cmdline: {cmdline}")


if __name__ == "__main__":
    main()
