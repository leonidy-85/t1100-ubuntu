#!/usr/bin/env python3
"""hxinit.py — full vendor init for HX83102E from refs/himax-v2.

Sequence (himax_mcu_power_on_init, docs/touch-hx83102e.md):

  1. AHB 0x100072EC = 0        addr_raw_out_sel  (without it the chip reports
                               "not coordinates" - our 00 03 00 00 frames)
  2. AHB 0x10007F04 = 0        sorting mode
  3. AHB 0x9000005C = 0        sense on, 10 ms
  4. reset GPIO158             5 ms low, 50 ms settle
  5. AHB 0x90000048 = 0xEC     reload_to_active, then read back until
                               data[1] == 0x01 && data[0] == 0xEC
  6. wait AHB 0x900000A8 == 0x05
  7. only then read register 0x30 (56 bytes)

Runs with the kernel driver unbound: GPIO163 is held high by the
regulator-always-on, so the digitizer stays powered.

Usage: hxinit.py [bus] [addr] [frames] [interval_ms]
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


def claim(line, value, label):
    chip = open("/dev/gpiochip0", "rb+", buffering=0)
    req = LineRequest()
    req.lineoffsets[0] = line
    req.flags = GPIOHANDLE_REQUEST_OUTPUT
    req.default_values[0] = value
    req.lines = 1
    req.consumer_label = label.encode()
    fcntl.ioctl(chip.fileno(), GPIO_GET_LINEHANDLE_IOCTL, req)
    return req.fd


def setval(fd, v):
    d = LineData()
    d.values[0] = v
    fcntl.ioctl(fd, GPIO_HANDLE_SET_LINE_VALUES_IOCTL, d)


class Dev:
    def __init__(self, bus, addr):
        self.fd = os.open("/dev/i2c-%d" % bus, os.O_RDWR)
        self.addr = addr

    def _xfer(self, wr, rd_len, retries=3):
        last = None
        for _ in range(retries):
            try:
                out = (ctypes.c_uint8 * max(rd_len, 1))()
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
                return bytes(bytearray(out))[:rd_len]
            except OSError as e:
                last = e
                time.sleep(0.002)
        raise last

    def w(self, reg, val):
        self._xfer([reg, val & 0xFF], 0)

    def r(self, reg, n):
        return self._xfer([reg], n)

    def ahb_read(self, addr, ln=4):
        self.w(0x13, 0x31)
        self.w(0x0d, 0x10)
        self._xfer([0x00] + list(struct.pack("<I", addr)), 0)
        self.w(0x0c, 0x00)
        return self.r(0x08, ln)

    def ahb_write(self, addr, val):
        self._xfer([0x00] + list(struct.pack("<I", addr)) +
                   list(struct.pack("<I", val)), 0)


def main():
    bus = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    addr = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0x48
    nframes = int(sys.argv[3]) if len(sys.argv) > 3 else 30
    ivms = int(sys.argv[4]) if len(sys.argv) > 4 else 50

    d = Dev(bus, addr)
    rst = claim(158, 1, "t1100-ts-rst")

    d.w(0x13, 0x31)
    d.w(0x0d, 0x10)

    print("1. 0x100072EC = 0 (addr_raw_out_sel)", flush=True)
    d.ahb_write(0x100072EC, 0x00000000)
    print("   readback: %s" % d.ahb_read(0x100072EC).hex(" "), flush=True)

    print("2. 0x10007F04 = 0 (sorting mode)", flush=True)
    d.ahb_write(0x10007F04, 0x00000000)
    print("   readback: %s" % d.ahb_read(0x10007F04).hex(" "), flush=True)

    print("3. 0x9000005C = 0 (sense on), 10 ms", flush=True)
    d.ahb_write(0x9000005C, 0x00000000)
    time.sleep(0.010)

    print("4. reset GPIO158: low 5 ms, high, 50 ms", flush=True)
    setval(rst, 0)
    time.sleep(0.005)
    setval(rst, 1)
    time.sleep(0.050)

    print("5. 0x90000048 = 0xEC (reload_to_active)", flush=True)
    d.ahb_write(0x90000048, 0x000000EC)
    time.sleep(0.001)
    for i in range(50):
        v = d.ahb_read(0x90000048)
        if len(v) >= 2 and v[0] == 0xEC and v[1] == 0x01:
            print("   active after %d polls: %s" % (i + 1, v.hex(" ")),
                  flush=True)
            break
        time.sleep(0.001)
    else:
        print("   reload_to_active: no 0x01/0xEC ack, last %s" % v.hex(" "),
              flush=True)

    print("6. wait 0x900000A8 == 0x05", flush=True)
    for i in range(50):
        a8 = d.ahb_read(0x900000a8)
        if a8[0] == 0x05:
            print("   FW ready after %d polls: %s" % (i + 1, a8.hex(" ")),
                  flush=True)
            break
        time.sleep(0.010)
    else:
        print("   FW not ready, last %s" % a8.hex(" "), flush=True)

    print("7. frames (register 0x30)", flush=True)
    last = None
    for i in range(nframes):
        v = d.r(0x30, 56)
        if v != last:
            last = v
            print("%s #%d %s" % (time.strftime("%H:%M:%S"), i, v.hex(" ")),
                  flush=True)
        time.sleep(ivms / 1000.0)


main()
