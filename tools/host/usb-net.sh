#!/usr/bin/env bash
# Give the host side of the T1100 USB link its address and probe the device.
#
# The tablet exposes RNDIS (mainline) or the Jolla recovery RNDIS; in both
# cases the device lives on 10.42.66.66/29 and the host takes .67.
#
# Usage: tools/host/usb-net.sh [up|ping|ssh|telnet]
set -u
HOST_IP=10.42.66.67/29
DEV_IP=10.42.66.66

iface() {
  # newest USB-ethernet interface, whatever the name looks like
  for i in $(ls /sys/class/net); do
    case "$i" in
      enx*|usb*|eth*) [ -e "/sys/class/net/$i/device" ] && echo "$i" && return ;;
    esac
  done
}

up() {
  i=$(iface)
  [ -n "$i" ] || { echo "no USB net interface"; return 1; }
  # NetworkManager manages new USB NICs and drops a manual address a minute
  # later (symptom: ping works, then "No route to host"). Unmanage it first.
  command -v nmcli >/dev/null && nmcli device set "$i" managed no 2>/dev/null
  ip addr flush dev "$i" 2>/dev/null
  ip addr add "$HOST_IP" dev "$i"
  ip link set "$i" up
  echo "host: $i $HOST_IP"
}

case "${1:-up}" in
  up)     up ;;
  ping)   ping -c 2 -W 1 "$DEV_IP" ;;
  ssh)    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$DEV_IP" ;;
  telnet) telnet "$DEV_IP" 2323 ;;
  *)      echo "usage: $0 [up|ping|ssh|telnet]" >&2; exit 2 ;;
esac
