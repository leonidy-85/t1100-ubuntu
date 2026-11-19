#!/usr/bin/env python3
"""Add the SCP remoteproc nodes to a T1100 boot DTB.

The board DTS deletes &scp because the vendor SCP firmware is not an ELF
image.  The mainline mtk_scp driver can boot the MT8183 linux-firmware
image instead; this script patches an already-built DTB so the experiment
does not need a full kernel rebuild.

It adds (or updates):

  /reserved-memory/memory@50000000   shared-dma-pool, 41 MiB, no-map
  /scp@10500000                      mediatek,mt8183-scp, IRQ 174

Usage:
  scripts/dtb-add-scp.py --dtb p29x/dtb --out scp.dtb
"""

import argparse
import re
import shutil
import subprocess
import sys

SCP_PATH = "/scp@10500000"
MEM_PATH = "/reserved-memory/memory@50000000"
DEFAULT_MEM_BASE = 0x50000000
DEFAULT_MEM_SIZE = 0x2900000
DEFAULT_IRQ = 174
DEFAULT_FW = "mediatek/mt8183/scp.img"


def run(*args):
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL)


def fdtput(dtb, node, prop, *values, type_=None):
    cmd = ["fdtput"]
    if type_:
        cmd += ["-t", type_]
    if values:
        cmd += [dtb, node, prop, *(str(v) for v in values)]
    else:
        cmd += [dtb, node, prop]
    subprocess.run(cmd, check=True)


def dtc(dtb, out):
    subprocess.run(["dtc", "-I", "dtb", "-O", "dts", "-o", out, dtb],
                   check=True, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)


def used_phandles(dtb):
    tmp = "/tmp/dtb-add-scp.dts"
    dtc(dtb, tmp)
    text = open(tmp, encoding="utf-8", errors="replace").read()
    return {int(m, 16) for m in re.findall(r"phandle\s*=\s*<0x([0-9a-fA-F]+)>", text)}


def pick_phandle(dtb):
    used = used_phandles(dtb)
    for cand in range(0x100, 0x400):
        if cand not in used:
            return cand
    raise SystemExit("no free phandle below 0x400")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dtb", required=True, help="input DTB")
    ap.add_argument("--out", required=True, help="output DTB")
    ap.add_argument("--irq", type=lambda x: int(x, 0), default=DEFAULT_IRQ)
    ap.add_argument("--mem-base", type=lambda x: int(x, 0), default=DEFAULT_MEM_BASE)
    ap.add_argument("--mem-size", type=lambda x: int(x, 0), default=DEFAULT_MEM_SIZE)
    ap.add_argument("--firmware", default=DEFAULT_FW)
    args = ap.parse_args()

    for tool in ("fdtput", "fdtget", "dtc"):
        if shutil.which(tool) is None:
            sys.exit(f"missing tool: {tool}")

    shutil.copyfile(args.dtb, args.out)

    phandle = pick_phandle(args.out)

    # reserved-memory region for the SCP DRAM segment (firmware p_paddr
    # 0x50000000).  no-map keeps Linux from touching it.
    subprocess.run(["fdtput", "-c", args.out, MEM_PATH], check=True)
    fdtput(args.out, MEM_PATH, "compatible", "shared-dma-pool", type_="s")
    fdtput(args.out, MEM_PATH, "reg",
           0, hex(args.mem_base), 0, hex(args.mem_size), type_="x")
    fdtput(args.out, MEM_PATH, "phandle", hex(phandle), type_="x")
    # empty property: fdtput without a value creates a zero-length property
    fdtput(args.out, MEM_PATH, "no-map")

    # SCP remoteproc node.  reg/clock names follow the MT8183 binding; the
    # MT6771 block has the same base, cfg window and IRQ.
    subprocess.run(["fdtput", "-c", args.out, SCP_PATH], check=True)
    fdtput(args.out, SCP_PATH, "compatible", "mediatek,mt8183-scp", type_="s")
    fdtput(args.out, SCP_PATH, "reg",
           0, "0x10500000", 0, "0x80000", 0, "0x105c0000", 0, "0x19080",
           type_="x")
    fdtput(args.out, SCP_PATH, "reg-names", "sram", "cfg", type_="s")
    fdtput(args.out, SCP_PATH, "interrupts", 0, hex(args.irq), 4, type_="x")
    fdtput(args.out, SCP_PATH, "clocks", "0x2a", "0x4", type_="x")
    fdtput(args.out, SCP_PATH, "clock-names", "main", type_="s")
    fdtput(args.out, SCP_PATH, "memory-region", hex(phandle), type_="x")
    fdtput(args.out, SCP_PATH, "firmware-name", args.firmware, type_="s")
    fdtput(args.out, SCP_PATH, "status", "okay", type_="s")

    print(f"wrote {args.out}: {SCP_PATH} irq {args.irq}, "
          f"memory @ {args.mem_base:#x} size {args.mem_size:#x}, "
          f"phandle {phandle:#x}")


if __name__ == "__main__":
    main()
