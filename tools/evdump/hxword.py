#!/usr/bin/env python3
"""hxword.py — read the Himax event stack as 14 x 4-byte words (56 B frame).

Hypothesis: the HX83102E pops the event FIFO in 4-byte words, so a single
56-byte streaming read returns filler, while 14 word reads assemble a frame.

Usage: hxword.py <bus> <addr> <seconds> [reg]
"""
import ctypes
import fcntl
import os
import sys
import time

I2C_RDWR = 0x0707
I2C_M_RD = 1


class Msg(ctypes.Structure):
    _fields_ = [("addr", ctypes.c_uint16), ("flags", ctypes.c_uint16),
                ("len", ctypes.c_uint16), ("pad", ctypes.c_uint16),
                ("buf", ctypes.c_void_p)]


class IoctlData(ctypes.Structure):
    _fields_ = [("msgs", ctypes.POINTER(Msg)), ("nmsgs", ctypes.c_uint32)]


class Dev:
    def __init__(self, bus, addr):
        self.fd = os.open("/dev/i2c-%d" % bus, os.O_RDWR)
        self.addr = addr

    def xfer(self, reg, length):
        out = (ctypes.c_uint8 * length)()
        w = (ctypes.c_uint8 * 1)(reg)
        m = (Msg * 2)()
        m[0].addr = self.addr
        m[0].flags = 0
        m[0].len = 1
        m[0].buf = ctypes.addressof(w)
        m[1].addr = self.addr
        m[1].flags = I2C_M_RD
        m[1].len = length
        m[1].buf = ctypes.addressof(out)
        fcntl.ioctl(self.fd, I2C_RDWR, IoctlData(m, 2))
        return bytes(bytearray(out))


def main():
    bus = int(sys.argv[1], 0)
    addr = int(sys.argv[2], 0)
    secs = float(sys.argv[3])
    reg = int(sys.argv[4], 0) if len(sys.argv) > 4 else 0x30
    d = Dev(bus, addr)
    print("# %s 14 x 4B reads at reg 0x%02x, %gs" %
          (time.strftime("%H:%M:%S"), reg, secs), flush=True)
    t0 = time.time()
    n = 0
    last = None
    while time.time() - t0 < secs:
        words = [d.xfer(reg, 4) for _ in range(14)]
        frame = b"".join(words)
        n += 1
        if frame == last:
            continue
        last = frame
        if any(frame):
            print("%s %3d: %s sum=0x%02x" %
                  (time.strftime("%H:%M:%S"), n, frame.hex(" "),
                   sum(frame) & 0xFF), flush=True)
    print("# %d frames read" % n, flush=True)


main()
