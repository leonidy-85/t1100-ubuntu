#!/usr/bin/env python3
"""Replay a raw MNL byte stream (as written by vendor mnld) into /dev/stpgps.

The stream is a concatenation of frames

    AA F0 <len16> <payload> [tail] AA 0F

where <len16> is NOT the payload length for chunk frames (mnld keeps it at
1406 / 1398 while the real payload is record + variable tail).  Frame borders
are therefore taken from the AA 0F AA F0 separator, not from <len16>.

Usage: gps-replay-raw.py STREAM.bin [SECONDS] [--raw]
"""
import os
import select
import sys
import time

DEV = "/dev/stpgps"
SEP = b"\xaa\x0f\xaa\xf0"


def split_stream(d):
    """Split a raw MNL stream into wire frames (header included)."""
    out = []
    start = 0
    while True:
        i = d.find(SEP, start)
        if i < 0:
            break
        # separator: terminator of current frame + first two bytes of next
        out.append(d[start:i + 2])
        start = i + 2
    if start < len(d):
        out.append(d[start:])
    return out


def frame_type(f):
    p = 4
    return (f[p] | (f[p + 1] << 8)) if len(f) > p + 1 else -1


def main():
    path = sys.argv[1]
    secs = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2].isdigit() else 120
    raw = "--raw" in sys.argv
    frames = split_stream(open(path, "rb").read())
    print("frames=%d sizes=%s" % (len(frames), [len(f) for f in frames]), flush=True)
    fd = os.open(DEV, os.O_RDWR | os.O_NONBLOCK)
    time.sleep(2.0)
    print("open %s ok" % DEV, flush=True)

    buf = b""

    def drain(timeout):
        nonlocal buf
        end = time.time() + timeout
        got = []
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.02)
            if not r:
                continue
            try:
                chunk = os.read(fd, 65536)
            except BlockingIOError:
                continue
            if not chunk:
                continue
            buf += chunk
            while True:
                i = buf.find(b"\xaa\xf0")
                if i < 0:
                    break
                j = buf.find(b"\xaa\x0f", i + 4)
                if j < 0:
                    break
                f = buf[i:j + 2]
                buf = buf[j + 2:]
                got.append(f)
        return got

    # config first, then chunks with ACK pacing, then keepalive
    for idx, f in enumerate(frames):
        typ = frame_type(f)
        os.write(fd, f)
        if typ in (0xfe08, 0xfe0c):
            answers = drain(0.5)
            acks = [a for a in answers if frame_type(a) == 0xfe32]
            other = [a for a in answers if frame_type(a) != 0xfe32]
            print("sent id=0x%02x len=%d acks=%d%s"
                  % (typ, len(f), len(acks),
                     "" if not other else " other=" + ",".join(
                         "0x%02x/%d" % (frame_type(a), len(a)) for a in other)),
                  flush=True)
        else:
            print("sent id=0x%02x len=%d" % (typ, len(f)), flush=True)

    ka = frames[-1]
    start = time.time()
    last_ka = 0.0
    frames_seen = 0
    text = b""
    while time.time() - start < secs:
        now = time.time()
        if now - last_ka >= 1.0:
            try:
                os.write(fd, ka)
            except OSError as e:
                print("keepalive write failed: %s" % e, flush=True)
                break
            last_ka = now
        for f in drain(0.25):
            typ = frame_type(f)
            if typ == 0xfe32:
                continue
            frames_seen += 1
            print("%.3f frame id=0x%02x len=%d %s"
                  % (now - start, typ, len(f), f.hex(" ") if raw else ""), flush=True)
        for line in buf.split(b"\n")[:-1]:
            if b"$" in line:
                print(line.strip().decode("ascii", "replace"), flush=True)
        buf = buf.split(b"\n")[-1] if b"\n" in buf else buf
    print("done frames=%d" % frames_seen, flush=True)


main()
