#!/usr/bin/env python3
"""MNL probe: send a few crafted frames to /dev/stpgps and dump all replies.

The driver's read() blocks until the requested size is available, so the
device is opened O_NONBLOCK and reads go through os.read().

Usage: mnl-probe.py [seconds-per-step]
"""
import os
import select
import struct
import sys
import time

DEV = "/dev/stpgps"
KEEPALIVE = bytes.fromhex("05fe3200000100 3f01".replace(" ", ""))
CONFIG = bytes.fromhex(
    "08fe1a0000000000c301a502000000008c4c0080048000001c00000000000500"
    "9d006f3c8889a2040000dc00c10028005c4a1e00c53728005c4a8f6503000000"
    "2800ff008000470064005000d8005000bb0003003c006f00890088000200fb00"
    "010000004849000001004e4fb015"
)


def wrap(payload):
    return b"\xaa\xf0" + struct.pack("<H", len(payload)) + payload + b"\xaa\x0f"


def dump(tag, data):
    print("%s len=%d %s" % (tag, len(data), data.hex(" ")), flush=True)


def write_all(fd, data, seconds=2.0):
    end = time.time() + seconds
    view = memoryview(data)
    while view:
        if time.time() > end:
            print("  write timeout, %d bytes left" % len(view), flush=True)
            return False
        _, w, _ = select.select([], [fd], [], 0.2)
        if not w:
            continue
        try:
            n = os.write(fd, view)
        except BlockingIOError:
            continue
        view = view[n:]
    return True


def read_all(fd, seconds):
    end = time.time() + seconds
    buf = b""
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.2)
        if not r:
            continue
        try:
            chunk = os.read(fd, 4096)
        except BlockingIOError:
            continue
        if not chunk:
            continue
        buf += chunk
        while True:
            i = buf.find(b"\xaa\xf0")
            if i < 0:
                buf = b""
                break
            if len(buf) < i + 4:
                buf = buf[i:]
                break
            term = buf.find(b"\xaa\x0f", i + 4)
            if term < 0:
                buf = buf[i:]
                break
            frame = buf[i:term + 2]
            buf = buf[term + 2:]
            payload = frame[4:-2]
            dump("  rx type=0x%04x seq=%d" % (
                struct.unpack_from("<H", payload, 0)[0],
                struct.unpack_from("<H", payload, 2)[0] if len(payload) >= 4 else -1), frame)


def main():
    secs = float(sys.argv[1]) if len(sys.argv) > 1 else 2.0
    fd = os.open(DEV, os.O_RDWR | os.O_NONBLOCK)
    time.sleep(2.0)

    steps = [
        ("1: keepalive only", KEEPALIVE),
        ("2: unknown type 0xfe99", bytes.fromhex("99fe0100deadbeef")),
        ("3: config", CONFIG),
        ("4: keepalive again", KEEPALIVE),
    ]
    for name, payload in steps:
        print("== %s" % name, flush=True)
        if not write_all(fd, wrap(payload)):
            break
        read_all(fd, secs)

    os.close(fd)


if __name__ == "__main__":
    main()
