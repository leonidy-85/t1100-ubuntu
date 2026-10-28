#!/usr/bin/env bash
# Run a command as root on the Fplus T1100 over SSH.
#
# Aurora has no sudo: `devel-su` (setuid wrapper around `script`) opens a root
# *interactive shell* and reads the device-lock code from a tty. So we drive an
# ssh -tt session and type the command on the root shell prompt.
#
# Usage: scripts/t1100_root.sh 'id; cat /proc/iomem | head'
# Env:   T1100_HOST (default 172.17.141.62), T1100_USER (defaultuser),
#        T1100_PASS (device-lock code, default 12345),
#        T1100_KEY  (default ~/.ssh/id_ed25519)
#
# Note: output includes the echoed command line and shell prompts; for bulk data
# prefer writing files on the device and fetching them with scp.
set -euo pipefail

HOST=${T1100_HOST:-172.17.141.62}
USER=${T1100_USER:-defaultuser}
PASS=${T1100_PASS:-12345}
KEY=${T1100_KEY:-$HOME/.ssh/id_ed25519}

CMD=${1:?usage: t1100_root.sh '<single-line command>'}

{
  sleep 5
  printf '%s\r' "$PASS"
  sleep 6
  printf '%s\r' "$CMD"
  sleep 8
  printf 'exit\r'
  sleep 2
} | timeout 180 ssh -tt -o BatchMode=yes -o StrictHostKeyChecking=no \
      -o ConnectTimeout=8 -i "$KEY" "$USER@$HOST" 'devel-su' 2>/dev/null |
  tr -d '\r' |
  sed -e '/^Password: *$/d' -e '/^exit$/d' -e '/^Connection to /d'
