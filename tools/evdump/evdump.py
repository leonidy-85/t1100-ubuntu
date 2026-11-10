#!/usr/bin/env python3
"""evdump.py — decode /dev/input/eventN without evtest (none in the rootfs).

Reads struct input_event (64-bit: 16-byte timeval + u16 type + u16 code +
s32 value = 24 bytes) and prints one line per event, with ABS_MT codes
resolved. Ends a frame with SYNC_REPORT on EV_SYN/SYN_REPORT.

Usage: evdump.py /dev/input/event2 [seconds]
"""
import struct
import sys
import time

FMT = "@llHHi"
SZ = struct.calcsize(FMT)

ABS = {
    0x00: "ABS_X", 0x01: "ABS_Y", 0x02: "ABS_PRESSURE",
    0x2f: "ABS_MT_SLOT", 0x30: "ABS_MT_TOUCH_MAJOR",
    0x31: "ABS_MT_TOUCH_MINOR", 0x32: "ABS_MT_WIDTH_MAJOR",
    0x33: "ABS_MT_WIDTH_MINOR", 0x34: "ABS_MT_ORIENTATION",
    0x35: "ABS_MT_POSITION_X", 0x36: "ABS_MT_POSITION_Y",
    0x37: "ABS_MT_TOOL_TYPE", 0x38: "ABS_MT_BLOB_ID",
    0x39: "ABS_MT_TRACKING_ID", 0x3a: "ABS_MT_PRESSURE",
}
BTN = {0x14a: "BTN_TOUCH", 0x145: "BTN_TOOL_FINGER"}

dev = sys.argv[1]
limit = float(sys.argv[2]) if len(sys.argv) > 2 else 60.0
fd = open(dev, "rb", buffering=0)
print(f"# listening on {dev}, {limit:g}s", flush=True)
t0 = time.time()
while time.time() - t0 < limit:
    buf = fd.read(SZ)
    if len(buf) < SZ:
        break
    sec, usec, typ, code, val = struct.unpack(FMT, buf)
    if typ == 0:
        if code == 0:
            print(f"{sec}.{usec:06d} SYN_REPORT", flush=True)
        continue
    if typ == 3:
        print(f"{sec}.{usec:06d} EV_ABS  {ABS.get(code, hex(code)):20s} {val}",
              flush=True)
    elif typ == 1:
        print(f"{sec}.{usec:06d} EV_KEY  {BTN.get(code, hex(code)):20s} {val}",
              flush=True)
    elif typ == 0:
        pass
    else:
        print(f"{sec}.{usec:06d} type={typ} code={code} value={val}", flush=True)
