#!/usr/bin/env python3
"""hxscan.py — watch every 8-byte window of the Himax register block for
content that changes, so the real event-stack register can be found by touch.

Usage: hxscan.py <bus> <addr> <seconds>
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


REGS = [r for r in range(0x10, 0xA0, 8)]


def main():
    bus = int(sys.argv[1], 0)
    addr = int(sys.argv[2], 0)
    secs = float(sys.argv[3])
    d = Dev(bus, addr)
    last = {r: None for r in REGS}
    print("# %s watching regs %s" % (time.strftime("%H:%M:%S"),
                                     " ".join("0x%02x" % r for r in REGS)),
          flush=True)
    t0 = time.time()
    while time.time() - t0 < secs:
        for r in REGS:
            try:
                v = d.xfer(r, 8)
            except OSError as e:
                print("reg 0x%02x err %s" % (r, e), flush=True)
                continue
            if v != last[r]:
                last[r] = v
                if any(v):
                    print("%s reg 0x%02x: %s" %
                          (time.strftime("%H:%M:%S"), r, v.hex(" ")), flush=True)


main()
