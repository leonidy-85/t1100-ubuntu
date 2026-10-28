# STATUS — t1100-ubuntu

Обновлено: 28.10.2026.

## Фаза

**Фаза 0 — закрыта (решение о базе). Фаза 1 (bring-up) — в работе.**

Ядро ещё не собиралось под MT6771 и не прошивалось. Репозиторий порта пока не
содержит кода ядра — только инфраструктуру, референсы и решения.

## Решения (decision log)

| Дата | Решение | Обоснование |
|---|---|---|
| 2026-10-28 | **База — mainline LTS 6.12.y, MT6771 добавляем как новый SoC in-tree**; downstream 4.14/4.4 MTK — только референс регистров/панели | В downstream нет DRM/KMS (только `mtkfb`), публичного downstream 4.19/5.x с `mtk_drm` и MT6771 нет; цели проекта (KMS+panfrost) требуют mainline |
| 2026-10-28 | **Шаблон порта — mainline MT8183**, второй референс — MT8365 | Доказано по стоковому DTB: OVL/RDMA/COLOR/CCORR/AAL/GAMMA/DITHER/DSI/MUTEX/LARB/SMI, `mmsys` 0x14000000, GPU 0x13040000+IRQ278/279/280, PMIC MT6358, topckgen/infracfg/pericfg — **совпадают с mt8183.dtsi** (см. `docs/research.md`) |
| 2026-10-28 | Ссылка на `gitlab.com/Helio-P22/linux-mainline` (была в `docs/research.md`) **снята как недостоверная** | Проекта с таким именем в публичном GitLab нет (API 28.10.2026); в mainline нет ни MT6765, ни MT6771 |
| 2026-10-28 | Кросс-тулчейн: `gcc-aarch64-linux-gnu` 15.2 (Ubuntu), `dtc` 1.7.2, `mkimage` 2025.10 — установлены на хосте | Минимальный набор для сборки `Image`/`dtbs` и перепаковки boot |
| 2026-10-28 | **Канала UART нет** (подключения к плате нет). Логи загрузки mainline — **`ramoops`/pstore из RAM** + сбор данных по SSH с самой платы; root — `scripts/t1100_root.sh` (`devel-su`, код блокировки) | Проверено: `/sys/fs/pstore/console-ramoops` содержит лог **прошлой** загрузки (паника `switch_root`) — pstore переживает reboot. `devel-su -c`/`su -c` не работают, нужен интерактивный root-shell (`docs/device-probe.md`) |
| 2026-10-28 | Практика: «сначала снять факты с платы, потом писать DTS» — board-узлы (LCM GPIO, backlight, тач) брать из живого FDT (`refs/device/fdt-live.dts.gz`), а не из boot-DTB | dtbo-оверлеи добавляют `odm/lcm`, `lcd-backlight`, `himax_touch@48` и др., которых в boot-DTB нет |
| 2026-10-28 | **Прошивка `boot_a` — только пошагово, с показом образа/сумм/плана отката и подтверждением владельца** | Правило проекта: бэкап + откат; прошивка через recovery (p29) |
| 2026-10-28 | **Код ядра — отдельное дерево `../linux-t1100`; наши изменения — патчами в `t1100-ubuntu/patches/`** | Патчи ревьюятся, переносимы в upstream, не завязаны на форк |

## Сделано

- [x] Проект создан: `README.md`, `AGENTS.md`, `opencode.json`, `docs/`.
- [x] `docs/hardware.md`, `docs/research.md`, `docs/porting-plan.md`.
- [x] Агенты: `lead`, `bringup`, `kernel-drm`, `gpu-mesa`, `distro-userspace`,
      `reverse-engineer`.
- [x] Скил `mt6771-port`.
- [x] **Снят стоковый DTB** из `boot_a_5.1.6.110.img` → `refs/stock-mt6771.dts`
      (111095 B, внутри 64-байтный MTK-заголовок; утилита
      `scripts/bootimg_extract.py`, читает `ANDROID!` v2).
- [x] **Карта дисплея и GPU MT6771** выписана из стокового DTB (`docs/hardware.md`).
- [x] **Панель идентифицирована**: BOE **TV110XUM-LB0-1SP0**, 1600×2176,
      4-lane DSI video, PLL 790, in-cell touch; LCM-драйвер в стоке —
      `tv110xum_lb2_incell` (вкомпилирован).
- [x] **Найдено соответствие MT6771 ↔ MT8183** (главный вывод: 90% подсистем
      дисплея/GPU/PMIC уже есть в mainline).
- [x] Тулчейн aarch64 + `dtc` + `mkimage` установлен.
- [x] Доступ к планшету проверен: SSH `defaultuser@172.17.141.62` живой,
      Aurora 4.14.186, `dmesg` читается без root; **root получен** через
      `devel-su` (`scripts/t1100_root.sh`).
- [x] **Данные с платы сняты** (`docs/device-probe.md`, `refs/device/`): живой
      FDT с dtbo (board-GPIO LCM/backlight/тач), полный `dmesg`, конфиг,
      `console-ramoops` прошлой загрузки, `/proc/iomem`, IRQ, OPP, разметка.
- [x] Подтверждён **канал логов без UART**: `ramoops`/pstore в RAM
      (`0x54410000`, 0xe0000), переживает перезагрузку.

## Следующий шаг

1. **`bringup`**: получить дерево `linux` 6.12.y в `../linux-t1100`, собрать
   `defconfig` baseline (`Image dtbs`) — проверка тулчейна.
2. **`bringup`**: `mt6771.dtsi` + `mt6771-fplus-t1100.dts` по шаблону
   `mt8183.dtsi`; первый шаг — CPU/GIC/timer/uart0/`memory` (boot to console).
3. **`bringup`**: `clk-mt6771` (top/infra/peri/apmixed/mfg/mm) — сверить
   gate-биты с downstream `clk-mt6771.c` (Hadenix 4.4 / Realme 4.14).
4. **`lead`**: решить канал отладки загрузки (UART? ramoops? сеть?) — см. блокеры.
5. Только после «зелёного» baseline — перепаковка `boot_a` и первая прошивка
   (с бэкапом и планом отката).

## Блокеры

1. **Логи только через pstore** (UART нет). Ранняя паника (до `ramoops`-инита)
   останется невидимой. Митигация: минимальный DTB/initramfs, `ramoops` в DTS,
   `nokaslr`, отключить лишние подсистемы; при необходимости — USB-gadget
   (`g_serial`/RNDIS) в initramfs как второй канал.
2. **Нет `clk-mt6771`/`pinctrl-mt6771`** — их нужно писать; объём работы
   сопоставим с половиной всего порта.
3. **Init панели** есть только в бинарнике LCM (исходник `tv110xum_lb2_incell`
   публично не найден) — потенциально RE.

## Риски

- Дисплей: нет TRM, только исходники; объём работы по `mediatek-drm` (сейчас
  снижен благодаря MT8183-совпадению).
- Панель/тач: init и тайминги; тач Himax — отдельный драйвер.
- Wi-Fi: MT6631 в mainline не поддержан; вероятно только вендорный
  `wlan_drv_gen3` + `/vendor/firmware`.
- Прошивка: только через recovery/`dd` с бэкапом `boot_a`/`vbmeta`/`seccfg`;
  recovery T1100 и NS220 на одном адресе `10.42.66.66` — сверять
  `/proc/partitions`.
- Отладочные MTK-узлы опасны: запись в `/proc/dispsys`/`/proc/clkdbg` валит
  стоковое ядро (проверено 28.10.2026, плата ушла в перезагрузку; лог в
  `refs/device/console-ramoops-2026-10-28-2237-crash.txt.gz`). Регистры берём
  только из DTB и downstream-исходников.

## Референсы

- `refs/stock-mt6771.dts` — DTS из boot-DTB (карта регистров).
- `refs/device/fdt-live.dts.gz` — **живой FDT** с dtbo: board-узлы (LCM GPIO/backlight/тач), см. `docs/device-probe.md`.
- `refs/es6311_anx6585_zigzag_wxga.c` — чужой LCM-драйвер, образец структуры
  MTK LCM/DSI (не наша панель).
- `scripts/bootimg_extract.py` — разбор Android boot v2 (kernel/ramdisk/DTB).
