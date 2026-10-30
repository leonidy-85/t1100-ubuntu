# Ubuntu rootfs для T1100

`build/rootfs/rootfs-t1100-base.tar.gz` — Ubuntu-base 24.04.3 (arm64) с:
hostname `t1100`, `systemd-networkd` (usb0 = 10.42.66.66/29), `ssh`, root/12345.

Дальше: разложить на eMMC (userdata/LVM) и `apt install plasma-desktop` +
`plasma-workspace-wayland` после того, как заработают сеть и eMMC.

Сборка: `build/rootfs/` содержит распакованный `root/`; пересобрать —
`tar czf rootfs-t1100-base.tar.gz -C root .`
