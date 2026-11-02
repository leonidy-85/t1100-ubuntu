#!/usr/bin/env python3
"""T1100 Jolla recovery driver: shell commands, upload/download over the USB link.

The recovery exports no SSH by default and its /tmp is 10 MB, so files move over
a plain TCP socket: the host listens, the device connects with busybox nc.

Usage:
    tools/host/recovery.py sh '<shell commands>'      # run, print output
    tools/host/recovery.py get <device-path> <local>  # device -> host
    tools/host/recovery.py put <local> <device-path>  # host -> device
    tools/host/recovery.py reboot                     # leave the shell, reboot

Env: REC_HOST (10.42.66.66), HOST_IP (10.42.66.67), REC_PORT_BASE (9900)

Notes
- The rootfs of this tablet is gone, so the device-lock prompt is bypassed and
  no lock code is needed; the menu's "are you sure" prompt is answered with "y"
  (one char, no newline).
- Every command is echoed back by the shell, so the end marker is chosen not to
  appear in the command itself.

Replaces scripts/recovery_telnet.py (Leonid, commit 10474ab) on this host: that
one imports `telnetlib`, which Python 3.13 removed, so it fails at import time.
"""
import os, socket, sys, threading, time, pexpect

REC_HOST = os.environ.get('REC_HOST', '10.42.66.66')
HOST_IP = os.environ.get('HOST_IP', '10.42.66.67')
PORT = int(os.environ.get('REC_PORT_BASE', '9900'))
END = 'T1100-REC-END'


def shell(timeout=60, quiet=False):
    c = pexpect.spawn(f'telnet {REC_HOST}', timeout=timeout, encoding='utf-8',
                      codec_errors='replace')
    if not quiet:
        c.logfile_read = sys.stdout
    c.expect('desired action', timeout=20)
    c.sendline('3')
    c.expect(r'\? \[Y/n\]', timeout=20)
    c.send('y')
    time.sleep(0.3)
    c.sendline('')
    c.expect(r'/ # ', timeout=40)
    return c


def run(cmds, timeout=300):
    c = shell(timeout=timeout)
    c.sendline(f'{{ {cmds}; }} 2>&1; echo {END}')
    c.expect(r'\n' + END + r'\r?\n', timeout=timeout)
    c.sendline('exit')
    time.sleep(0.3)
    c.close(force=True)


def _serve(path, writing):
    """Wait for the device to connect and stream one file."""
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('0.0.0.0', PORT))
    s.listen(1)
    s.settimeout(120)
    conn, addr = s.accept()
    n = 0
    if writing:
        with open(path, 'rb') as f:
            while True:
                b = f.read(1 << 20)
                if not b:
                    break
                conn.sendall(b)
                n += len(b)
        conn.shutdown(socket.SHUT_WR)
    else:
        with open(path, 'wb') as f:
            while True:
                b = conn.recv(1 << 20)
                if not b:
                    break
                f.write(b)
                n += len(b)
    conn.close()
    s.close()
    print(f'[net] {n} bytes via {addr[0]}')


def transfer(cmd, path, writing, wait=180):
    pre = os.environ.get('PRE', '')
    if pre:
        cmd = f'{pre} {cmd}'
    t = threading.Thread(target=_serve, args=(path, writing), daemon=True)
    t.start()
    time.sleep(0.5)
    run(cmd, timeout=wait + 60)
    t.join(wait)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    what = sys.argv[1]
    if what == 'sh':
        run(sys.argv[2])
    elif what == 'get':
        dev, local = sys.argv[2], sys.argv[3]
        transfer(f'nc {HOST_IP} {PORT} < {dev}', local, False)
    elif what == 'put':
        local, dev = sys.argv[2], sys.argv[3]
        transfer(f'nc {HOST_IP} {PORT} | dd of={dev} bs=1M conv=fsync', local, True)
    elif what == 'reboot':
        run('sync; reboot -f')
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
