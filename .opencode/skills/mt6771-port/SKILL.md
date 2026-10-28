---
name: mt6771-port
description: Workflow порта mainline/near-mainline ядра с DRM/KMS и panfrost на Fplus T1100 (MT6771/MT8788): сборка тестового ядра, перепаковка boot (kernel+DTB+initramfs), прошивка через recovery/dd, проверка kmscube/glmark2, откат. Триггеры: mt6771 port, t1100 ubuntu, kms, drm, panfrost, build kernel, repack boot, flash kernel, kmscube, glmark2, gnome, ubuntu rootfs.
---

# MT6771 / Fplus T1100 — порт ядра и Ubuntu

Рабочий флоу для проекта `t1100-ubuntu`. Проверенные факты о планшете —
`docs/hardware.md`; источники — `docs/research.md`; фазы — `docs/porting-plan.md`.

## Инструменты и соседний проект

- `../t1100` — доступ к планшету (SSH/root), recovery, бэкапы
  `boot_a`/`vbmeta`/`seccfg`, `backup_5.1.6.110/`.
- `../t1100/.opencode/skills/t1100-ssh/SKILL.md` — SSH/root, recovery.
- `scripts/boot_patch.py` (локальная копия) = `../t1100/.opencode/skills/aurora-mediatek-security-off/scripts/boot_patch.py`
  — разбор/перепаковка Android boot v2 (kernel + ramdisk + DTB).
- Кросс-сборка: aarch64 `gcc`/`clang`, `dtc`, `mkbootimg` (или `boot_patch.py`).

## Сборка тестового ядра

```sh
# пример; точное дерево — по docs/porting-plan.md (фаза 0)
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- <defconfig>
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image dtbs
```

Загрузить сначала **без дисплея**: uart/консоль, USB-gadget, RAM. Только потом
DRM/GPU.

## Перепаковка boot

Boot — Android boot v2: gzip-ядро + ramdisk + DTB (111095 байт). Использовать
`boot_patch.py` (он умеет менять cmdline/ядро/ramdisk, сохраняя DTB) либо
`mkbootimg` с теми же параметрами (page 2048, `dtb_size`).

Cmdline для Ubuntu: `root=/dev/mmcblk0p54 rootwait` (вместо `root=/dev/ram`),
`ima_appraise=off`, `security=` убрать/оставить инертным, `module.sig_enforce=0`
(для вендорных модулей). **Не** менять `clearmem`/`security=diehard` без причины.

## Прошивка

Только с бэкапом. Варианты:
- **recovery** T1100: RNDIS `10.42.66.66`, telnet-меню → «5) Run sshd»,
  `root`/`recovery`; стрим `dd` в `/dev/mmcblk0p29`.
- Из работающей ОС (root): `dd if=boot.img of=/dev/mmcblk0p29 bs=1M conv=fsync`.
- BROM `0e8d:0003` + mtkclient (опционально, нужны кнопки).

**Перед записью** сверить `/proc/partitions`: T1100 — p29=32768, p54≈52 ГБ. Не
перепутать с NS220 (16 ГБ, p1…p22) — оба recovery на `10.42.66.66`.

## Проверка

```sh
# KMS
modetest -M mediatek
kmscube
# GPU
glmark2 / es2gears
# сеть/ввод
ip a; evtest
```

## Откат

Вернуть стоковый `boot_a` из `../t1100/backup_5.1.6.110/boot_a_5.1.6.110.img`
(или `boot_a_imaoff_nodiehard.img`) через recovery/`dd`, сверить sha, перезагрузить.

## Правила

- Каждая прошивка — с бэкапом и планом отката.
- Не трогать MTK-прошивки (`preloader`, `lk`, `tee`, `md1img`, …).
- Регистры/такты — только из исходников.
- Сообщать фактический вывод (`modetest`, `dmesg`), не предположения.
