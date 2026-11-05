# t1100-ubuntu — Ubuntu с DRM/KMS и GPU на Fplus T1100 (MT6771)

Проект порта **mainline-ядра** (или близкого к нему) на планшет **Fplus T1100**
(SoC **MT6771 / MT8788**, GPU **Mali-G72 MP3 Bifrost**) с целью запустить
**Ubuntu + Wayland/GNOME с аппаратным GPU-ускорением**.

> **Статус (05.11.2026): фаза 1 закрыта, KMS-стек поднят; блокер — нет картинки
> на панели.**
> mainline 6.12.114 + патчи 0001–0034: ядро доходит до `systemd running`,
> eMMC HS400 (57.6 ГБ, 56 разделов), RAM 3.5 ГБ, USB-RNDIS (`1d6b:0104`) и
> `ssh root@10.42.66.66` по ключу, **батарея заряжается** (`mt6370-charger`:
> `online=1`, `Charging`, `vbus 4940 мВ`), **`poweroff` плату гасит** (0034).
> Дисплей: `mediatek-drm` собран, CRTC активен в вендорском режиме
> `1600x2176@60`, DSI стартует (`DSI_START=1`), мост IT6112 настроен побайтно
> как в стоковом LK — но **экран чёрный**; публичного референса для этой панели
> нет (в порту той же платы узел панели `disabled`). Дальше: RE инициализации
> панели в LK → GPU panfrost → KDE. Состояние и план — `docs/STATUS.md`,
> `docs/handover.md`.
>
> ~~**Статус (02.11.2026): Ubuntu 24.04 с systemd установлена на eMMC; загрузка
> подтверждена косвенно (петли сбросов нет), лог подтверждения — следующий шаг.
> Не хватает: USB-UDC (сеть), KMS-панели, GPU, KDE.**~~
>
> ~~**Статус: boot-chain пройден** — mainline 6.12 запускается на планшете
> (LK принимает наш DTB; см. `docs/lk-dtb-rules.md`, `docs/STATUS.md`).
> Дальше: логи через pstore, полноценное ядро, затем KMS.
>
> ~~**Статус: фаза 0 закрыта, идёт bring-up.**~~ База — mainline LTS 6.12.114,
> MT6771 добавляется как новый SoC; шаблон — mainline MT8183 (совпадение
> DISPSYS/GPU/PMIC доказано по стоковому DTB и WIP-порту `adomerle/mt6771-next`,
> см. `docs/research.md`). DTS собирается (PSCI + watchdog), `Image` собран,
> **на плату ещё не прошивался**. Панель — BOE TV110XUM-LB2 за мостом IT6112,
> исходник драйвера есть (`refs/it6112/`). Текущее состояние — `docs/STATUS.md`,
> воспроизводимость сборки — `docs/provenance.md`.

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
├── opencode.json              # MCP (aurora-docs)
├── docs/
│   ├── STATUS.md              # состояние, решения, следующий шаг
│   ├── hardware.md            # железо планшета (из разведки)
│   ├── research.md            # публичные источники и оценка
│   ├── porting-plan.md        # пошаговый план порта
│   ├── drm-port-plan.md       # инвентарь дисплейных блоков
│   ├── boot-test.md           # протокол первой загрузки (pstore)
│   ├── device-probe.md        # что снято с платы
│   ├── bringup-log.md         # журнал bring-up
│   └── provenance.md          # версии/хеши сборки
├── patches/                   # изменения ядра (series + *.patch)
├── configs/t1100.fragment     # Kconfig-фрагмент (pstore, watchdog…)
├── scripts/                   # сборка, перепаковка boot, initramfs, root
├── refs/                      # референсы: stock DTS, дампы, IT6112, mt6771-next
└── .opencode/
    ├── agent/
    │   ├── lead.md            # оркестратор
    │   ├── kernel-drm.md      # senior Linux DRM/KMS
    │   ├── bringup.md         # platform bring-up (DTS/clock/power)
    │   ├── gpu-mesa.md        # panfrost / Mesa
    │   ├── distro-userspace.md# Ubuntu / GNOME / systemd
    │   └── reverse-engineer.md# опционально: дизассемблер
    └── skills/
        └── mt6771-port/
            └── SKILL.md       # рабочий флоу порта
```

Ядро живёт отдельно: `../linux-t1100` (6.12.114 + `git am patches/series`),
сборка — out-of-tree в `build/t1100` (в `.gitignore`).

## Инструменты и соседние проекты

- `../t1100` — текущий проект планшета: SSH/root, recovery, `boot_patch.py`,
  бэкапы `boot_a`/`vbmeta`/`seccfg`.
- `../t1100/.opencode/skills/t1100-ssh/SKILL.md` — доступ к планшету.
- `../t1100/.opencode/skills/aurora-mediatek-security-off/` — перепаковка boot
  (`scripts/boot_patch.py`), recovery/прошивка.
- `../linux-t1100` — дерево ядра (создаётся из tarball 6.12.114 + патчи).
- `../toolchains/arm-gnu-toolchain-14.2…` — кросс-компилятор aarch64
  (альтернатива — системный `gcc-aarch64-linux-gnu`).

## Сборка с нуля

```sh
# 1) дерево ядра
curl -LO https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.114.tar.xz
tar -xf linux-6.12.114.tar.xz && mv linux-6.12.114 ../linux-t1100
cd ../linux-t1100 && git init && git add -A && git commit -m base
git am ../t1100-ubuntu/patches/$(sed -n '/\.patch$/p' ../t1100-ubuntu/patches/series)
# 2) сборка (тулчейн и фрагмент подхватываются автоматически)
cd ../t1100-ubuntu && scripts/build_kernel.sh
# 3) регресс DTB
sha256sum build/t1100/arch/arm64/boot/dts/mediatek/mt6771-fplus-t1100.dtb
```

## Где проект сейчас (31.10.2026)

| Блок | Состояние |
|---|---|
| LK / образ boot.img | ✅ LK принимает наш DTB (4 правила, `docs/lk-dtb-rules.md`), перепаковка `scripts/repack_boot.py` |
| Ядро | ✅ mainline **6.12.114** грузится до userspace; патчи `patches/0001…0019` |
| Память/PSCI/GIC | ✅ |
| PMIC MT6358 / power domains | ✅ рельсы и домены поднимаются |
| eMMC | ✅ HS400, `mmcblk0` 57.6 ГиБ, разделы видны |
| Логи без UART/экрана | ✅ своя зона `ramoops@70000000` + чтение из рекавери (`/proc/last_kmsg`) |
| USB (mtu3/UDC) | ❌ контроллер пробуется, `/sys/class/udc` нет → нет сети/SSH |
| Ubuntu rootfs | ✅ Ubuntu 24.04 arm64 с systemd на `p54`, грузится |
| DRM/KMS + панель BOE TV110XUM (IT6112) | ⏳ не начато (DSI0/DPI0 выключены) |
| GPU panfrost (Mali-G72) | ⏳ не начато |
| KDE Plasma | ⏳ после KMS |

## С чего начать

Входная точка — агент **`lead`** (оркестратор): он читает `docs/` и ведёт
`docs/STATUS.md`. Дальше он делегирует `bringup` (фаза 1), затем
`kernel-drm`/`gpu-mesa`, затем `distro-userspace`.

## Быстрый старт (когда начнём)

1. Прочитать `docs/hardware.md`, `docs/research.md`, `docs/porting-plan.md`.
2. ~~Выбрать базовое дерево~~ — выбрано: mainline 6.12.y + поддержка MT6771
   по шаблону MT8183 (`docs/STATUS.md`).
3. Собрать ядро, загрузить до serial/ramdisk (без дисплея).
4. Портировать `mediatek-drm` под MT6771, поднять `kmscube`.
5. Включить panfrost, проверить GLES.
6. Собрать Ubuntu rootfs + Wayland/GNOME.
7. Прошивать только с бэкапом и через recovery (см. `t1100-ssh`).
