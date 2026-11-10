#!/usr/bin/env python3
"""hxwin.py — print every change of an N-byte register window of the Himax IC.

Usage: hxwin.py <bus> <addr> <seconds> [reg] [len]
  default reg 0x32, len 64
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
    reg = int(sys.argv[4], 0) if len(sys.argv) > 4 else 0x32
    ln = int(sys.argv[5]) if len(sys.argv) > 5 else 64
    d = Dev(bus, addr)
    print("# %s window 0x%02x len %d for %gs" %
          (time.strftime("%H:%M:%S"), reg, ln, secs), flush=True)
    t0 = time.time()
    last = None
    n = 0
    while time.time() - t0 < secs:
        try:
            v = d.xfer(reg, ln)
        except OSError as e:
            print("%s i2c error: %s (retrying)" %
                  (time.strftime("%H:%M:%S"), e), flush=True)
            time.sleep(0.3)
            continue
        n += 1
        if v == last:
            continue
        last = v
        print("%s %s sum=0x%02x" %
              (time.strftime("%H:%M:%S.%f")[:-3], v.hex(" "), sum(v) & 0xFF),
              flush=True)


main()
