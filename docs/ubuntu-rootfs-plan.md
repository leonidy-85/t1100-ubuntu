# Ubuntu + KDE: план rootfs и первого запуска

Цель: загруженная Ubuntu 24.04 с KDE Plasma (Wayland) на T1100.

> **Статус (10.11.2026):** шаги 1–4 выполнены 31.10–03.11; rootfs живёт на
> `p54`, загружается до systemd, SSH по RNDIS работает. Ниже — исходный план;
> актуальные уточнения — в разделе «Что уже есть».

## Что уже есть

- На планшете: `p54` — **ext4, метка `ubuntu`**, Ubuntu **24.04.3 arm64**,
  systemd, `systemd-networkd` (usb0 → `10.42.66.66/29`), `sshd` (root по ключу
  этого хоста), `t1100-power-guard`; LVM `sailfish` снесён 31.10.2026.
- Базовый архив `build/rootfs/rootfs-t1100-base.tar.gz` (hostname `t1100`,
  root/`12345`) и пересобранный `rootfs-t1100.tar.gz` в локальном дереве
  **сейчас отсутствуют** (`build/` нет); живая копия — на p54.
- Канал в ядро: RNDIS `usb0` + `sshd` (проверено).

## Шаги

1. **Ядро**: eMMC (`mmcblk0`) + USB-периферия (`/sys/class/udc`) — текущая работа
   `bringup`. Критерий: `mmcblk0` в `/proc/partitions`, `udc` в sysfs.
2. **Разложить rootfs** из рекавери (там есть `dd`, `mkfs`? проверить; иначе
   через USB/`nc`):
   - `vgchange -ay` не нужен: LVM снесён 31.10.2026;
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

- LVM `sailfish` содержал Aurora-home: снос был необратим (Aurora осталась
  загрузочной, но данные `/home` пропали). Выполнено 31.10.2026 с явного
  подтверждения владельца.
- KDE на 4 ГБ RAM и Mali-G72 — ок для Plasma Wayland, но нужен рабочий KMS.
