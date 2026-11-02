#!/usr/bin/env bash
# Watch the host's USB subsystem for T1100 events during a boot test.
#
# What it tells us:
#   * "0e8d:2000" appearing again = the tablet reset and its preloader
#     re-enumerated -> the bootloader never handed control to our kernel
#     (this includes "LK rejected the DTB": LK's watchdog then resets the SoC).
#   * no preloader after the reboot, and later "1d6b:0104" (our RNDIS gadget)
#     or a new usb0/enx* interface = the kernel ran and brought the gadget up.
#
# Usage: tools/host/watch-usb.sh [seconds]     (default 180)
set -u
SECS=${1:-180}
echo "watching for ${SECS}s; Ctrl-C to stop"
timeout "$SECS" journalctl -k -f -o short-iso 2>/dev/null \
  | grep --line-buffered -E "usb 1-|New USB device|idVendor|rndis|cdc_ether|mtu3|usb0|0e8d" \
  | while IFS= read -r line; do
      printf '%s\n' "$line"
      case "$line" in
        *0e8d:2000*) echo "  -> preloader: board reset / LK did not start the kernel" ;;
        *1d6b:0104*) echo "  -> our RNDIS gadget enumerated" ;;
      esac
    done
