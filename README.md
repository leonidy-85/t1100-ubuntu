# t1100-ubuntu — Ubuntu с DRM/KMS и GPU на Fplus T1100 (MT6771)

Проект порта **mainline-ядра** (или близкого к нему) на планшет **Fplus T1100**
(SoC **MT6771 / MT8788**, GPU **Mali-G72 MP3 Bifrost**) с целью запустить
**Ubuntu + Wayland/GNOME с аппаратным GPU-ускорением**.

> **Статус (14.11.2026): фазы 1–3 закрыты; Ubuntu 26.04 + KDE Plasma 6.6.4.**
> mainline 6.12.114 + патчи 0001–0067 (0035 отключён, 0020 заменён на 0060): ядро доходит до `systemd running`,
> eMMC HS400 (57.6 ГБ, 56 разделов), RAM 3.5 ГБ, все **8 ядер** (`maxcpus=8`),
> USB-RNDIS (`1d6b:0104`) и `ssh root@10.42.66.66` по ключу, **батарея
> заряжается** (`mt6370-charger`; драйвера счётчика заряда — battery gauge —
> в mainline нет, процентов заряда не будет), **`poweroff` снимает питание** через RTC MT6358 (0034; при
> подключённом кабеле плата стартует снова — штатный «boot on charger»).
> Дисплей: `card0-DSI-1` `connected/enabled`, режим `1600x2176@58.93`; сдвиг
> кадра убран окончательно (0046 + 0052: `vbp 284`, `vfp 8`).
> GPU: panfrost (0039) — **Mesa 26.0.3**; **DVFS включён** (0058/0059:
> coupler MT6771/MT8788, OPP 698/743/800 МГц, VGPU/VSRAM spread 100 мВ);
> `glmark2` Score 1409/1583, но в отдельных shader-сценах есть таймауты
> panfrost — отдельный баг, не DVFS. KDE Plasma 6.6.4 + SDDM (autologin root).
> Тач HX83102E работает (`boot_touch8`, native portrait; KWin сам поворачивает —
> 0051). **Микрофон работает:** маршрут `UL1_CH1/CH2 ADDA_UL` и `PGA L/R = AIN0`
> применяет `t1100-audio-mixer.service`, PipeWire source `alsa_mic` — по
> умолчанию; `arecord`/`parecord` дают ненулевой сигнал. Wi-Fi/BT в mainline
> не поддержаны, сеть — только RNDIS.
> **USB host/OTG (0060/0061/0067):** Type-C переведён в dual-role, host-режим
> работает — флешка `Phison 13fe:5500` определяется как `sda` (7.4 GB), MT6370
> выдаёт VBUS 5.05 В / 2.4 А. Возврат host→device — helper `t1100-usb-role`:
> он останавливает xHCI, меняет роль и снова поднимает xHCI, без перезагрузки.
> **CPU DVFS (0062/0063):** `mtk-cpufreq`, 16 OPP 793…1989 МГц с voltage
> tracking, `schedutil`; максимум 1.989 ГГц при 1.05 В проверен на железе.
> **Thermal (0064):** CPU-зона 80/90/115 °C, throttling проверен; efuse-
> калибровка MT6771 пока не декодируется, драйвер использует дефолты MT8183.
> SVS пока выключен.
> **Suspend:** `systemctl suspend` работает через s2idle (`SuspendState=freeze`);
> USB-гаджет на время сна отключается хуком и восстанавливается после пробуждения.
> Глубокий `mem` (PSCI deep) не восстанавливается — после него нужен power-cycle;
> поэтому используется s2idle.
> Дальше: SVS/soak-тест, panfrost shader timeout, Wi-Fi/BT (фаза 5), безопасный
> возврат USB-роли, задержка выделения. Состояние и план — `docs/STATUS.md`,
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
| `/vendor/firmware` (Wi-Fi/BT), если портировать стек | Aurora rootfs: LVM `sailfish` снесён, `p54` = ext4 под Ubuntu |
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
│   ├── cross-build.md         # кросс-сборка: build-хост, sysroot, статические утилиты
│   ├── bringup-log.md         # журнал bring-up
│   └── provenance.md          # версии/хеши сборки
├── patches/                   # изменения ядра (series + *.patch)
├── configs/t1100.fragment     # Kconfig-фрагмент (pstore, watchdog…)
├── scripts/                   # сборка (в т.ч. на build-хосте), перепаковка boot, initramfs
├── rootfs-overlay/            # файлы для rootfs (юнит-страховка от разряда…)
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

Ядро живёт отдельно: локальное дерево `../linux-t1100` (если есть) или
`/home/l/t1100-ubuntu-build/src` на build-хосте (rsync из
`scripts/build-kernel-remote.sh`, 6.12.114 + `git am patches/series`); сборка —
out-of-tree, артефакты забираются в `build/remote/` (в `.gitignore`).

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
# 2) сборка — НА BUILD-ХОСТЕ (12 ядер): локальная машина делит CPU с другими
#    проектами, полная сборка там занимала часы
cd ../t1100-ubuntu && scripts/build-kernel-remote.sh
#    (локальный вариант остаётся: scripts/build_kernel.sh -> build/t1100)
# 3) регресс DTB
sha256sum build/t1100/arch/arm64/boot/dts/mediatek/mt6771-fplus-t1100.dtb
```

## Где проект сейчас (13.11.2026)

| Блок | Состояние |
|---|---|
| LK / образ boot.img | ✅ LK принимает наш DTB (4 правила, `docs/lk-dtb-rules.md`), перепаковка `scripts/repack_boot.py` |
| Ядро | ✅ mainline **6.12.114** грузится до userspace; патчи `patches/0001…0067` (0035 отключён, 0020 заменён на 0060) |
| Память/PSCI/GIC | ✅ |
| PMIC MT6358 / питание | ✅ регуляторы (rails) MT6358 и power-домены SCPSYS регистрируются (0012); зарядка MT6370 `online=1/Charging`, но без счётчика заряда (battery gauge) — процентов в `/sys/class/power_supply` нет (0031; TCPC dual-role, 0066/0067); `poweroff` снимает питание через RTC MT6358 (0034; при подключённом кабеле плата стартует снова — «boot on charger») |
| eMMC | ✅ HS400, `mmcblk0` 57.6 ГиБ, разделы видны |
| Логи без UART/экрана | ✅ своя зона `ramoops@70000000` + чтение из рекавери (`/proc/last_kmsg`) |
| USB (mtu3/UDC + host) | ✅ RNDIS `1d6b:0104`, `usb0 = 10.42.66.66`, SSH; host — флешка `sda` 7.4 GB, VBUS 5.05 В (0060/0061/0067), helper `t1100-usb-role`; возврат host→device без reboot |
| Ubuntu rootfs | ✅ Ubuntu 26.04 LTS arm64 + KDE Plasma 6.6.4 на `p54` (ext4, метка `ubuntu`), 8 ядер |
| DRM/KMS + панель BOE TV110XUM (IT6112) | ✅ панель 1600×2176@58.93 (0038/0046/0052), сдвиг кадра убран |
| GPU panfrost (Mali-G72) | ✅ Mesa 26.0.3, GLES 3.1; DVFS 698/743/800 МГц (0058/0059), `glmark2` Score 1409/1583 |
| CPU DVFS | ✅ `mtk-cpufreq` (0062/0063), 793…1989 МГц, 650/700…1050 мВ, `schedutil`; thermal CPU-зона 80/90/115 °C (0064), throttling проверен; SVS пока выключен |
| Wayland / KDE | ✅ KDE Plasma 6.6.4 + SDDM autologin root; тач (0051) и клавиатура работают |
| Звук | ✅ динамик и микрофон; маршрут `UL1_CH1/CH2 ADDA_UL`, PipeWire source `alsa_mic` |
| Wi-Fi / BT | ❌ в mainline не поддержаны (CONNSYS_6771/MT6631); сеть только RNDIS |

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
