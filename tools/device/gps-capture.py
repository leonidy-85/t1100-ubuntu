#!/usr/bin/env python3
"""Снять обмен mnld <-> /dev/stpgps без потерь (pty-релей).

Зачем не FIFO. В ноябре 2026 обмен снимали, подменив /dev/stpgps на FIFO.
FIFO — это одна общая очередь: mnld открывает её O_RDWR и читает свой же
поток, релей читает ту же очередь. Байты «воруют» друг у друга, поэтому из
~28 чанков DSP-патча в дамп попало 7 (seq 2,5,7,9,11,13,24 с дырами).

pty-пара устроена иначе: slave отдаётся mnld, master держит релей, и каждый
байт идёт ровно в одну сторону.

    /dev/stpgps -> /dev/pts/N          (slave, mnld)
    релей <-> master <-> /dev/stpgps.real  (gps_drv)

Запуск (на планшете, root):

    /root/gps-capture.py --seconds 45 --start-mnld

Результат:
    <log>.txt      — таймлайн кадров (тип/seq/длина)
    <log>.mnld.bin — чистый поток mnld -> chip
    <log>.chip.bin — чистый поток chip -> mnld

По завершении /dev/stpgps возвращается на место (в т.ч. по SIGINT/SIGTERM).
"""

import argparse
import atexit
import os
import pty
import select
import signal
import subprocess
import sys
import termios
import time
import tty

DEV = "/dev/stpgps"
REAL = "/dev/stpgps.real"
BIONIC = "/opt/bionic"
MNLD_CMD = (
    "export LD_LIBRARY_PATH=/vendor/lib:/system/lib:/vendor/lib/hw; "
    "export LD_PRELOAD=/vendor/lib/libpropfix.so; "
    "exec /system/bin/mnld"
)
HAL_CMD = (
    "export LD_LIBRARY_PATH=/vendor/lib:/system/lib:/vendor/lib/hw; "
    "export LD_PRELOAD=/vendor/lib/libpropfix.so; "
    "exec /system/bin/gps_hal_test"
)

NAMES = {
    0xFE08: "config",
    0xFE0C: "patch",
    0xFE05: "keepalive",
    0xFE02: "?",
    0xFE31: "status",
    0xFE32: "ack",
}


def wrap(payload):
    """MNL-кадр: AA F0 + len LE16 + payload + AA 0F."""
    return b"\xaa\xf0" + len(payload).to_bytes(2, "little") + payload + b"\xaa\x0f"


class FakeChip:
    """Ответы реального CONSYS, чтобы mnld дошёл до конца инициализации.

    Данные сняты с чипа T1100: на config (0xFE08) он отвечает status
    (0xFE31). ACK на чанки патча пока не воспроизводим — сначала смотрим,
    шлёт ли mnld все чанки без ACK.
    """

    CONFIG_OK = bytes.fromhex("31fe000046150000000000009801")

    def response(self, payload):
        typ = payload[0] | (payload[1] << 8)
        if typ == 0xFE08:
            return self.CONFIG_OK
        return None


class Capture:
    def __init__(self, base, responder=None):
        self.responder = responder
        self.txt = open(base + ".txt", "w", buffering=1)
        self.bins = {
            "mnld": open(base + ".mnld.bin", "wb"),
            "chip": open(base + ".chip.bin", "wb"),
        }
        self.bufs = {"mnld": bytearray(), "chip": bytearray()}
        self.stats = {"mnld": {}, "chip": {}}
        self.t0 = time.time()
        self.pending = bytearray()  # байты для mnld (режим fake-chip)

    def _log(self, msg):
        print(f"{time.time() - self.t0:8.3f} {msg}")
        self.txt.write(f"{time.time() - self.t0:8.3f} {msg}\n")

    def feed(self, direction, data):
        self.bins[direction].write(data)
        self.bins[direction].flush()
        b = self.bufs[direction]
        b += data
        while True:
            i = b.find(b"\xaa\xf0")
            if i < 0:
                # держим только возможное начало маркера
                del b[: max(0, len(b) - 1)]
                return
            del b[:i]
            if len(b) < 4:
                return
            ln = b[2] | (b[3] << 8)
            end = 4 + ln
            if len(b) < end + 2:
                return
            if bytes(b[end:end + 2]) != b"\xaa\x0f":
                del b[:2]  # ложный маркер, ищем дальше
                continue
            payload = bytes(b[4:end])
            del b[: end + 2]
            self._frame(direction, payload)

    def _frame(self, direction, p):
        typ = p[0] | (p[1] << 8)
        seq = (p[2] | (p[3] << 8)) if len(p) >= 4 else -1
        name = NAMES.get(typ, "")
        self.stats[direction][typ] = self.stats[direction].get(typ, 0) + 1
        self._log(
            f"{direction:4s} type=0x{typ:04x} seq={seq:5d} len={len(p):4d} {name}"
        )
        if direction == "mnld" and self.responder is not None:
            resp = self.responder.response(p)
            if resp:
                self.pending += wrap(resp)
                self._log(f"fake chip -> type=0x{resp[0] | (resp[1] << 8):04x} "
                          f"len={len(resp)}")

    def close(self):
        self._log("== итого")
        for direction in ("mnld", "chip"):
            parts = [
                f"0x{t:04x}({NAMES.get(t, '?')})={n}"
                for t, n in sorted(self.stats[direction].items())
            ]
            self._log(f"{direction:4s}: " + (", ".join(parts) or "пусто"))
        for f in [self.txt, *self.bins.values()]:
            f.close()


def restore_device():
    """Вернуть настоящий /dev/stpgps (идемпотентно)."""
    try:
        if os.path.islink(DEV):
            os.unlink(DEV)
        if os.path.exists(REAL):
            os.rename(REAL, DEV)
    except OSError as exc:  # noqa: BLE001 - диагностика важнее
        print(f"restore: {exc}", file=sys.stderr)


def ensure_chroot_mounts():
    os.makedirs(f"{BIONIC}/dev/pts", exist_ok=True)
    for src, dst in (
        ("/dev", f"{BIONIC}/dev"),
        ("/dev/pts", f"{BIONIC}/dev/pts"),
        ("/proc", f"{BIONIC}/proc"),
        ("/sys", f"{BIONIC}/sys"),
        ("/data", f"{BIONIC}/data"),
    ):
        if not os.path.ismount(dst):
            subprocess.run(["mount", "--bind", src, dst], check=False)
    for d in ("/data/vendor/gps", "/data/vendor/log/gps", "/data/agps_supl",
              f"{BIONIC}/data", "/dev/socket"):
        os.makedirs(d, exist_ok=True)


def wait_for_logdw(timeout=5.0):
    end = time.time() + timeout
    while time.time() < end:
        if os.path.exists("/dev/socket/logdw"):
            return True
        time.sleep(0.2)
    return False


def start_mnld():
    subprocess.run(["pkill", "-f", "^/system/bin/mnld"], check=False)
    time.sleep(0.5)
    log = open("/tmp/mnld-capture.log", "wb")
    proc = subprocess.Popen(
        ["chroot", BIONIC, "/system/bin/sh", "-c", MNLD_CMD],
        stdout=log,
        stderr=subprocess.STDOUT,
    )
    return proc


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seconds", type=float, default=45.0)
    ap.add_argument("--start-mnld", action="store_true",
                    help="поднять mnld в chroot (иначе запустить вручную)")
    ap.add_argument("--fake-chip", action="store_true",
                    help="не трогать CONSYS: отвечать mnld canned-кадрами чипа")
    ap.add_argument("--start-hal", action="store_true",
                    help="запустить gps_hal_test (без него mnld не открывает порт)")
    ap.add_argument("--log", default="/root/gps-capture")
    ap.add_argument("--no-restore", action="store_true")
    args = ap.parse_args()

    if os.path.islink(DEV):
        os.unlink(DEV)
    if os.path.exists(REAL):
        if os.path.exists(DEV):
            # мусор от прошлого запуска: настоящий узел уже на месте
            os.unlink(REAL)
        else:
            os.rename(REAL, DEV)
    if not os.path.exists(DEV):
        sys.exit(f"нет {DEV} — загружен ли gps_drv?")

    # Настоящий узел убираем в сторону: драйвер продолжает жить, open() по
    # новому пути идёт в pty.
    os.rename(DEV, REAL)
    atexit.register(restore_device)

    master, slave = pty.openpty()
    tty.setraw(slave)
    tty.setraw(master)
    attrs = termios.tcgetattr(slave)
    attrs[0] &= ~(termios.IXON | termios.IXOFF | termios.IXANY)
    termios.tcsetattr(slave, termios.TCSANOW, attrs)

    slave_name = os.ttyname(slave)
    os.symlink(slave_name, DEV)
    print(f"{DEV} -> {slave_name} (реальный узел: {REAL})")

    ensure_chroot_mounts()
    if args.start_mnld:
        if not wait_for_logdw():
            print("нет /dev/socket/logdw — mnld может упасть без логов",
                  file=sys.stderr)
        mnld = start_mnld()
        print(f"mnld запущен, pid {mnld.pid}")
    else:
        mnld = None
        input("нажмите Enter, когда mnld будет запущен... ")

    hal = None
    if args.start_hal:
        time.sleep(1.0)
        hal = subprocess.Popen(
            ["chroot", BIONIC, "/system/bin/sh", "-c", HAL_CMD],
            stdout=open("/tmp/gps-hal-capture.log", "wb"),
            stderr=subprocess.STDOUT,
        )
        print(f"gps_hal_test запущен, pid {hal.pid}")

    cap = Capture(args.log, FakeChip() if args.fake_chip else None)
    if args.fake_chip:
        real = None
        print("== fake chip: CONSYS не открывается, ответы синтетические")
    else:
        real = os.open(REAL, os.O_RDWR | os.O_NONBLOCK)
    os.set_blocking(master, False)

    stop = {"flag": False}

    def on_signal(signum, _frame):
        stop["flag"] = True

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)

    to_chip = bytearray()
    to_mnld = bytearray()
    deadline = time.time() + args.seconds
    print(f"== запись {args.seconds:.0f} с -> {args.log}.*")

    while not stop["flag"] and time.time() < deadline:
        watch = [master] if real is None else [master, real]
        try:
            ready, _, _ = select.select(watch, [], [], 0.2)
        except InterruptedError:
            continue
        if master in ready:
            try:
                data = os.read(master, 65536)
            except BlockingIOError:
                data = b""
            if data:
                cap.feed("mnld", data)
                to_chip += data
        if real is not None and real in ready:
            try:
                data = os.read(real, 65536)
            except BlockingIOError:
                data = b""
            if data:
                cap.feed("chip", data)
                to_mnld += data
        if cap.pending:
            to_mnld += cap.pending
            cap.pending.clear()
        if to_chip:
            if real is None:
                to_chip.clear()  # fake chip: писать некуда, только лог
            else:
                try:
                    n = os.write(real, to_chip)
                    del to_chip[:n]
                except BlockingIOError:
                    pass
        if to_mnld:
            try:
                n = os.write(master, to_mnld)
                del to_mnld[:n]
            except BlockingIOError:
                pass

    if mnld is not None and mnld.poll() is None:
        mnld.terminate()
    if hal is not None:
        if hal.poll() is None:
            hal.terminate()
        subprocess.run(["pkill", "-f", "^/system/bin/gps_hal_test"], check=False)
    if real is not None:
        os.close(real)
    os.close(master)
    os.close(slave)
    cap.close()

    if args.no_restore:
        print(f"оставлено как есть: {DEV} -> {slave_name}, настоящий узел {REAL}")
        atexit.unregister(restore_device)
    else:
        restore_device()
        print(f"{DEV} восстановлен")
    atexit.unregister(restore_device)


if __name__ == "__main__":
    main()
