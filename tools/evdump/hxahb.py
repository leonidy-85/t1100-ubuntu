#!/usr/bin/env python3
"""hxahb.py — HX83102E register/AHB access exactly as the vendor driver does.

Protocol (docs/touch-hx83102e.md §1):

  AHB read (hx83102_register_read):
      W 13 31 | W 0D 10 | W 00 <addr LE4> | W 0C 00 | R 08 <4 bytes>

  AHB write (himax_mcu_register_write / hx83102_register_write):
      W 00 <addr LE4> <data LE4>          <- ONE 9-byte i2c transaction

  frame (83102E slot 0xA9A450): plain register burst read of 0x30.

Usage:
  hxahb.py read  <ahb_addr> [len]        # len > 4 enables burst, like the driver
  hxahb.py write <ahb_addr> <value>      # 9-byte transaction
  hxahb.py reg   <sub> [len]             # raw register read
  hxahb.py sense_on                      # AHB 0x9000005c = 0, 10 ms, then state
  hxahb.py frame [count] [interval_ms]   # read reg 0x30 (56 B), print distinct
"""
import ctypes
import fcntl
import os
import struct
import sys
import time

I2C_RDWR = 0x0707
I2C_M_RD = 1
BUS = int(os.environ.get("HX_BUS", "0"))
ADDR = int(os.environ.get("HX_ADDR", "0x48"), 0)


class Msg(ctypes.Structure):
    _fields_ = [("addr", ctypes.c_uint16), ("flags", ctypes.c_uint16),
                ("len", ctypes.c_uint16), ("pad", ctypes.c_uint16),
                ("buf", ctypes.c_void_p)]


class IoctlData(ctypes.Structure):
    _fields_ = [("msgs", ctypes.POINTER(Msg)), ("nmsgs", ctypes.c_uint32)]


class Dev:
    def __init__(self):
        self.fd = os.open("/dev/i2c-%d" % BUS, os.O_RDWR)

    def _xfer(self, wr, rd_len, retries=3):
        last = None
        for _ in range(retries):
            try:
                return self._xfer1(wr, rd_len)
            except OSError as e:
                last = e
                time.sleep(0.005)
        raise last

    def _xfer1(self, wr, rd_len):
        out = (ctypes.c_uint8 * max(rd_len, 1))()
        w = (ctypes.c_uint8 * len(wr))(*wr)
        nmsg = 2 if rd_len else 1
        m = (Msg * nmsg)()
        m[0].addr = ADDR
        m[0].flags = 0
        m[0].len = len(wr)
        m[0].buf = ctypes.addressof(w)
        if rd_len:
            m[1].addr = ADDR
            m[1].flags = I2C_M_RD
            m[1].len = rd_len
            m[1].buf = ctypes.addressof(out)
        fcntl.ioctl(self.fd, I2C_RDWR, IoctlData(m, nmsg))
        return bytes(bytearray(out))[:rd_len]

    def w(self, reg, val):
        self._xfer([reg, val & 0xFF], 0)

    def r(self, reg, n):
        return self._xfer([reg], n)

    def ahb_read(self, addr, ln=4):
        self.w(0x13, 0x31)
        self.w(0x0d, 0x10)
        self._xfer([0x00] + list(struct.pack("<I", addr & 0xFFFFFFFF)), 0)
        self.w(0x0c, 0x00)
        return self.r(0x08, ln)

    def ahb_write(self, addr, val):
        # ONE transaction: sub 0x00, addr LE4, data LE4
        self._xfer([0x00] + list(struct.pack("<I", addr & 0xFFFFFFFF)) +
                   list(struct.pack("<I", val & 0xFFFFFFFF)), 0)


def show(tag, v):
    print("%-22s %s   (le32=%s)" % (tag, v.hex(" "),
                                    hex(int.from_bytes(v[:4], "little"))
                                    if len(v) >= 4 else "-"), flush=True)


def main():
    d = Dev()
    cmd = sys.argv[1] if len(sys.argv) > 1 else "read"

    if cmd == "read":
        addr = int(sys.argv[2], 0)
        ln = int(sys.argv[3]) if len(sys.argv) > 3 else 4
        show("ahb %08x" % addr, d.ahb_read(addr, ln))
    elif cmd == "write":
        addr = int(sys.argv[2], 0)
        val = int(sys.argv[3], 0)
        d.ahb_write(addr, val)
        print("wrote ahb %08x = 0x%08x (9-byte transaction)" % (addr, val),
              flush=True)
    elif cmd == "reg":
        sub = int(sys.argv[2], 0)
        ln = int(sys.argv[3]) if len(sys.argv) > 3 else 1
        show("reg %02x" % sub, d.r(sub, ln))
    elif cmd == "sense_on":
        d.w(0x13, 0x31)
        d.w(0x0d, 0x10)
        d.ahb_write(0x9000005C, 0x00000000)
        print("AHB 0x9000005c = 0 (sense on), waiting 10 ms", flush=True)
        time.sleep(0.010)
        show("a8 (want 0x05)", d.ahb_read(0x900000a8))
        show("5c", d.ahb_read(0x9000005c))
        show("icid", d.ahb_read(0x900000d0))
    elif cmd == "frame":
        n = int(sys.argv[2]) if len(sys.argv) > 2 else 40
        iv = (int(sys.argv[3]) if len(sys.argv) > 3 else 50) / 1000.0
        last = None
        for i in range(n):
            v = d.r(0x30, 56)
            if v != last:
                last = v
                print("%s #%d %s sum=0x%02x" %
                      (time.strftime("%H:%M:%S"), i, v.hex(" "),
                       sum(v) & 0xFF), flush=True)
            time.sleep(iv)
        print("# %d reads done" % n, flush=True)


main()
