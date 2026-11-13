#!/usr/bin/env python3
"""Minimal telnet client for Jolla Recovery (py3.13 dropped telnetlib).

Replacement for scripts/recovery_telnet.py on python>=3.13; same menu flow
(3) Shell -> "Are you really SURE? [Y/n]" -> y -> devicelock code), but with a
raw socket and no marker parsing. Copy to /tmp/opencode on the host machine.

Usage: rec.py 'cmd1' 'cmd2' ...
Env: T1100_RECOVERY_HOST (10.42.66.66), T1100_PASS (12345)
"""
import os
import socket
import sys
import time

HOST = os.environ.get("T1100_RECOVERY_HOST", "10.42.66.66")
PORT = int(os.environ.get("T1100_RECOVERY_PORT", "23"))
CODE = os.environ.get("T1100_PASS", "12345")


def drain(s, seconds=1.0):
    s.settimeout(0.3)
    end = time.time() + seconds
    buf = b""
    while time.time() < end:
        try:
            d = s.recv(4096)
            if not d:
                break
            buf += d
        except socket.timeout:
            continue
        except OSError:
            break
    return buf


def wait_for(s, needles, timeout=20):
    """Read until one of the byte needles appears; return (buf, which)."""
    s.settimeout(0.4)
    end = time.time() + timeout
    buf = b""
    while time.time() < end:
        try:
            d = s.recv(4096)
            if not d:
                break
            buf += d
        except socket.timeout:
            continue
        except OSError:
            break
        for n in needles:
            if n in buf:
                return buf, n
    return buf, None


def negot(initial):
    """Answer the few telnet IAC sequences busybox/telnetd sends."""
    out = bytearray()
    i = 0
    while i < len(initial):
        if initial[i] == 0xFF and i + 2 < len(initial):
            cmd, opt = initial[i + 1], initial[i + 2]
            if cmd in (0xFB, 0xFD):        # WILL / DO -> refuse (WONT / DONT)
                out += bytes([0xFF, 0xFC if cmd == 0xFB else 0xFE, opt])
            elif cmd in (0xFC, 0xFE):
                out += bytes([0xFF, 0xFE if cmd == 0xFC else 0xFC, opt])
            i += 3
        else:
            i += 1
    return bytes(out)


def open_shell():
    s = socket.create_connection((HOST, PORT), timeout=10)
    buf = drain(s, 1.5)
    s.sendall(negot(buf))
    buf += drain(s, 0.5)
    s.sendall(b"3\n")                       # 3) Shell
    buf2, _ = wait_for(s, [b"[Y/n]", b"[y/N]", b"/ #"], 10)
    if b"[Y/n]" in buf2 or b"[y/N]" in buf2:
        s.sendall(b"y")                     # no newline: prompty reads one char
        buf3, hit = wait_for(s, [b"devicelock", b"/ #", b"Code"], 10)
        if b"/ #" not in buf3:
            s.sendall(CODE.encode() + b"\n")
            buf4, _ = wait_for(s, [b"/ #", b"Wrong", b"Denied"], 15)
            if b"/ #" not in buf4:
                sys.exit("recovery: shell not reached:\n" +
                         (buf2 + buf3 + buf4).decode("utf-8", "replace"))
    s.sendall(b"export PS1='#'\n")
    drain(s, 0.4)
    return s


def run(s, cmd, timeout=60):
    s.sendall(("echo __B__; " + cmd + "; echo __E__\n").encode())
    buf, hit = wait_for(s, [b"__E__"], timeout)
    txt = buf.decode("utf-8", "replace").replace("\r", "")
    start = txt.find("__B__")
    end = txt.rfind("__E__")
    if start >= 0:
        txt = txt[start + 5:end if end > start else None]
    lines = [l for l in txt.splitlines()
             if l.strip() and l.strip() != cmd and l.strip() != "echo __B__; " + cmd + "; echo __E__"]
    print("\n".join(lines))
    print("--- %s" % cmd)


def main():
    s = open_shell()
    for c in sys.argv[1:]:
        run(s, c)
    s.sendall(b"exit\n")
    s.close()


if __name__ == "__main__":
    main()
