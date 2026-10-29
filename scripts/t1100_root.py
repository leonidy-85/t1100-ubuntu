#!/usr/bin/env python3
"""Run a command as root on the Fplus T1100 over SSH (pexpect driver).

Aurora has no sudo: `devel-su` opens an interactive root shell and reads the
device-lock code from a tty, so the session must be driven by a pty. Output
between the __BEGIN__/__END__ markers is printed on stdout.

Usage: scripts/t1100_root.sh 'id; ls /sys/fs/pstore'

Env: T1100_HOST        (default 172.17.141.62)
     T1100_USER        (default defaultuser)
     T1100_SSH_PASS    (ssh login password; default = T1100_PASS)
     T1100_PASS        (devel-su device-lock code; default 12345)
     T1100_TIMEOUT     (default 60)

scripts/t1100_root.exp is the legacy expect implementation and is used only if
pexpect is unavailable.
"""
import os
import sys

import pexpect

HOST = os.environ.get("T1100_HOST", "172.17.141.62")
USER = os.environ.get("T1100_USER", "defaultuser")
PASS = os.environ.get("T1100_PASS", "12345")
SSH_PASS = os.environ.get("T1100_SSH_PASS", PASS)
TIMEOUT = int(os.environ.get("T1100_TIMEOUT", "60"))

PASSWORD = r"[Pp]assword[^\n]*: *"
PROMPT = r"[#$] $"


def die(msg, code):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def login(child):
    """Authenticate ssh, then devel-su; leaves the child at a root prompt."""
    i = child.expect([PASSWORD, PROMPT, pexpect.EOF, pexpect.TIMEOUT])
    if i == 0:                    # ssh login password
        child.sendline(SSH_PASS)
        i = child.expect([PASSWORD, PROMPT, pexpect.EOF, pexpect.TIMEOUT])
    if i == 0:                    # devel-su device-lock code
        child.sendline(PASS)
        i = child.expect([PROMPT, pexpect.EOF, pexpect.TIMEOUT])
        if i != 0:
            die("devel-su code rejected (wrong T1100_PASS?)", 3)
        return
    if i != 1:
        die("cannot log in (no password prompt / no root shell)", 2)


def main():
    if len(sys.argv) < 2:
        die("usage: t1100_root.py '<single-line command>'", 2)
    command = sys.argv[1]

    # Do not let the desktop keyring (SSH_ASKPASS) answer: it is keyed by host
    # name and returns the wrong password when the device IP changes.
    env = dict(os.environ)
    env.pop("SSH_ASKPASS", None)
    env.pop("SSH_ASKPASS_REQUIRE", None)

    child = pexpect.spawn(
        "ssh",
        ["-tt", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=10",
         "-o", "PreferredAuthentications=password,keyboard-interactive",
         "-o", "PubkeyAuthentication=no", f"{USER}@{HOST}", "devel-su"],
        encoding="utf-8",
        timeout=TIMEOUT,
        env=env,
    )
    try:
        login(child)
        child.sendline("echo __BE''GIN__")
        child.expect(r"__BEGIN__")
        child.sendline(command)
        child.sendline("echo __E''ND__")
        child.expect(r"__END__")
        text = child.before or ""
        child.sendline("exit")
        child.expect(pexpect.EOF)
    finally:
        child.close()

    start = text.find("__BEGIN__")
    if start >= 0:
        text = text[start + len("__BEGIN__"):]
    end = text.find("__END__")
    if end >= 0:
        text = text[:end]

    for line in text.replace("\r", "").splitlines():
        if line.strip() == command.strip():
            continue
        print(line)


if __name__ == "__main__":
    main()
