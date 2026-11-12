#!/usr/bin/env python3
import base64
import re
import sys

import pexpect

LOG = "/tmp/opencode/recovery_header.log"
OUT = "/tmp/opencode/boot_a_header.b64"

child = pexpect.spawn(
    "telnet 10.42.66.66", timeout=20, encoding="utf-8", codec_errors="replace"
)
log = open(LOG, "w")
child.logfile = log

try:
    child.expect(r"Enter\]:")
    child.sendline("3")
    child.expect(r"\[y/N\]")
    child.send("y")
    child.sendline("")

    idx = child.expect(
        [r"devicelock", r"/\s*#", r"Code", r"code", pexpect.TIMEOUT], timeout=12
    )
    if idx in (0, 2, 3):
        child.sendline("12345")
        child.expect(r"/\s*#", timeout=10)
    elif idx == 4:
        print("no shell prompt after y", file=sys.stderr)
        sys.exit(2)

    child.sendline("echo SHELL_READY")
    child.expect("SHELL_READY")
    child.expect(r"/\s*#")

    cmd = (
        "P=/dev/block/by-name/boot_a; [ -e $P ] || P=/dev/mmcblk0p29; "
        "D=HDR; A=START; B=END; echo ${D}${A}; "
        "dd if=$P bs=1724 count=1 2>/dev/null | base64 -w 0; "
        "echo; echo ${D}${B}"
    )
    child.sendline(cmd)
    child.expect("HDRSTART", timeout=10)
    child.expect("HDREND", timeout=20)

    raw = child.before
    compact = re.sub(r"\s+", "", raw)
    matches = re.findall(r"[A-Za-z0-9+/=]{1000,}", compact)
    if not matches:
        print("base64 blob not found", file=sys.stderr)
        print(repr(raw[:500]), file=sys.stderr)
        sys.exit(3)
    b64 = max(matches, key=len)
    data = base64.b64decode(b64)
    print(f"base64_len={len(b64)} bytes={len(data)}")
    if len(data) != 1724:
        print(f"unexpected length {len(data)}, expected 1724", file=sys.stderr)
        sys.exit(4)
    if data[:8] != b"ANDROID!":
        print(f"unexpected magic {data[:8]!r}", file=sys.stderr)
        sys.exit(5)
    with open(OUT, "w") as f:
        f.write(b64)
    with open("build/ref_boot_a_header.img", "wb") as f:
        f.write(data)
    print("saved build/ref_boot_a_header.img")
    print("magic:", data[:8].decode())
finally:
    try:
        child.sendline("exit")
        child.close(force=True)
    except Exception:
        pass
    log.close()
