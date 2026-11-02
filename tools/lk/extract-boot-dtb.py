#!/usr/bin/env python3
"""Extract the device-tree blob that `lk` will hand to the kernel from a boot.img.

Why this exists: the only honest way to answer "does LK get *our* DTB?" is to
compare the blob that is physically inside the flashed image with the DTB built
from the tree. Reading the DTS or the build output is not enough — the image is
what the bootloader sees.

The MTK flavour of the Android v2 header differs from AOSP:
  kernel_size  @0x08 (u32)        page_size    @0x24 (u32)
  ramdisk_size @0x10 (u32)        dtb_size     @0x670 (u32)
  second_size  @0x18 (u32)        dtb_addr     @0x674 (u32, NOT u64)
and the DTB payload is *wrapped*: a 64-byte MTK header (magic 0xD7B7AB1E,
big-endian on disk) followed by the plain FDT.

Usage:
  tools/lk/extract-boot-dtb.py boot.img            # writes boot.dtb next to it
  tools/lk/extract-boot-dtb.py boot.img out.dtb
"""
import hashlib
import struct
import sys

MTK_MAGIC = b'\xd7\xb7\xab\x1e'
MTK_HDR = 0x40


def align(x, p):
    return (x + p - 1) // p * p


def extract(path):
    d = open(path, 'rb').read()
    if d[:8] != b'ANDROID!':
        sys.exit(f'{path}: not an Android boot image')
    ks, ka, rs, ra, ss, sa, ta, ps = struct.unpack_from('<8I', d, 8)
    hv = struct.unpack_from('<I', d, 0x28)[0]
    dsz = struct.unpack_from('<I', d, 0x670)[0]
    da = struct.unpack_from('<I', d, 0x674)[0]
    off = ps + align(ks, ps) + align(rs, ps) + align(ss, ps)
    blob = d[off:off + dsz]
    wrapped = blob[:4] == MTK_MAGIC
    fdt = blob[MTK_HDR:] if wrapped else blob
    info = dict(header_version=hv, kernel_size=ks, kernel_addr=ka,
                ramdisk_size=rs, dtb_size=dsz, dtb_addr=da, page=ps,
                offset=off, wrapped=wrapped)
    return fdt, info, d


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    img = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else img.rsplit('.', 1)[0] + '.dtb'
    fdt, info, d = extract(img)
    open(out, 'wb').write(fdt)
    print(f'image      : {img} ({len(d)} bytes, md5 {hashlib.md5(d).hexdigest()})')
    print(f'header     : v{info["header_version"]}, page {info["page"]}, '
          f'kernel {info["kernel_size"]} @{info["kernel_addr"]:#x}, '
          f'ramdisk {info["ramdisk_size"]}')
    print(f'dtb field  : size {info["dtb_size"]}, addr {info["dtb_addr"]:#x}, '
          f'wrapped={info["wrapped"]} (blob at {info["offset"]})')
    print(f'fdt        : {len(fdt)} bytes, sha256 {hashlib.sha256(fdt).hexdigest()}')
    print(f'written    : {out}')


if __name__ == '__main__':
    main()
