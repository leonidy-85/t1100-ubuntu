#!/usr/bin/env python3
"""hxraw.py — poll the Himax touch FIFO without the kernel driver.

Usage: hxraw.py <bus> <addr> <seconds> [mode]
  mode = direct (default): read 56 bytes from register 0x30 (hx83112b path)
  mode = ahb: AHB-indirect read of 0x90060000 (hx83100a path)

Prints every new non-empty frame, so the event-frame layout of this chip can
be read back from real fingers.  Only used for diagnosis: the kernel driver
must be unbound first (echo 0-0048 > /sys/bus/i2c/drivers/*/unbind).
"""
import ctypes
import fcntl
import os
import struct
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
        """One transaction: write reg pointer, then read length bytes."""
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

    def write_reg32(self, reg, val):
        b = (ctypes.c_uint8 * 5)()
        b[0] = reg
        for i in range(4):
            b[1 + i] = (val >> (8 * i)) & 0xFF
        m = (Msg * 1)()
        m[0].addr = self.addr
        m[0].flags = 0
        m[0].len = 5
        m[0].buf = ctypes.addressof(b)
        fcntl.ioctl(self.fd, I2C_RDWR, IoctlData(m, 1))


def main():
    bus = int(sys.argv[1], 0)
    addr = int(sys.argv[2], 0)
    secs = float(sys.argv[3])
    mode = sys.argv[4] if len(sys.argv) > 4 else "direct"

    d = Dev(bus, addr)
    print("# %s polling /dev/i2c-%d 0x%02x mode=%s" %
          (time.strftime("%H:%M:%S"), bus, addr, mode), flush=True)

    def frame():
        if mode == "ahb":
            d.write_reg32(0x13, 0x31)
            d.write_reg32(0x0d, 0x10)
            d.write_reg32(0x00, 0x90060000)
            d.write_reg32(0x0c, 0x00)
            return d.xfer(0x08, 56)
        return d.xfer(0x30, 56)

    t0 = time.time()
    reads = 0
    last = None
    frames = 0
    while time.time() - t0 < secs:
        try:
            f = frame()
        except OSError as e:
            print("ioctl error: %s" % e, flush=True)
            time.sleep(0.2)
            continue
        reads += 1
        if f == last:
            continue
        last = f
        if any(f):
            frames += 1
            print("%s %3d: %s  sum=0x%02x" %
                  (time.strftime("%H:%M:%S"), frames, f.hex(" "), sum(f) & 0xFF),
                  flush=True)
    print("# %d reads, %d distinct non-empty frames" % (reads, frames), flush=True)


main()
