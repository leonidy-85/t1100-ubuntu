# Передача проекта (состояние на 02.11.2026)

Кратко: **mainline 6.12 грузится на T1100, eMMC работает, установлен Ubuntu 24.04
с systemd; не хватает USB (UDC), KMS/панели, GPU и KDE.**

## Что проверено на железе

| Что | Доказательство |
|---|---|
| LK принимает наш DTB | `python3 refs/pennyos-lk/check-lk-dtb.py <dtb> build/lk/dtbo_a.img build/lk/live.dts` → 9/9 ok |
| Ядро 6.12 загружается | лог: `refs/device/last_kmsg-6.12-first-boot.txt.gz` |
| PMIC/PD | лог `refs/device/last_kmsg-pmic-cycle.txt.gz` |
| eMMC HS400 | `refs/device/last_kmsg-emmc-ok.txt.gz` (`mmcblk0 … 57.6 GiB`, p1…p54) |
| Логи без UART | своя зона `ramoops@70000000` (не `nomap`), читается из рекавери через `/proc/last_kmsg` |
| Ubuntu rootfs на `p54` | ext4, 575 МБ, `/sbin/init → ../lib/systemd/systemd`, ssh, systemd-networkd |
| Было причиной «петли» | в ubuntu-base tarball **нет systemd** → `switch_root` падал (`Attempted to kill init`) |

## Что не работает (следующие шаги)

1. **USB-UDC**: `mtu3 11201000.usb` пробуется (`dr_mode: 2`, IP U3), но
   `/sys/class/udc/*` не появляется → нет RNDIS/SSH. Смотреть `tphy`
   (`u2port0`) и `usb-role-switch` по `refs/affenull-mt6771/`.
2. **DRM/KMS**: `&dsi0`/`&dpi0` выключены; панель **BOE TV110XUM** за мостом
   **ITE IT6112**, драйвер — `refs/it6112/panel-it6112-boe-tv110xum-lb2.c`.
3. **GPU**: panfrost для Mali-G72 MP3; `&gpu`/`&mfg` пока `disabled`
   (нужны `mali-supply` + `sram-supply` и рабочие PD).
4. **KDE**: `plasma-desktop` можно доставить в rootfs на хосте
   (`qemu-aarch64` + chroot, `Acquire::ForceIPv4=true`), как ставили systemd.

## Артефакты

- Ядро: `/home/l/projects/linux-t1100` (6.12.114), патчи `patches/0001…0019`
  (применяются `git am` на baseline `728cd6e`).
- Образы: `build/boot_ubuntu3.img` (Ubuntu, `root=/dev/mmcblk0p54`,
  initramfs со `switch_root`), `build/boot_pmic3/4.img` (bring-up),
  `build/boot_full_net*.img`.
- Rootfs: `build/rootfs/rootfs-t1100.tar.gz` (Ubuntu 24.04 + systemd + ssh),
  на планшете — `p54` (ext4, метка `ubuntu`).
- Инструменты: `scripts/{repack_boot,bootimg_extract,make_test_boot,make_initramfs,
  patch_image_header}.py|sh`, `tools/payload`, `tools/shim`,
  `tools/initramfs/{net-init.sh,root-init.sh,build-net.sh}`,
  `refs/pennyos-lk`, `refs/affenull-mt6771`, `refs/mt6771-next`, `refs/it6112`.

## Как продолжить

1. Планшет в **recovery** (`telnet 10.42.66.66`, меню `3` → `y`), RNDIS
   `10.42.66.67`, root-шелл без пароля.
2. Прошить нужный образ: `nc -l -p NNNN < img` на хосте,
   `nc 10.42.66.67 NNNN | dd of=/dev/mmcblk0p29 bs=1M conv=fsync` на устройстве.
3. Загрузиться, затем снова в recovery и прочитать лог:
   `cat /proc/last_kmsg | nc 10.42.66.67 NNNN`.
4. Вернуть Aurora: прошить `../t1100/backup_5.1.6.110/boot_a_imaoff_nodiehard_nosig.img`
   (md5 `73417c46…`). Rootfs Aurora (LVM `sailfish`) **уже снесён** — данные
   `/home` потеряны, владелец это разрешил.

## Грабли (не наступать снова)

- `reserved-memory` в нашем DTB должен существовать, но **без статических
  детей**; иначе LK висит. Своя зона ramoops — единственное исключение и только
  по адресу, не пересекающемуся с `mblock-*` (проверять валидатором).
- `regulator-coupled-with` mainline не поддерживает (generic coupler требует
  `always-on`) — не добавлять.
- Без `always-on` на VDRAM2/VBIF28 `regulator_late_cleanup()` выключает питание
  DRAM → system hangs до первого printk.
- В ubuntu-base нет systemd — проверять `/usr/lib/systemd/systemd` после распаковки.
- Пустой ramdisk LK не грузит: нужен хотя бы минимальный initramfs.
