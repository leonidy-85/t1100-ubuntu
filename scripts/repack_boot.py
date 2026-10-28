#!/usr/bin/env python3
"""Repack an Android boot image (header v2) for the Fplus T1100.

The stock image carries: gzip kernel + gzip ramdisk + MTK-wrapped DTB.
The DTB blob inside the image is *not* a bare FDT: MTK `lk` expects a 64-byte
container header before it:

    off  size  value
    0x00   4   d7 b7 ab 1e (BE)  magic
    0x04   4   total_size        = 0x40 + len(fdt)
    0x08   4   0x20
    0x0c   4   0x20
    0x10   4   0x1
    0x14   4   0x20
    0x18   4   0x800
    0x1c   4   0x0
    0x20   4   payload_size      = len(fdt)
    0x24   4   0x40              payload offset
    0x28..0x3f  zeros

(Verified on the stock boot_a of Aurora 5.1.6.110: total=0x1b1f7,
payload=0x1b1b7, FDT at 0x40.)

Header parameters (addresses, page size, cmdline) are inherited from a
reference image, so we never guess load addresses.

Usage:
  # round-trip check (must be byte-identical to the stock image)
  scripts/repack_boot.py --ref stock.img --kernel stock/kernel \\
      --ramdisk stock/ramdisk --dtb stock/dtb --out /tmp/rt.img

  # real image
  scripts/repack_boot.py --ref stock.img --kernel Image.gz --dtb mt6771.dtb \\
      --ramdisk initramfs.cpio.gz --out boot_a_my.img
"""
import argparse
import struct
import sys

MTK_DTB_MAGIC = 0xD7B7AB1E
MTK_DTB_HDR_SIZE = 0x40


def align(x, p):
    return (x + p - 1) // p * p


def wrap_dtb(fdt: bytes) -> bytes:
    if fdt[:4] != b"\xd0\x0d\xfe\xed":
        sys.exit("dtb: not a flattened device tree (bad FDT magic)")
    total = MTK_DTB_HDR_SIZE + len(fdt)
    # all fields are big-endian in the stock blob
    hdr = struct.pack(
        ">10I",
        MTK_DTB_MAGIC,
        total,
        0x20, 0x20, 0x01, 0x20, 0x800, 0x0,
        len(fdt),
        MTK_DTB_HDR_SIZE,
    )
    hdr += b"\0" * (MTK_DTB_HDR_SIZE - len(hdr))
    return hdr + fdt


def read_ref(path):
    d = open(path, "rb").read()
    if d[:8] != b"ANDROID!":
        sys.exit("ref: not an Android boot image")
    (ks, ka, rs, ra, ss, sa, ta, ps) = struct.unpack_from("<8I", d, 8)
    hv = struct.unpack_from("<I", d, 0x28)[0]
    if hv != 2:
        sys.exit(f"ref: header version {hv}, only v2 supported")
    cmdline = d[0x40:0x240].split(b"\0")[0]
    name = d[0x30:0x40].split(b"\0")[0]
    dtb_size, dtb_addr = struct.unpack_from("<IQ", d, 0x670)
    return dict(
        d=d, page=ps, kernel_addr=ka, ramdisk_addr=ra, second_addr=sa,
        tags_addr=ta, cmdline=cmdline, name=name, dtb_addr=dtb_addr,
        img_size=len(d),
    )


def build(ref, kernel, ramdisk, dtb, cmdline, size):
    """Build image using the reference header as a template.

    The stock header is not the plain AOSP v2 layout: header_size sits at 0x66c,
    dtb_size at 0x670, dtb_addr at 0x674 (508-byte reserved hole before them).
    Copying the reference header and patching only sizes/cmdline keeps every
    unknown field (load addresses, ids, reserved) exactly as lk expects.
    """
    ps = ref["page"]
    hdr = bytearray(ref["d"][:0x67C])
    struct.pack_into("<I", hdr, 0x08, len(kernel))
    struct.pack_into("<I", hdr, 0x10, len(ramdisk))
    struct.pack_into("<I", hdr, 0x18, 0)                  # no second stage
    hdr[0x40:0x240] = cmdline.ljust(512, b"\0")[:512]
    struct.pack_into("<I", hdr, 0x670, len(dtb))
    hdr[0x260:0x280] = b"\0" * 32                         # id: unused by lk

    out = bytearray(hdr.ljust(ps, b"\0"))
    for blob in (kernel, ramdisk, dtb):
        out += blob
        out += b"\0" * (align(len(blob), ps) - len(blob))
    if size:
        if len(out) > size:
            sys.exit(f"image {len(out)} > partition {size}")
        out += b"\0" * (size - len(out))
    return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", required=True, help="stock boot.img (header template)")
    ap.add_argument("--kernel", required=True)
    ap.add_argument("--ramdisk")
    ap.add_argument("--dtb", required=True, help="bare FDT (mtk header is added)")
    ap.add_argument("--cmdline", help="override cmdline")
    ap.add_argument("--size", type=int, default=32 * 1024 * 1024,
                    help="pad image to partition size (default 32 MiB, boot_a)")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    ref = read_ref(a.ref)
    kernel = open(a.kernel, "rb").read()
    ramdisk = open(a.ramdisk, "rb").read() if a.ramdisk else b""
    dtb = wrap_dtb(open(a.dtb, "rb").read())
    cmdline = a.cmdline.encode() if a.cmdline else ref["cmdline"]

    img = build(ref, kernel, ramdisk, dtb, cmdline, a.size)
    open(a.out, "wb").write(img)
    print(f"wrote {a.out}: {len(img)} bytes "
          f"(kernel {len(kernel)}, ramdisk {len(ramdisk)}, dtb {len(dtb)})")
    print(f"cmdline: {cmdline.decode(errors='replace')}")


if __name__ == "__main__":
    main()
