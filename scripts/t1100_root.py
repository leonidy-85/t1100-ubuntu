#!/usr/bin/env python3
"""Run a command as root on the Fplus T1100 over SSH (pexpect driver).

Aurora has no sudo: `devel-su` opens an interactive root shell and reads the
device-lock code from a tty, so the session must be driven by a pty. Output
between the __BEGIN__/__END__ markers is printed on stdout.

Usage: scripts/t1100_root.sh 'id; ls /sys/fs/pstore'

Env: T1100_HOST (default 172.17.141.62), T1100_USER (defaultuser),
     T1100_PASS (device-lock code, default 12345),
     T1100_KEY  (default ~/.ssh/id_ed25519), T1100_TIMEOUT (default 60)

This is the pexpect implementation; scripts/t1100_root.exp is the legacy
expect one and is used only if pexpect is unavailable.
"""
import os
import sys

import pexpect

HOST = os.environ.get("T1100_HOST", "172.17.141.62")
USER = os.environ.get("T1100_USER", "defaultuser")
PASS = os.environ.get("T1100_PASS", "12345")
KEY = os.environ.get("T1100_KEY", os.path.expanduser("~/.ssh/id_ed25519"))
TIMEOUT = int(os.environ.get("T1100_TIMEOUT", "60"))


def die(msg, code):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def main():
    if len(sys.argv) < 2:
        die("usage: t1100_root.py '<single-line command>'", 2)
    command = sys.argv[1]

    child = pexpect.spawn(
        "ssh",
        ["-tt", "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
         "-o", "IdentityAgent=none", "-o", "StrictHostKeyChecking=no",
         "-o", "ConnectTimeout=10", "-i", KEY, f"{USER}@{HOST}", "devel-su"],
        encoding="utf-8",
        timeout=TIMEOUT,
    )
    try:
        i = child.expect([r"[Pp]assword:", pexpect.EOF, pexpect.TIMEOUT])
        if i != 0:
            die("no password prompt (host unreachable or key rejected)", 2)
        child.sendline(PASS)

        i = child.expect([r"[#$] ", "Auth failed", pexpect.EOF, pexpect.TIMEOUT])
        if i == 1:
            die("devel-su: authentication failed (wrong T1100_PASS?)", 3)
        if i != 0:
            die("no root shell", 4)

        # The root shell is interactive, so delimit the output with markers and
        # filter prompts/echoed command in this process.
        child.sendline("echo __BEGIN__")
        child.expect(r"__BEGIN__")
        child.sendline(command)
        child.sendline("echo __END__")
        child.expect(r"__END__")
        child.sendline("exit")
        child.expect(pexpect.EOF)
    finally:
        child.close()

    text = child.before or ""
    # Drop everything up to the last __BEGIN__ and anything after __END__.
    start = text.rfind("__BEGIN__")
    if start >= 0:
        text = text[start + len("__BEGIN__"):]
    end = text.find("__END__")
    if end >= 0:
        text = text[:end]

    for line in text.replace("\r", "").splitlines():
        s = line.strip()
        if not s or s == command.strip():
            continue
        print(line)


if __name__ == "__main__":
    main()
