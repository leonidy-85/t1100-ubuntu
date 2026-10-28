#!/usr/bin/env python3
"""Patch an Aurora/MediaTek Android boot image.

Actions:
  --ima-off      cmdline ima_appraise=enforce -> off, and comment the two
                 appraise rules in the initramfs /etc/ima/ima-policy.
  --diehard-off  NOP the `bl security_add_hooks` inside diehard_add_hooks in
                 the (gzip) kernel, so the diehard LSM registers no hooks.

Tested on Fplus T1100 (MT6771, Aurora 5.1.6.110). Symbol VAs come from the
running device:

  echo 0 > /proc/sys/kernel/kptr_restrict
  grep -E ' _stext$| diehard_add_hooks$| security_add_hooks$' /proc/kallsyms

Example:
  boot_patch.py --image boot_a.img --out boot_a_nodiehard.img \
    --ima-off --diehard-off \
    --stext-va 0xffffff848a280800 \
    --diehard-va 0xffffff848b6ade08 \
    --security-va 0xffffff848b6ad4a8

Requires: capstone only for --diehard-off.
"""
import argparse
import gzip
import hashlib
import io
import struct
import sys

NOP = b"\x1f\x20\x03\xd5"  # arm64: nop


def align(x, p):
    return (x + p - 1) // p * p


def parse(image):
    d = open(image, "rb").read()
    if d[:8] != b"ANDROID!":
        sys.exit("not an Android boot image (missing ANDROID! magic)")
    ks, ka, rs, ra, ss, sa, ta, ps = struct.unpack_from("<8I", d, 8)
    hv = struct.unpack_from("<I", d, 0x28)[0]
    dtb_size = struct.unpack_from("<I", d, 0x670)[0] if hv >= 2 else 0
    koff = ps
    roff = ps + align(ks, ps)
    soff = roff + align(rs, ps)
    doff = soff + align(ss, ps)
    kern = d[koff:koff + ks]
    ram = d[roff:roff + rs]
    dtb = d[doff:doff + dtb_size]
    if hv >= 2 and dtb_size and len(dtb) != dtb_size:
        sys.exit("dtb truncated/missing")
    return d, ps, ks, rs, ss, hv, dtb_size, kern, ram, dtb


def patch_ima_cmdline(hdr):
    cmd = hdr[0x40:0x240].split(b"\0")[0].decode()
    if "ima_appraise=off" in cmd:
        return cmd
    if "ima_appraise=enforce" not in cmd:
        sys.exit("ima_appraise=enforce not found in cmdline")
    cmd = cmd.replace("ima_appraise=enforce", "ima_appraise=off")
    enc = cmd.encode()
    hdr[0x40:0x240] = enc + b"\0" * (512 - len(enc))
    return cmd


def patch_ima_ramdisk(ram):
    if ram[:2] != b"\x1f\x8b":
        sys.exit("ramdisk is not gzip; adapt this script")
    raw = gzip.decompress(ram)
    rules = (
        b"appraise func=BPRM_CHECK appraise_type=imasig",
        b"appraise func=FILE_MMAP mask=MAY_EXEC appraise_type=imasig",
    )
    for pat in rules:
        n = raw.count(pat)
        if n != 1:
            sys.exit("expected exactly one %r, got %d" % (pat, n))
        i = raw.index(pat)
        raw = raw[:i] + b"#" + raw[i + 1:]
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb", compresslevel=9, mtime=0) as f:
        f.write(raw)
    return buf.getvalue()


def kernel_raw(kern):
    if kern[:2] == b"\x1f\x8b":
        return gzip.decompress(kern), True
    return kern, False


def kernel_pack(raw, was_gz):
    if not was_gz:
        return raw
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb", compresslevel=9, mtime=0) as f:
        f.write(raw)
    return buf.getvalue()


def patch_diehard(raw, stext_off, stext_va, diehard_va, security_va):
    try:
        from capstone import Cs, CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN
    except ImportError:
        sys.exit("capstone required for --diehard-off (pip install capstone)")
    md = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)
    raw = bytearray(raw)
    off = stext_off + (diehard_va - stext_va)
    target = stext_off + (security_va - stext_va)
    if off < 0 or off + 4 > len(raw):
        sys.exit("diehard_add_hooks offset out of range (check --stext-off / VAs)")
    call = None
    for ins in md.disasm(bytes(raw[off:off + 0x200]), off):
        if ins.mnemonic == "bl":
            try:
                t = int(ins.op_str.lstrip("#"), 16)
            except ValueError:
                continue
            if t == target:
                call = ins.address
                break
        if ins.mnemonic == "ret":
            break
    if call is None:
        sys.exit("bl -> security_add_hooks not found in diehard_add_hooks "
                 "(diehard_off=%#x, target=%#x)" % (off, target))
    raw[call:call + 4] = NOP
    return raw, call


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--ima-off", action="store_true")
    ap.add_argument("--diehard-off", action="store_true")
    ap.add_argument("--stext-off", type=lambda x: int(x, 0), default=0x800,
                    help="_stext file offset in the decompressed kernel (default 0x800)")
    ap.add_argument("--stext-va", type=lambda x: int(x, 0))
    ap.add_argument("--diehard-va", type=lambda x: int(x, 0))
    ap.add_argument("--security-va", type=lambda x: int(x, 0))
    ap.add_argument("--partition-size", type=lambda x: int(x, 0), default=0,
                    help="pad output to this size (e.g. 0x2000000 for a 32 MB boot_a)")
    ap.add_argument("--cmdline-set", action="append", default=[], metavar="KEY=VALUE",
                    help="replace KEY=<old> with KEY=VALUE in the cmdline (repeatable)")
    args = ap.parse_args()

    if not (args.ima_off or args.diehard_off or args.cmdline_set):
        sys.exit("nothing to do: pass --ima-off, --diehard-off and/or --cmdline-set")

    d, ps, ks, rs, ss, hv, dtb_size, kern, ram, dtb = parse(args.image)
    hdr = bytearray(d[:ps])

    raw, was_gz = kernel_raw(kern)
    if args.diehard_off:
        for name in ("stext_va", "diehard_va", "security_va"):
            if getattr(args, name) is None:
                sys.exit("--%s required with --diehard-off" % name.replace("_", "-"))
        raw, call = patch_diehard(raw, args.stext_off, args.stext_va,
                                  args.diehard_va, args.security_va)
        print("diehard: nop bl at kernel-file offset %#x" % call)
    if args.ima_off:
        print("cmdline:", patch_ima_cmdline(hdr))
        ram = patch_ima_ramdisk(ram)
        print("ramdisk: %d -> %d bytes" % (rs, len(ram)))
    if args.cmdline_set:
        import re
        cmd = hdr[0x40:0x240].split(b"\0")[0].decode()
        for kv in args.cmdline_set:
            key, _, val = kv.partition("=")
            if not key or not val:
                sys.exit("bad --cmdline-set %r (want KEY=VALUE)" % kv)
            cmd, n = re.subn(r"(?<!\S)" + re.escape(key) + r"=\S+", key + "=" + val, cmd)
            if n == 0:
                cmd = cmd.rstrip() + " " + key + "=" + val
        enc = cmd.encode()
        if len(enc) > 511:
            sys.exit("cmdline too long")
        hdr[0x40:0x240] = enc + b"\0" * (512 - len(enc))
        print("cmdline:", cmd)

    kern = kernel_pack(raw, was_gz)
    struct.pack_into("<I", hdr, 0x08, len(kern))
    struct.pack_into("<I", hdr, 0x10, len(ram))
    blob = (bytes(hdr)
            + kern + b"\0" * (align(len(kern), ps) - len(kern))
            + ram + b"\0" * (align(len(ram), ps) - len(ram))
            + dtb)
    blob += b"\0" * (align(len(blob), ps) - len(blob))
    if args.partition_size:
        if len(blob) > args.partition_size:
            sys.exit("image %d > partition %d" % (len(blob), args.partition_size))
        blob += b"\0" * (args.partition_size - len(blob))
    open(args.out, "wb").write(blob)
    print("written %s (%d bytes) sha256=%s"
          % (args.out, len(blob), hashlib.sha256(blob).hexdigest()))


if __name__ == "__main__":
    main()
