#!/bin/sh
# One-shot diagnostics on the running T1100 (Ubuntu, mainline 6.12 + KMS).
# Run over SSH; prints a compact report. Safe: read-only except for the USB
# power/control pin, the backlight brightness and the fb0 test pattern.
set -u
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@10.42.66.66"

$SSH 'sh -s' <<'EOF'
echo "=== kernel"; uname -r
echo "=== usb autosuspend pin"
echo on > /sys/bus/platform/devices/11201000.usb/power/control 2>/dev/null
cat /sys/bus/platform/devices/11201000.usb/power/control 2>/dev/null
mkdir -p /etc/systemd/system
cat > /etc/systemd/system/t1100-usb-nosuspend.service <<'UNIT'
[Unit]
Description=Keep the T1100 mtu3 controller out of runtime autosuspend
After=sysinit.target
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for d in /sys/bus/platform/devices/11201000.usb; do echo on > $d/power/control; done'
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
UNIT
systemctl enable --now t1100-usb-nosuspend.service 2>&1 | tail -1

echo "=== drm"
ls /sys/class/drm/ | tr '\n' ' '; echo
for f in status enabled modes; do printf 'card0-DSI-1/%s: ' $f; cat /sys/class/drm/card0-DSI-1/$f 2>/dev/null | tr '\n' ' '; echo; done
echo "=== backlight"
for b in /sys/class/backlight/*; do echo "$b: $(cat $b/brightness)/$(cat $b/max_brightness) $(cat $b/actual_brightness 2>/dev/null)";

  echo 1023 > $b/brightness; echo "after: $(cat $b/brightness)"; done
echo "=== pwm"
ls /sys/class/pwm/ 2>/dev/null
echo "=== regulators (panel)"
mount -t debugfs none /sys/kernel/debug 2>/dev/null
grep -iE "dsv|vpos|vneg" /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | head -6
echo "=== i2c devices"
ls /sys/bus/i2c/devices/ | grep -E "3-" | tr '\n' ' '; echo
echo "=== drm debugfs"
ls /sys/kernel/debug/dri/0/ 2>/dev/null | tr '\n' ' '; echo
echo "=== dmesg: drm/dsi/cmdq/iommu"
dmesg | grep -iE "mediatek-drm|mtk_dsi|dsi@|it6112|cmdq|iommu|fault|vblank|atomic|mmsys|rdma|ovl" | tail -25
echo "=== dmesg: errors"
dmesg | grep -iE "error|fail|timeout|warn" | tail -15
EOF
