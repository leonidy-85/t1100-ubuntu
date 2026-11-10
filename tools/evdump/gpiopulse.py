#!/usr/bin/env python3
"""gpiopulse.py — drive a SoC GPIO through /dev/gpiochip0 (gpio-cdev v1).

No libgpiod in the tablet rootfs, so the two ioctls are done by hand:

  GPIO_GET_LINEHANDLE_IOCTL       = 0xc16cb403
  GPIO_HANDLE_SET_LINE_VALUES_IOCTL = 0xc040b409

Usage: gpiopulse.py <line> <low_ms> <then_high:0|1>
   e.g. gpiopulse.py 158 20 1     # reset pulse: low 20 ms, then high
"""
import ctypes
import fcntl
import struct
import sys
import time

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


def main():
    line = int(sys.argv[1])
    low_ms = float(sys.argv[2])
    final_high = int(sys.argv[3]) if len(sys.argv) > 3 else 1

    chip = open("/dev/gpiochip0", "rb+", buffering=0)
    req = LineRequest()
    req.lineoffsets[0] = line
    req.flags = GPIOHANDLE_REQUEST_OUTPUT
    req.default_values[0] = 0
    req.lines = 1
    req.consumer_label = b"t1100-touch-rst"
    fcntl.ioctl(chip.fileno(), GPIO_GET_LINEHANDLE_IOCTL, req)
    fd = req.fd
    print("line %d claimed, fd=%d" % (line, fd), flush=True)

    def setval(v):
        d = LineData()
        d.values[0] = v
        fcntl.ioctl(fd, GPIO_HANDLE_SET_LINE_VALUES_IOCTL, d)

    setval(0)
    print("line %d = 0 (reset asserted) for %g ms" % (line, low_ms), flush=True)
    time.sleep(low_ms / 1000.0)
    setval(final_high)
    print("line %d = %d" % (line, final_high), flush=True)
    time.sleep(0.1)


main()
