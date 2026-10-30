# Ubuntu + KDE: план rootfs и первого запуска

Цель: загруженная Ubuntu 24.04 с KDE Plasma (Wayland) на T1100.

## Что уже есть

- `build/rootfs/rootfs-t1100-base.tar.gz` — Ubuntu-base **24.04.3 arm64**:
  hostname `t1100`, `systemd-networkd` (usb0 → `10.42.66.66/29`), `ssh`,
  root/`12345`.
- Разметка (GPT): `p54 userdata` ≈ 52 ГБ — сейчас LVM `sailfish`
  (`sailfish-root` 9 ГБ + `sailfish-home` 41 ГБ). Под Ubuntu её и используем.
- Канал в ядро (когда USB починим): RNDIS `usb0` + `telnetd`/sshd.

## Шаги

1. **Ядро**: eMMC (`mmcblk0`) + USB-периферия (`/sys/class/udc`) — текущая работа
   `bringup`. Критерий: `mmcblk0` в `/proc/partitions`, `udc` в sysfs.
2. **Разложить rootfs** из рекавери (там есть `dd`, `mkfs`? проверить; иначе
   через USB/`nc`):
   - `vgchange -ay` не нужен: LVM сносим;
   - `wipefs -a /dev/mmcblk0p54`, `mkfs.ext4 -L ubuntu /dev/mmcblk0p54`;
   - монтировать, распаковать `rootfs-t1100-base.tar.gz`.
3. **cmdline**: `root=/dev/mmcblk0p54 rootwait rw console=tty0
   pstore.backend=ramoops ramoops.mem_address=0x54410000 …`
   (initramfs пока оставить — он даёт RNDIS/telnetd даже при проблемах с root).
4. **Первый запуск**: systemd, `systemd-networkd` (usb0), `sshd` → зайти
   `root@10.42.66.66`.
5. **KDE**: `apt update && apt install -y plasma-desktop plasma-workspace-wayland
   sddm` (+ `mesa-utils`, `glmark2-es2-wayland`); нужен интернет — NAT с хоста
   через `usb0` (host: `ip_forward`+`nftables masquerade`).
6. **Порядок зависимостей**: KDE не запустится без KMS. Поэтому после rootfs —
   DRM/KMS (панель BOE TV110XUM через IT6112, `refs/it6112/`), затем panfrost,
   затем `sddm`+Plasma.

## Риски

- LVM `sailfish` содержит текущую Aurora-home: снос необратим (Aurora при этом
  остаётся загрузочной, но данные `/home` пропадут) → делать только после
  явного подтверждения владельца.
- KDE на 4 ГБ RAM и Mali-G72 — ок для Plasma Wayland, но нужен рабочий KMS.
