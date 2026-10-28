# t1100-ubuntu — Ubuntu с DRM/KMS и GPU на Fplus T1100 (MT6771)

Проект порта **mainline-ядра** (или близкого к нему) на планшет **Fplus T1100**
(SoC **MT6771 / MT8788**, GPU **Mali-G72 MP3 Bifrost**) с целью запустить
**Ubuntu + Wayland/GNOME с аппаратным GPU-ускорением**.

> **Статус: scaffold.** Здесь только описание, план, агенты, скилы и инструменты.
> Kernel/DRM-порт ещё не начат — ничего не прошивалось и не реализовано.

## Зачем

Сейчас планшет работает на Aurora OS 5.1.6.110 поверх **downstream MTK/hybris
ядра 4.14** с `mtkfb` (framebuffer, **без DRM/KMS**) и проприетарным
`mali_kbase`. Полноценный KMS (Wayland/GNOME) требует:

- **DRM/KMS-драйвер дисплея для MT6771** — в mainline его нет, нужно портировать
  downstream `dispsys` (OVL/RDMA/DSI/MMSYS/CMDQ) в `mediatek-drm`;
- **mainline-совместимый DTS** и подсистемы (clock/pinctrl/regulator/CMDQ/IOMMU);
- **DRM panel-драйвер** для DSI-панели T1100;
- **GPU: panfrost** (open-source, поддерживает Mali-G72 Bifrost).

Исходники downstream-ядра MT6771 и mainline-фреймворк `mediatek-drm` **публичны**
(см. `docs/research.md`), поэтому порт инженерно реализуем — но это недели–месяцы
работы сильного kernel-разработчика.

## Не-цели v1

- модем/LTE, камера, звук — только если заведутся «сами» через mainline;
- Android-приложения / hybris — не нужны;
- Ubuntu Touch / UBports — отдельный проект.

## Что оставляем / что заменяем

| Оставляем | Заменяем |
|---|---|
| SoC-прошивки MTK: `preloader`, `lk`, `tee`, `md1img`, `nvram`, `nvdata`, `protect*` | Aurora userspace (lipstick/systemd) |
| DTB / описание панели | initramfs Авроры |
| `/vendor/firmware` (Wi-Fi/BT), если нужны | rootfs (`sailfish-root`/`sailfish-home` LVM) |
| — | Android-HAL в `super` (fimage/vendor) |

«Оставить только ядро от Авроры» на практике = оставить ядро **и** DTB **и**
загрузочную цепочку MTK (иначе SoC не стартует).

## Структура

```
t1100-ubuntu/
├── README.md                  # этот файл
├── AGENTS.md                  # правила для агентов проекта
├── opencode.json              # MCP (web-search, aurora-docs)
├── docs/
│   ├── hardware.md            # железо планшета (из разведки)
│   ├── research.md            # публичные источники и оценка
│   └── porting-plan.md        # пошаговый план порта
└── .opencode/
    ├── agent/
    │   ├── kernel-drm.md      # senior Linux DRM/KMS
    │   ├── bringup.md         # platform bring-up (DTS/clock/power)
    │   ├── gpu-mesa.md        # panfrost / Mesa
    │   ├── distro-userspace.md# Ubuntu / GNOME / systemd
    │   └── reverse-engineer.md# опционально: дизассемблер
    └── skills/
        └── mt6771-port/
            └── SKILL.md       # рабочий флоу порта
```

## Инструменты и соседние проекты

- `../t1100` — текущий проект планшета: SSH/root, recovery, `boot_patch.py`,
  бэкапы `boot_a`/`vbmeta`/`seccfg`.
- `../t1100/.opencode/skills/t1100-ssh/SKILL.md` — доступ к планшету.
- `../t1100/.opencode/skills/aurora-mediatek-security-off/` — перепаковка boot
  (`scripts/boot_patch.py`), recovery/прошивка.

## С чего начать

Входная точка — агент **`lead`** (оркестратор): он читает `docs/` и ведёт
`docs/STATUS.md`. Дальше он делегирует `bringup` (фаза 1), затем
`kernel-drm`/`gpu-mesa`, затем `distro-userspace`.

## Быстрый старт (когда начнём)

1. Прочитать `docs/hardware.md`, `docs/research.md`, `docs/porting-plan.md`.
2. Выбрать базовое дерево (mainline + patches Helio-P22 / downstream 4.19+).
3. Собрать ядро, загрузить до serial/ramdisk (без дисплея).
4. Портировать `mediatek-drm` под MT6771, поднять `kmscube`.
5. Включить panfrost, проверить GLES.
6. Собрать Ubuntu rootfs + Wayland/GNOME.
7. Прошивать только с бэкапом и через recovery (см. `t1100-ssh`).
