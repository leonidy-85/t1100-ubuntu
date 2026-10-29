#!/usr/bin/env python3
"""Run shell commands in Aurora Recovery v2.0 over telnet (root).

USB RNDIS: host 10.42.66.67/32, tablet 10.42.66.66, `telnet 10.42.66.66:23`.
Env: T1100_RECOVERY_HOST, T1100_PASS (device-lock code).

Menu: 3) Shell -> "Are you really SURE? [y/N]" -> devicelock code.
Note: the SURE prompt reads a single character, so 'y' must be sent WITHOUT a
trailing newline, otherwise the leftover empty line is consumed as the code.
"""
import sys
import time
import telnetlib

import os
HOST = os.environ.get("T1100_RECOVERY_HOST", "10.42.66.66")
CODE = os.environ.get("T1100_PASS", "12345")


def drain(t, seconds):
    end = time.time() + seconds
    buf = b""
    while time.time() < end:
        try:
            d = t.read_very_eager()
        except Exception:
            d = b""
        if d:
            buf += d
        else:
            time.sleep(0.05)
    return buf


def read_until(t, marker, timeout=60):
    end = time.time() + timeout
    buf = b""
    while time.time() < end:
        try:
            d = t.read_very_eager()
        except Exception:
            d = b""
        if d:
            buf += d
            if marker in buf:
                return buf
        else:
            time.sleep(0.05)
    return buf


def open_shell():
    t = telnetlib.Telnet(HOST, 23, timeout=10)
    time.sleep(0.8)
    read_until(t, b"Enter]:", 8)
    t.write(b"3\n")
    read_until(t, b"[y/N]", 8)
    t.write(b"y")
    read_until(t, b"devicelock", 8)
    t.write(CODE.encode() + b"\n")
    out = read_until(t, b"/ #", 15)
    if b"Code accepted" not in out:
        print(out.decode("utf-8", "replace"), file=sys.stderr)
        sys.exit("recovery: devicelock code rejected")
    return t


def run_bg(t, name, cmd, timeout=120):
    """Run a command detached, log to /tmp/<name>.log, poll for rc=NN.

    Needed for anything that reads/writes several MB: a long foreground command
    makes telnetd stop delivering output, so the session looks hung (the command
    itself is fine - it finishes without a session).
    """
    path = f"/tmp/{name}.log"
    start = (
        f"rm -f {path}; setsid sh -c '{cmd} > {path} 2>&1; "
        f"echo rc=$? >> {path}' </dev/null >/dev/null 2>&1 & echo started"
    )
    t.write(("echo __B__; " + start + "; echo __E__\r\n").encode())
    read_until(t, b"__E__", 15)
    end = time.time() + timeout
    while time.time() < end:
        time.sleep(1)
        t2 = open_shell()
        t2.write(("cat " + path + " 2>/dev/null; echo __X__\r\n").encode())
        out = read_until(t2, b"__X__", 15).decode("utf-8", "replace")
        t2.write(b"exit\n")
        t2.close()
        if "rc=" in out:
            i = out.find("rc=")
            print(out[i:].splitlines()[0])
            body = "\n".join(
                l for l in out[:i].splitlines() if not l.startswith("cat /tmp/")
            )
            print(body.strip())
            return
    sys.exit(f"timeout waiting for {path}")


def main():
    cmds = sys.argv[1:]
    if not cmds:
        sys.exit("usage: recovery_telnet.py 'cmd1' 'cmd2' ...")
    if cmds[0] == "--bg":
        t = open_shell()
        run_bg(t, cmds[1], cmds[2], timeout=int(cmds[3]) if len(cmds) > 3 else 120)
        t.write(b"exit\n")
        t.close()
        return
    t = open_shell()
    for cmd in cmds:
        t.write(("echo __B__; " + cmd + "; echo __E__\r\n").encode())
        out = read_until(t, b"__E__", 120).decode("utf-8", "replace")
        start = out.find("__B__")
        end = out.rfind("__E__")
        if start >= 0:
            out = out[start + 5:end if end >= 0 else None]
        body = out.replace("\r", "")
        # drop the echoed command line and prompt echo
        lines = [l for l in body.splitlines() if l.strip() not in ("__B__", "__E__", "echo __B__; " + cmd + "; echo __E__")]
        print("\n".join(lines))
        print("---", cmd)
    t.write(b"exit\n")
    t.close()


if __name__ == "__main__":
    main()
