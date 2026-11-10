#!/usr/bin/env python3
"""hxreset.py — power the touch rail, reset the HX83102E, read its frame.

The rail switch (GPIO163) is owned by the kernel driver, so it drops when the
driver is unbound; this keeps it claimed while it pokes the chip through
/dev/i2c-0 by hand (docs/touch-hx83102e.md §7).

  - GPIO163: output high for as long as this process lives (AVDD on)
  - GPIO158: reset pulse, low 12 ms then high
  - AHB reads (0x900000a8 / 0x9000005c / 0x900000d0) via sub-address 0x00
  - burst on (0x13=0x31, 0x0d=0x10), write(0x11, 0x00), read reg 0x30

Usage: hxreset.py [bus] [addr] [hold_seconds]
"""
import ctypes
import fcntl
import os
import struct
import sys
import time

I2C_RDWR = 0x0707
I2C_M_RD = 1
GPIO_GET_LINEHANDLE_IOCTL = 0xC16CB403
GPIO_HANDLE_SET_LINE_VALUES_IOCTL = 0xC040B409
GPIOHANDLE_REQUEST_OUTPUT = 2


class LineRequest(ctypes.Structure):
    _fields_ = [("lineoffsets", ctypes.c_uint32 * 64),
                ("flags", ctypes.c_uint32),
                ("default_values", ctypes.c_uint8 * 64),
                ("consumer_label", ctypes.c_char * 32),
                ("lines", ctypes.c_uint32),
                ("fd", ctypes.c_uint32)]


class LineData(ctypes.Structure):
    _fields_ = [("values", ctypes.c_uint8 * 64)]


class Msg(ctypes.Structure):
    _fields_ = [("addr", ctypes.c_uint16), ("flags", ctypes.c_uint16),
                ("len", ctypes.c_uint16), ("pad", ctypes.c_uint16),
                ("buf", ctypes.c_void_p)]


class IoctlData(ctypes.Structure):
    _fields_ = [("msgs", ctypes.POINTER(Msg)), ("nmsgs", ctypes.c_uint32)]


class Line:
    def __init__(self, chip, line, value, label):
        req = LineRequest()
        req.lineoffsets[0] = line
        req.flags = GPIOHANDLE_REQUEST_OUTPUT
        req.default_values[0] = value
        req.lines = 1
        req.consumer_label = label.encode()
        fcntl.ioctl(chip, GPIO_GET_LINEHANDLE_IOCTL, req)
        self.fd = req.fd

    def set(self, value):
        d = LineData()
        d.values[0] = value
        fcntl.ioctl(self.fd, GPIO_HANDLE_SET_LINE_VALUES_IOCTL, d)


class Dev:
    def __init__(self, bus, addr):
        self.fd = os.open("/dev/i2c-%d" % bus, os.O_RDWR)
        self.addr = addr

    def _xfer(self, wr, rd_len):
        out = (ctypes.c_uint8 * rd_len)()
        w = (ctypes.c_uint8 * len(wr))(*wr)
        nmsg = 2 if rd_len else 1
        m = (Msg * nmsg)()
        m[0].addr = self.addr
        m[0].flags = 0
        m[0].len = len(wr)
        m[0].buf = ctypes.addressof(w)
        if rd_len:
            m[1].addr = self.addr
            m[1].flags = I2C_M_RD
            m[1].len = rd_len
            m[1].buf = ctypes.addressof(out)
        fcntl.ioctl(self.fd, I2C_RDWR, IoctlData(m, nmsg))
        return bytes(bytearray(out))

    def w(self, reg, val):
        self._xfer([reg, val & 0xFF], 0)

    def w32(self, reg, val):
        self._xfer([reg] + list(struct.pack("<I", val)), 0)

    def r(self, reg, n):
        return self._xfer([reg], n)

    def ahb(self, addr, n=4):
        self.w32(0x00, addr)
        self.w32(0x0c, 0x00)
        return self.r(0x08, n)

    def ahb_w32(self, addr, val):
        self.w32(0x00, addr)
        self.w32(0x0c, 0x01)
        self.w32(0x08, val)
        self.w32(0x0c, 0x00)


def main():
    bus = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    addr = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0x48
    hold = float(sys.argv[3]) if len(sys.argv) > 3 else 3.0

    chip = open("/dev/gpiochip0", "rb+", buffering=0)
    avdd = Line(chip.fileno(), 163, 1, "t1100-ts-avdd")
    rst = Line(chip.fileno(), 158, 1, "t1100-ts-rst")
    print("AVDD (163) = 1", flush=True)

    rst.set(0)
    time.sleep(0.012)
    rst.set(1)
    print("reset (158): low 12 ms, high", flush=True)
    time.sleep(0.15)

    d = Dev(bus, addr)
    print("ICID  (0x900000d0) = %s" % d.ahb(0x900000d0).hex(" "), flush=True)
    print("FW    (0x900000a8) = %s" % d.ahb(0x900000a8).hex(" "), flush=True)
    print("SENSE (0x9000005c) = %s" % d.ahb(0x9000005c).hex(" "), flush=True)

    print("reg 0x13 = %s, reg 0x0d = %s" % (d.r(0x13, 1).hex(),
                                            d.r(0x0d, 1).hex()), flush=True)
    d.w(0x13, 0x31)
    d.w(0x0d, 0x10)
    d.w(0x11, 0x00)
    print("burst on, 0x11=0", flush=True)

    for name, reg, ln in (("0x30", 0x30, 56), ("0x38", 0x38, 8),
                          ("0x3a", 0x3a, 6), ("0x40", 0x40, 16)):
        v = d.r(reg, ln)
        print("reg %s: %s  sum=0x%02x" % (name, v.hex(" "), sum(v) & 0xFF),
              flush=True)

    # mainline's address, for the A/B
    print("AHB 0x90000030: %s" % d.ahb(0x90000030, 16).hex(" "), flush=True)

    time.sleep(hold)


main()
