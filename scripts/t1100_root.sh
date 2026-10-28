#!/usr/bin/env bash
# Run a command as root on the Fplus T1100 over SSH.
#
# Aurora has no sudo; `devel-su` opens an interactive root shell and reads the
# device-lock code from a tty, so the session is driven by expect
# (scripts/t1100_root.exp). Output between the __BEGIN__/__END__ markers is
# returned; shell prompts and the echoed command are filtered out.
#
# Usage: scripts/t1100_root.sh 'id; ls /sys/fs/pstore'
# Env:   T1100_HOST (default 172.17.141.62), T1100_USER (defaultuser),
#        T1100_PASS (device-lock code, default 12345),
#        T1100_KEY  (default ~/.ssh/id_ed25519)
#
# For bulk data prefer writing files on the device and fetching them with scp:
#   scripts/t1100_root.sh 'mkdir -p /tmp/p; cp /sys/firmware/fdt /tmp/p/; chmod -R a+rX /tmp/p'
#   scp -r defaultuser@$T1100_HOST:/tmp/p/* build/device/
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
HOST=${T1100_HOST:-172.17.141.62}
USER=${T1100_USER:-defaultuser}
PASS=${T1100_PASS:-12345}
KEY=${T1100_KEY:-$HOME/.ssh/id_ed25519}

CMD=${1:?usage: t1100_root.sh '<single-line command>'}

expect "$HERE/t1100_root.exp" "$HOST" "$USER" "$KEY" "$PASS" "$CMD" 2>/dev/null |
  tr -d '\r' |
  awk '/^__BEGIN__$/{f=1;next} /^__END__$/{f=0} f'
