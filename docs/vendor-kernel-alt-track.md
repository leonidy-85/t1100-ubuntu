# Track B: ALT Linux на вендорском ядре Aurora 4.14

Дата: 2026-11-24
Статус: отдельный трек, не начат; первый шаг — read-only инвентарь T800.

## Цель

Запустить ALT Linux (glibc/systemd, Wayland) поверх **штатного вендорского ядра
Aurora 4.14.186** (T800 / T1100, MT6771), не переписывая драйверы на mainline.
Это альтернатива Track A (mainline 6.12 + Ubuntu/ALT), а не замена ему.

## Почему

- На T800 вендорское 4.14-ядро уже имеет рабочие panel/touch/GPU/VDEC/Wi-Fi;
  Aurora сама запускает Wayland на этом ядре.
- Не нужен mainline bring-up SoC и (отдельно) не нужен SCP/VDEC mainline-путь.
- VDEC остаётся вендорским AP-side (`/dev/Vcodec` + 32-bit bionic HAL).
- T800/T1100, по предварительным данным, отличаются в основном panel/touch.

## Архитектура

- Boot: вендорский kernel + DTB + собственный initramfs (ALT) + ALT rootfs
  на разделе/eMMC; загрузчик/AVB — проверить.
- Userspace ALT: systemd/glibc, Wayland; display/touch через DRM/evdev;
  Wi-Fi/BT — вендорские драйверы/прошивки.
- Android-слой: `/vendor` HAL, bionic chroot для VDEC (и, при необходимости,
  GPU Mali); panfrost на 4.14 не будет.

## Риски/что проверить

- AVB/verified boot T800, unlocked bootloader, собственный boot image;
  без полного бэкапа ничего не прошивать.
- Конфиг ядра для systemd/ALT: CGROUPS, DEVTMPFS, EXT4, INITRD, TMPFS,
  PROC/SYSFS, UNIX/NET/PACKET, INPUT_EVDEV, DRM, VT/FB_CONSOLE, NAMESPACES,
  SECCOMP, OVERLAY_FS/SQUASHFS/LOOP, NETFILTER/NFT, USB gadget/configfs,
  FW_LOADER — снять `/proc/config.gz`.
- Android HAL: Mali bionic, VDEC `/dev/Vcodec` 32-bit, Wi-Fi/BT/camera/audio;
  ALT glibc не использует их напрямую — нужен bionic chroot/прослойка.
- 4.14 EOL: нет обновлений безопасности; Android-специфичные интерфейсы.
- ALT rootfs уже есть; модули вендора — в `/vendor/lib/modules`, не mainline.

## Первый безопасный шаг (read-only, T800)

1. `uname -a`, `/proc/cmdline`, `/proc/config.gz`, `/proc/partitions`, `mounts`.
2. `/proc/device-tree` и `/sys/firmware/fdt`; panel/touch/regulators/Wi-Fi.
3. `getprop`, `/vendor/lib/modules`, `/vendor/lib` HAL, boot/recovery layout,
   состояние AVB/verified boot.
4. Сравнить с T1100 (mainline DTS и стоковым 4.14), оценить, что переносится.
5. Ничего не прошивать; сначала полный бэкап boot/recovery/rootfs.

## Критерий успеха

ALT userspace грузится до консоли и Wayland на вендорском 4.14; работают
panel/touch (и, желательно, Wi-Fi); VDEC — через bionic HAL; mainline не
требуется. Camera/audio — вне первого этапа.

## Связь с Track A

- Track A: mainline 6.12 + Ubuntu/ALT, mtk-drm/panfrost; VDEC mainline
  ограничен прошивкой SCP.
- Track B: вендорское 4.14 + ALT; быстрее к рабочему desktop, но старее ядро
  и Android-зависимости.
- T800 trace (`/tmp/opencode/omsvc.trace`) остаётся эталоном для VDEC в обоих
  треках.
