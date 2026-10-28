# AGENTS.md — проект t1100-ubuntu (порт Ubuntu с KMS на MT6771)

Правила для агентов opencode. Читать в начале сессии.

## Что это

Проект порта Linux (mainline или near-mainline) на планшет **Fplus T1100**
(SoC **MT6771 / MT8788 = Helio P60/P70**, GPU **Mali-G72 MP3 Bifrost**) с целью
**Ubuntu + Wayland/GNOME + DRM/KMS + panfrost**. Сейчас — только scaffold.

## Обязательный контекст

1. `docs/hardware.md` — железо, разделы, текущее состояние.
2. `docs/research.md` — публичные исходники/ссылки и что не публично.
3. `docs/porting-plan.md` — фазы и точки рисков.
4. Соседний проект `../t1100` — доступ к планшету, recovery, перепаковка boot.

## Правила работы

1. **Не прошивать без бэкапа**: `boot_a`, `vbmeta_a`, `seccfg` (см. `../t1100`).
   Бэкапы и инструмент — в `../t1100/backup_5.1.6.110/`.
2. **Прошивка только через recovery или `dd` с проверкой sha**, как в
   `../t1100/.opencode/skills/aurora-mediatek-security-off`.
3. **Дисплей — отдельная сложная задача**: не считать «ядро загрузилось»
   готовностью десктопа. KMS проверяется `kmscube`/`modetest`, GPU — `glmark2`.
4. **Не выдумывать регистры**: брать их из публичных исходников MT6771
   (`Hadenix/android_kernel_alps-4.4`, `dispsys`) и mainline `mediatek-drm`.
5. **SoC-прошивки MTK не трогать** (`preloader`, `lk`, `tee`, `md1img`, `nvram`,
   `nvdata`, `protect*`) без явной необходимости — риск потерять устройство.
6. **Сообщать фактический результат** команд (прошло/не прошло, точный вывод),
   а не предположения.
7. TRM MT6771 **не публичен** — референс = исходники ядра; дизассемблирование —
   только как fallback (см. агента `reverse-engineer`).

## Роли (агенты)

| Агент | Роль |
|---|---|
| `kernel-drm` | DRM/KMS-драйвер дисплея MT6771 |
| `bringup` | DTS, clock/pinctrl/regulator, SMI/IOMMU, загрузка |
| `gpu-mesa` | panfrost, GPU-node, Mesa, GLES |
| `distro-userspace` | Ubuntu rootfs, systemd, Wayland/GNOME, Wi-Fi/ввод |
| `reverse-engineer` | опционально: дизассембл недостающих блобов |

## Не-цели v1

Модем, камера, звук, Android/hybris, Ubuntu Touch — вне скоупа, если не
заработают «сами».
