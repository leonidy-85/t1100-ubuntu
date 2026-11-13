# STATUS — t1100-ubuntu

Обновлено: 12.11.2026.

## Фаза

**Фазы 0–3 закрыты. Фаза 4 (десктоп) — в работе, фаза 5 (Wi-Fi/BT) — в работе.**

- **Фаза 0 (решения) — закрыта:** база mainline LTS **6.12.114**, код — в
  отдельном дереве `../linux-t1100`, изменения — патчами `patches/` +
  `series` (**0001–0052**, 0035 отключён).
- **Фаза 1 (bring-up) — закрыта:** ядро доходит до `systemd running`; eMMC
  HS400 (57.6 ГБ, 56 разделов), RAM 3.5 ГБ, **8 ядер** (`maxcpus=8`),
  USB-RNDIS (`1d6b:0104`) и `ssh root@10.42.66.66` по ключу, батарея
  заряжается (`mt6370-charger`), `poweroff` гасит плату (0034).
- **Фаза 2 (DRM/KMS) — закрыта:** `mediatek-drm` + DSI0 + панель BOE
  TV110XUM-LB2 за мостом IT6112; режим **1600×2176@58.93**; сдвиг кадра
  убран окончательно (0046 + 0052: `vbp 284`, `vfp 8`, `vtotal 2476`).
  KDE работает в ландшафте 2176×1600.
- **Фаза 3 (GPU) — закрыта:** panfrost (0039) без DVFS, Mesa 26.0.3,
  GLES 3.1; на момент приёмки `kmscube` 56.4 fps, `glmark2` Score 452.
- **Фаза 4 (десктоп) — в работе:** Ubuntu 26.04 LTS + KDE Plasma 6.6.4
  (SDDM autologin root) на `p54`; тач HX83102E работает (native portrait,
  0051 — оси и поворот отданы KWin). Остались задержка выделения в
  приложениях и DVFS GPU.
- **Фаза 5 (Wi-Fi/BT) — в работе:** вендорский стек портирован и собирается
  под 6.12 (`wmt_drv.ko`, `wlan_drv_gen3.ko`, M2 закрыт), DT для CONSYS и
  HIF MT6631 (0049), M3 подготовлен (build-only) — на железе не запускался.
  Сеть сейчас — только RNDIS.

Хронология и детали — ниже; свежие записи в конце файла («12.11»).

## Решения (decision log)

| Дата | Решение | Обоснование |
|---|---|---|
| 2026-10-28 | **База — mainline LTS 6.12.y, MT6771 добавляем как новый SoC in-tree**; downstream 4.14/4.4 MTK — только референс регистров/панели | В downstream нет DRM/KMS (только `mtkfb`), публичного downstream 4.19/5.x с `mtk_drm` и MT6771 нет; цели проекта (KMS+panfrost) требуют mainline |
| 2026-10-28 | **Шаблон порта — mainline MT8183**, второй референс — MT8365 | Доказано по стоковому DTB: OVL/RDMA/COLOR/CCORR/AAL/GAMMA/DITHER/DSI/MUTEX/LARB/SMI, `mmsys` 0x14000000, GPU 0x13040000+IRQ278/279/280, PMIC MT6358, topckgen/infracfg/pericfg — **совпадают с mt8183.dtsi** (см. `docs/research.md`) |
| 2026-10-28 | Ссылка на `gitlab.com/Helio-P22/linux-mainline` (была в `docs/research.md`) **снята как недостоверная** | Проекта с таким именем в публичном GitLab нет (API 28.10.2026); в mainline нет ни MT6765, ни MT6771 |
| 2026-10-28 | **Канала UART нет** (подключения к плате нет). Логи загрузки mainline — **`ramoops`/pstore из RAM** + сбор данных по SSH с самой платы; root — `scripts/t1100_root.sh` (`devel-su`, код блокировки) | Проверено: `/sys/fs/pstore/console-ramoops` содержит лог **прошлой** загрузки (паника `switch_root`) — pstore переживает reboot |
| 2026-10-28 | Практика: «сначала снять факты с платы, потом писать DTS» — board-узлы брать из живого FDT (`refs/device/fdt-live.dts.gz`) | dtbo-оверлеи добавляют `odm/lcm`, `lcd-backlight`, `himax_touch@48` и др., которых в boot-DTB нет |
| 2026-10-28 | **Прошивка `boot_a` — только пошагово, с показом образа/сумм/плана отката и подтверждением владельца** | Правило проекта: бэкап + откат; прошивка через recovery (p29) |
| 2026-10-28 | **Код ядра — отдельное дерево `../linux-t1100`; наши изменения — патчами в `patches/`** | Патчи ревьюятся, переносимы в upstream, не завязаны на форк |
| 2026-10-29 | **База закреплена: linux-6.12.114** (sha256 `7a858991…4af3`) | Актуальный LTS на 29.10.2026; сверено с `sha256sums.asc` |
| 2026-10-29 | Сборка — out-of-tree `O=<repo>/build/t1100`, лог в `build/logs/`; для DTS-итераций — только нужный `.dtb` | Точечная сборка DTB — секунды, полная — минуты |
| 2026-10-29 | **PSCI в стоке есть** (`arm,psci-1.0`, `method = "smc"`, 8 CPU online) | Стоковый DTS (`refs/stock-mt6771.dts`) + dmesg `PSCIv1.0 detected in firmware` |
| 2026-10-29 | **GIC — v3** (`GICD 0x0c000000`, `GICR 0x0c100000`), **uart0 IRQ = GIC_SPI 91** | dmesg + стоковый DT (`0x5b`=91) |
| 2026-10-29 | **Среда пересоздана на новом хосте**: tarball 6.12.114 + Arm GNU Toolchain 14.2 (распакован в `../toolchains/`, без root) | Скрипты теперь сами находят дерево/тулчейн/фрагмент; старые пути `/home/l/...` убраны |
| 2026-10-29 | **`dtb_addr` в MTK-заголовке — 32-битное поле по `0x674`** (не AOSP `u64` по `0x678`); хвост стокового образа при перепаковке **сохраняется** | `<IQ` давал 0; иначе round-trip «идентичен» только на полезных 14,9 МБ, а не на всех 32 МиБ |
| 2026-10-29 | **Патч 0003: PSCI + `mediatek,mt8183-wdt`; из bootargs убраны `console`/`earlycon`/`stdout-path`** | Без restart-handler `panic=10` печатал `System halted`; до `clk-mt6771` UART-гейт закрыт LK, первый printk не должен трогать gated-периферию |
| 2026-10-29 | **Панель = BOE TV110XUM-LB2 за мостом ITE IT6112**; init-последовательность и тайминги есть в публичном WIP-драйвере (`refs/it6112/`) | `linux-mediatek/linux` @ `935fe30`, автор Arseniy Velikanov; RE больше не основной путь |
| 2026-10-29 | **Гипотеза: MT8183-инфраструктуру можно переиспользовать для MT6771** (`clk`, `pinctrl`, mmsys) | В `adomerle/mt6771-next` `mt6771.dtsi` = `#include "mt8183.dtsi"` + `compatible`, отдельных драйверов MT6771 нет (`refs/mt6771-next/`) |

## Сделано

- [x] Проект создан: `README.md`, `AGENTS.md`, `opencode.json`, `docs/`.
- [x] `docs/hardware.md`, `docs/research.md`, `docs/porting-plan.md`,
      `docs/drm-port-plan.md`, `docs/boot-test.md`, `docs/device-probe.md`,
      `docs/bringup-log.md`.
- [x] Агенты: `lead`, `bringup`, `kernel-drm`, `gpu-mesa`, `distro-userspace`,
      `reverse-engineer`.
- [x] **Снят стоковый DTB** → `refs/stock-mt6771.dts` (111095 B, MTK-заголовок
      срезан); `scripts/bootimg_extract.py` читает `ANDROID!` v2.
- [x] **Карта дисплея и GPU MT6771** выписана из стокового DTB.
- [x] **Панель идентифицирована**: BOE **TV110XUM-LB0-1SP0**, 1600×2176,
      in-cell touch; в стоке LCM `tv110xum_lb2_incell`; `es6311` — устаревшая
      строка ATAG.
- [x] **Найдено соответствие MT6771 ↔ MT8183** (+ WIP-порт `adomerle/mt6771-next`).
- [x] Доступ к планшету проверен ранее; данные сняты (`docs/device-probe.md`,
      `refs/device/`); канал логов — `ramoops`/pstore.
- [x] `scripts/build_kernel.sh` — воспроизводимая сборка (out-of-tree, лог,
      sha, `--clean`/`--defconfig`), теперь с автопоиском тулчейна и
      авто-применением `configs/t1100.fragment`.
- [x] `scripts/repack_boot.py` — перепаковка boot v2 + MTK-контейнер DTB;
      round-trip стокового образа **побайтово идентичен на всех 32 МиБ**.
- [x] `scripts/make_initramfs.sh` + `scripts/make_test_boot.sh`; initramfs
      1 031 517 B, тестовый `boot_a_test.img` 32 МиБ собран.
- [x] **DTS MT6771**: `mt6771.dtsi` (300 строк) + `mt6771-fplus-t1100.dts`
      (75) + `Makefile`; DTB 4941 B, 0 warnings.
- [x] **Патч 0003**: PSCI, `mediatek,mt8183-wdt`, bootargs без
      console/earlycon/stdout-path; регресс на чистом дереве — sha совпадает.
- [x] `configs/t1100.fragment`: PSTORE/PSTORE_RAM/CONSOLE/PMSG,
      `DEBUG_INFO_NONE`, `VA_BITS_39`, `PANIC_TIMEOUT=10`, `ARM_PSCI_FW`,
      `MEDIATEK_WATCHDOG`.
- [x] `scripts/t1100_root.py` — pexpect-драйвер `devel-su` (expect больше не
      обязателен); `IdentitiesOnly`-вариант в `t1100_root.exp` **не проверен на
      плате** (нет ключа/пароля на этом хосте).
- [x] `docs/provenance.md` — версии/хеши/воспроизводимость.
- [x] `refs/it6112/` — WIP-драйвер панели; `refs/mt6771-next/` — полный board
      DTS планшета и `mt6771.dtsi` из linux-mediatek.
- [x] `Image` собран с фрагментом: 38 531 584 B, 0 warnings, 1192 DTB
      (84 mediatek), ~4,5 минуты на 20 CPU.

## Следующий шаг

1. **Первая тестовая загрузка** (UP, `maxcpus=1`, без UART-консоли):
   прошить `build/boot_a_test.img` в `p29` **с подтверждением владельца**,
   вернуть сток через recovery, прочитать
   `/sys/fs/pstore/console-ramoops` с платы.
2. **Проверить гипотезу «MT8183 достаточно»**: собрать вариант DTS с
   `#include "mt8183.dtsi"` (как в `adomerle/mt6771-next`), сравнить поведение
   (pwrap/PMIC, MMC, pinctrl) на железе. Если работает — `clk-mt6771` не нужен
   на первом этапе.
3. **`kernel-drm`**: бэкпорт `panel-it6112-*` на 6.12 (`devm_drm_panel_alloc` →
   `drm_panel_init`), подключить `i2c3` + MT6370-регуляторы; mmsys route +
   `OVL→…→DSI` DIRECT_LINK.
4. **`distro-userspace`**: initramfs с маркерами уже есть; далее Ubuntu-base
   rootfs + systemd на eMMC (после MMC-клоков).
5. Если понадобится UART: вернуть `earlycon`/`console` после `clk-mt6771`.

## Блокеры

1. **Нет SSH-доступа к плате с этого хоста** — `defaultuser` требует
   ключ/пароль (`Permission denied (publickey,password)`), а `devel-su`-код
   (`12345`) для SSH не подходит. Без этого нельзя прочитать pstore после
   тестовой загрузки. Нужен ключ/пароль владельца.
2. **Логи только через pstore** (UART нет). Ранняя паника (до `ramoops`-инита)
   невидима. Митигация: минимальный DTB/initramfs, `nokaslr` при необходимости.
3. **`clk-mt6771`/`pinctrl-mt6771` отсутствуют** — либо переиспользуем MT8183
   (гипотеза), либо пишем свои (недели, TRM нет).
4. **Питание панели**: `vpos`/`vneg` даёт MT6370 — без его регуляторов экран
   не включится.
5. **Бэкапа `boot_a`/`vbmeta`/`seccfg` на этом хосте нет**; recovery-инструкции
   в отсутствующем `../t1100`. Перед прошивкой — восстановить бэкап/план отката.

## Сессия 29.10.2026 (lead): разбор чужой сборки и диагностика загрузки

**Найдено на плате.** В `boot_a` был образ другого разработчика: ядро 6.12.114
(`leo@localhost`, Arm GNU Toolchain 14.2), **наш** initramfs (`--action sleep`,
600 с), наш board-DTB. Образ сохранён целиком
(`build/recovery/boot_a_current.img`, 32 МиБ, md5 `26508f08…`), вместе с GPT
(`p03 expdb`, `p29 boot_a`, `p45 boot_b`, `p50 recovery`, `p51 cache`, …).
Их тесты: ни одного printk ни в одном варианте; «сбросы» — это **watchdog LK**;
probe-payload доказал, что `lk` грузит и передаёт управление нашему образу
(`refs/probe-payload`). Значит ядро умирает до первой консоли.

**Исправлено (наш DTS).** Регион `framebuffer@7cd80000` в `reserved-memory` был
помечен `no-map` — такой регион нельзя `ioremap`, поэтому `simpledrm`/fbcon не
поднимался вовсе. `no-map` снят (регион остаётся зарезервированным).

**Подготовлено к решающему тесту (собрано, на плату не прошивалось):**

| Артефакт | sha256 | Что |
|---|---|---|
| `build/t1100/.../Image` | `40a1d6fb…c047f` | 39 129 600 B, defconfig+`configs/t1100.fragment` (PSTORE, SIMPLEDRM), 0 warnings |
| `mt6771-fplus-t1100.dtb` | `f722a150…b88be` | 4 989 B, fb mappable |
| `build/payload_boot.img` | `9f3602dc…442e` | диагностический payload: рисует адрес загрузки и оба fb-base на экране |
| `build/boot_v1.img` | `379a0bc0…0338` | kernel по `0x40080000`, `text_offset=0x80000`, `nokaslr` |
| `build/boot_shim.img` | `848eb90f…5ffb` | shim: копирует `Image` на 2 МиБ-выровненный `0x44000000` и прыгает |

Инструменты: `tools/payload/` (адрес на экране), `tools/shim/` (релокатор),
`scripts/patch_image_header.py` (`text_offset`/`flags`).

**Порядок теста:** payload → фото экрана (адрес выровнен?) → при невыровненном
адресе `boot_shim.img`, иначе `boot_v1.img` / DTS на базе `mt8183.dtsi`.

## Тест 29.10 (вечер): WDT-дискриминатор и гипотеза размера

- Прошит `build/boot_wdtstop.img` (в `head.S` первой инструкцией стоп TOPRGU,
  md5 в `p29` сверен `90904d3b…`). **Плата всё равно ушла в цикл сбросов.**
  Вывод: наш код, судя по всему, **не исполняется**: иначе watchdog был бы
  остановлен (в payload Leonid'а тот же приём работает — плата висит).
- Значит проблема не в DTS/ядре, а в том, как `lk` загружает образ. Главное
  отличие нашего образа от рабочего payload — **размер**: стоковое ядро
  27,4 МБ (Image), наше **39,1 МБ** (`image_size` 39,98 МБ), payload — 328 Б.
  Гипотеза: `lk` не разжимает/не запускает такой большой образ.
- Собирается **минимальное ядро** (`configs/tiny.fragment`, O=`build/tiny`):
  только консоль/pstore/initramfs, без драйверов и модулей — ожидаемый `Image`
  единицы МБ. Это следующий тест на железе.
- Планшет возвращён в работу: `boot_a` = `boot_a_imaoff_nodiehard_nosig.img`
  (md5 `73417c46…`, сверен на устройстве), Aurora 4.14.186 поднялась,
  SSH `defaultuser@172.17.141.62` отвечает.

## Прорыв 29.10: причина boot-loop найдена (DTB для LK)

Найдено по проекту **PennyOS** (mainline на том же MT6771): LK **не прыгает в
ядро**, а падает в ASSERT/while(1) при подготовке device tree. Наши образы
нарушали минимум три правила из четырёх (`docs/lk-dtb-rules.md`):
нет `compatible = "mediatek,scp"`, статические `reserved-memory` пересекаются с
резервациями LK, `/__symbols__` не резолвит метки вендорского `dtbo_a`.

Сделано:
- снят `dtbo_a` (p31, 8 МиБ) с платы; внутри DTBO-таблица с 1 оверлеем
  (47 357 Б, `__fixups__` — **51 метка**: `odm, pio, chosen, scp, i2c0..11,
  mt6370_pmu, touch, keypad, …`);
- сгенерирован `mt6771-fplus-t1100-lk-compat.dtsi`
  (`tools/lk/gen-lk-compat-dtsi.py`): `/__symbols__` на инертные
  `/mtk-lk-sink/*`, `gpio@10005000`, `odm`, `scp` (`status="disabled"`);
- из `mt6771.dtsi` **удалён статический `reserved-memory`** (LK сам добавит
  `mblock-N-*`; ramoops — из cmdline);
- проверка офлайн: `fdtoverlay` применяет вендорский оверлей к нашему DTB
  **без ошибок** (rc=0), в merged-дереве есть `mediatek,scp`;
- собран `build/boot_fixed_tiny.img` (minimal 6.12 + исправленный DTB + initramfs,
  md5 `f90c5ea5…`) — **сбрасывался**: я удалил узел `/reserved-memory` целиком,
  а LK требует его существования (дописывает туда `mblock-*`);
- исправлено: узел оставлен, но **без статических детей**; офлайн-валидатор
  PennyOS (`refs/pennyos-lk/check-lk-dtb.py`) — **все правила ok**,
  `RESULT: LK should accept this DTB`;
- `build/boot_fixed2_tiny.img` (md5 `fb9b11d0…`) прошит — **плата СТОИТ и не
  сбрасывается**: LK принял DTB. Boot-chain пройден (LK больше не ASSERT'ит).
- Полное ядро с тем же DTB (`build/boot_fixed_full.img`, md5 `de34b2ec…`):
  на экране **логотип Aurora, сбросов нет**. Лог в `/proc/last_kmsg` — **не
  наш** (там старый вендорский); значит либо ядро не пишет в ramoops, либо LK
  всё ещё висит в while(1) (визуально неотличимо: лого + отсутствие сбросов).
- Найдено: в `build/tiny` **не было `CONFIG_PSTORE`** — `fs/pstore/Kconfig`
  подключён внутри `if MISC_FILESYSTEMS`, а в tinyconfig он выключен, поэтому
  опции молча отбрасывались. Включаем `MISC_FILESYSTEMS` + `PSTORE*`.
- Готов дискриминатор «ядро живо vs LK висит»: initramfs с **самоперезагрузкой
  через 30 с** (`scripts/make_initramfs.sh --action reboot --sleep 30`). Если
  плата сама перезагружается — ядро дошло до userspace.

Патчи 0001–0006 (шаги 1–2 фазы 1) пересобраны из дерева и запушены.

## Приоритет 29.10 (после решения владельца): Ubuntu + KDE

Цель v1 — **загруженная Ubuntu с рабочим столом KDE (Plasma/Wayland)**, а не
отладка ради отладки. Экранные «логи» и визуальные метки — **не нужны**
(владелец: «на экране видно только логотип Aurora»), канал диагностики —
`pstore` + USB-сеть, когда они заработают.

Поэтому меняем подход в фазе 1: вместо минимального самописного DTS берём
**SoC-DTS на базе mainline `mt8183.dtsi`** (клоки/pinctrl/eMMC/USB/IOMMU/DRM от
mt8183-драйверов; MT6771 совместим по адресам — `docs/research.md`) и
адаптируем board DTS из WIP-порта ровно нашего планшета
(`refs/mt6771-next/mt8788-fplus-t1100.dts`, 868 строк: `&mmc0/1`, `&ssusb`,
`&pio`, `&i2c0..6`, `&dsi0/&mipi_tx0`, `&gpu/&mfg`, `&iommu`, MT6358).

Порядок до KDE:
1. ядро с реальными драйверами (mt8183-база) + LK-compat → загрузка до userspace
   с USB-сетью (RNDIS) и eMMC;
2. rootfs Ubuntu-base arm64 + systemd → SSH/сеть;
3. DRM/KMS: `mediatek-drm` (OVL/RDMA/DSI) + панель BOE TV110XUM через IT6112
   (`refs/it6112/`, `refs/mt6771-next/`);
4. GPU panfrost (Mali-G72 MP3, `&gpu/&mfg`);
5. Wayland + KDE Plasma на дисплее.

## Почему логи нашего ядра «пропадают» (29.10)

Проверено на железе: `/sys/fs/pstore/console-ramoops` после возврата в Aurora
содержит лог **самой Aurora** (`systemd`, `msdc`), т.е. **каждая загрузка Aurora
перезаписывает pstore-зону** (`0x54410000`). Поэтому лог нашего mainline-ядра
там не сохраняется, и «нет лога» ≠ «ядро не запустилось».
`/proc/last_kmsg` в рекавери читает **SRAM** (`0x11d000`), а не DRAM-pstore, и
тоже не наш лог.

Вывод: пока нет UART и нет USB-сети, канала для логов нашего ядра фактически
нет. Поэтому приоритет — **ядро с USB (mtu3/RNDIS) и eMMC** (см. «Приоритет:
Ubuntu + KDE»), а не дальнейшие попытки «увидеть» лог.

## 30.10: ядро 6.12 загрузилось до userspace (первый лог!)

Получен **первый лог нашего ядра** (SRAM-«чёрный ящик» из initramfs, читается
`/proc/last_kmsg` в рекавери; сохранён: `refs/device/last_kmsg-6.12-first-boot.txt.gz`):

- `Linux version 6.12.114`, `Machine model: MT6771V/C`, `PSCIv1.0 detected`,
  `GICv3`, разметка памяти и все `mblock-*` от LK — **корректны**;
- ядро дошло до **userspace** (initramfs, PID 1) и жило 3603 с, затем паника
  `Attempted to kill init` — это наш init завершился по `sleep 3600`
  (исправлено: init теперь не выходит);
- `[Firmware Bug]: Kernel image misaligned at boot` — как у PennyOS, следствие
  `text_offset=0` и загрузки на `0x40080000`; безвредно;
- **ПМIC-цепочка — корень всех deferred probe**: `mt6358-regulator` падал
  (`vgpu: failed to get coupler: -ENOTSUPP`), из-за этого не регистрировались
  все регуляторы, а `mtk-pm-domains` не мог получить питание
  (`failed to get power supply`) → `mmc`, `usb`, `gpu`, `disp`, `iommu` — все
  «deferred probe pending» навсегда.
- Исправлено: из board DTS убраны `regulator-coupled-with/max-spread` у
  `vgpu`/`vsram_gpu` (mainline mt6358 их не поддерживает).

Новый образ `build/boot_full_net3.img` (md5 `462ae4bd…`) прошит; USB-гаджет
пока не появился — нужен следующий лог (SRAM) чтобы увидеть, что осталось.

## 30.10 (вечер): исправление PMIC/PD по эталону affenull

Разбор `bringup` (по коду, подтверждено логом):
1. `regulator-coupled-with` несовместим с generic coupler (только `always-on`) →
   `mt6358-regulator` выходил на первой ошибке ⇒ **ни одного рельса** ⇒ все
   `deferred probe pending`.
2. `power-domain@2` (MFG_ASYNC) без `domain-supply` в самом узле домена →
   `scpsys_probe` падал ⇒ провайдер power-доменов не регистрировался ⇒
   `mutex/ovl/rdma/dsi/larb*/smi/pwm/mfgcfg` навсегда deferred.
3. `mtk-ramconsole` не писал: искал узел `ramoops`, которого нет (ramoops из
   параметров) → `-ENODEV`.
4. `regulator_late_cleanup()` в mainline гасит «неиспользуемые» рельсы;
   у вендора защищены 16, в mainline — 14. Без `always-on` гасятся
   **VDRAM2/VBIF28** (питание LPDDR4X/bias) → SoC умирает до первого printk.

Исправлено: coupling убран, `&gpu { mali-supply; sram-supply }`, `&mfg_async`
получил `domain-supply`, `always-on` для VDRAM2/VBIF28/VAUX18/VIO28/VAUD28,
`mmc0/mmc1/ssusb/usb_host` включены, ранняя консоль ищет зону по `mblock-N-pstore`
и параметрам. Образ `build/boot_pmic2.img` (md5 `fd96f69d…`) прошит, планшет
перезагружен; USB-гаджет не появился — нужен лог (ранняя консоль) из рекавери.

## 30.10 (ночь): почему ранняя консоль молчит

`bringup` нашёл ошибку в `mtk-ramconsole`: зона ramoops лежит в system RAM,
а `ioremap()` на RAM возвращает `NULL` (`WARN_ON(pfn_is_map_memory)`), поэтому
драйвер молча получал `-ENODEV`. Исправлено (патчи 0015/0016): `memremap(WB)`,
формат `persistent_ram` руками, геометрия только из `ramoops.mem_*` в cmdline,
снимки на `early_initcall`/`postcore`/`arch`/`late_initcall_sync`;
`mt6358_regulator_probe` стал нефатальным по-рельсово.

**Факт с железа по `boot_pmic3.img` (md5 `dc99e2b6…`):** чёрный экран, USB нет,
в `/proc/last_kmsg` — **ни `T1100LOG`, ни новых строк** (файл тот же, 289537 Б,
uptime 3603 из старого прогона net2). Значит вариант с исправленными рельсами
умирает **до `early_initcall`**, т.е. раньше, чем может включиться любой наш
логгер. При этом вариант с `regulator-coupled-with` (net2) доходил до userspace.

Вывод: нужно бисектить не драйверы, а **разницу DTB** между net2 и pmic3
(coupling → рельсы регистрируются); смерть происходит в `start_kernel`-области,
что для правок регуляторов нелогично — вероятна ошибка в собранном DTB
(например, порядок/адреса узлов после `#include`), и это надо проверить
сравнением двух DTB, а не новыми правками.

## 30.10 (ночь, продолжение): ядро с PMIC-фиксами ЖИВОЕ

Дискриминатор без экрана и без USB: образ с initramfs, который сам делает
`reboot -f` через 30 с. Прошит `build/bisect_C_reboot.img` (pmic3 Image+DTB,
md5 `a061421c…`) — с хоста видно, что плата **циклически перезагружается**
(`usb 0e8d:2000` preloader появляется снова и снова). Значит ядро **доходит до
userspace**, а прежний вывод «умирает до early_initcall» был ошибкой метода:
initramfs `net3` просто жил в бесконечном цикле, и отсутствие USB трактовалось
как смерть.

Итог: PMIC/PD-фиксы работают на уровне «ядро живёт». Не работают: USB-гаджет
(`mtu3`/UDC) и запись логов в pstore (вероятно, `mtk-ramconsole` пишет в зону
раньше ramoops и ломает её заголовок). Следующий шаг — читать лог из рекавери
после такого прогона и править USB, затем eMMC.

## 30.10/31.10: где мы и что дальше

- **Работает:** mainline 6.12 грузится **до userspace**, PMIC/PD-фиксы держатся,
  ранняя RAM-консоль пишет (лог `refs/device/last_kmsg-pmic-cycle.txt.gz`).
- **Не работает:** eMMC (`mtk-msdc: Cannot find pinctrl` — в `mt8183.dtsi` у
  `mmc@11230000/11240000` нет pinctrl, их добавляет board DTS), USB-UDC
  (`mtu3` пробуется, `/sys/class/udc` не появляется — в логе нет ошибок,
  нужен маркер, добавлен патчем 0018).
- Вариант `boot_pmic4` (pinctrl для mmc + маркер UDC) прошит, но **лог не
  обновился** — то есть он умирает раньше pstore/ранней консоли, как и часть
  предыдущих DTB-вариантов. Требуется бисект: менять по одному свойству DTB и
  проверять дискриминатором «initramfs-reboot-30s» (виден с хоста как
  периодический `usb 0e8d:2000`), не гоняя владельца в recovery на каждую мелочь.
- **Следующая сессия:** (1) бисект DTB pmic3 → pmic4 по одному изменению;
  (2) при рабочем mmc — rootfs по `docs/ubuntu-rootfs-plan.md`; (3) DRM/DSI, затем
  panfrost и KDE.

## 31.10: итог сессии (для следующей)

**Что точно работает:** mainline 6.12 загружается до userspace на T1100 (PSCI,
GIC, память, PMIC/PD). Дискриминатор «initramfs-reboot-30s» виден с хоста.

**Что не работает (проверено на железе):**
1. **eMMC** — после добавления `pinctrl-0/1` для `&mmc0/&mmc1` из
   `refs/mt6771-next` лог всё ещё не получен, а запись лога в `expdb` (p3) из
   initramfs **не появилась** ⇒ eMMC не поднялся. Нужен либо правильный
   `pinctrl-mt6771` (пины/функции MT6771), либо сверка `mtk-sd`-свойств
   (hs400/`mediatek,*`) с affenull-DTS.
2. **USB-UDC** — `mtu3` пробуется, `/sys/class/udc` не появляется; маркер
   `UDC 'mtu3' registered` (патч 0018) в лог не попал, т.к. лог не пишется.
3. **pstore/ранняя консоль** — лог в `/proc/last_kmsg` перестал обновляться
   (последний живой лог — `refs/device/last_kmsg-pmic-cycle.txt.gz`). Вероятно,
   `mtk-ramconsole` и ramoops конфликтуют за зону; нужно проверить
   `ramoops_register_dummy` (legacy `ramoops.mem_*` в 6.12) и порядок записи.
4. **DRM** — ожидаемо: DSI0/DPI0 выключены; это следующий этап (KMS-панель
   BOE TV110XUM через IT6112, `refs/it6112/`).

**Следующая сессия (в этом порядке):**
1. Починить канал логов (pstore или expdb после eMMC) — без него мы слепы.
2. eMMC: сверить pinmux с affenull/cosmo и проверить `mtk-sd` на MT6771.
3. USB-UDC (mtu3 + tphy), затем RNDIS/SSH.
4. Rootfs Ubuntu (`build/rootfs/rootfs-t1100-base.tar.gz`,
   `docs/ubuntu-rootfs-plan.md`), затем DSI-панель, panfrost, KDE.

Планшет возвращён на рабочую Aurora (`boot_a_imaoff_nodiehard_nosig.img`).

## 31.10: eMMC работает, Ubuntu rootfs записан на p54

- Своя зона pstore (`ramoops@70000000`, не `nomap`) **решила проблему логов**:
  в `/proc/last_kmsg` приходит наш лог.
- **eMMC поднялся**: `mmc0: new HS400 MMC card`, `mmcblk0 … 57.6 GiB`,
  все разделы p1…p54 (лог: `refs/device/last_kmsg-emmc-ok.txt.gz`).
- `p54` переформатирован в **ext4** (метка `ubuntu`; LVM `sailfish` снесён —
  владелец подтвердил), распакован `rootfs-t1100-base.tar.gz`
  (105 МБ, hostname `t1100`, ssh, systemd-networkd).
- Прошит `build/boot_ubuntu.img` (md5 `47c1138f…`): наше ядро + DTB,
  **без initramfs**, cmdline `root=/dev/mmcblk0p54 rootwait rw`.
- Дальше: проверить по pstore-логу, дошёл ли systemd до multi-user;
  затем USB-UDC (сеть/SSH), KDE-пакеты, KMS-панель, panfrost.

## 31.10: Ubuntu 24.04 стартовала с eMMC

- Причина прежней петли: в ubuntu-base tarball **не было systemd** →
  `switch_root` не находил init → `Attempted to kill init`. `EXT4-fs
  (mmcblk0p54): mounted` при этом был — eMMC и монтирование работали.
- systemd/udev/dbus/openssh-server доустановлены в rootfs на хосте
  (`qemu-aarch64` + chroot, `Acquire::ForceIPv4`), rootfs пересобран
  (`build/rootfs/rootfs-t1100.tar.gz`, 192 МБ, 575 МБ на диске).
- `p54` переформатирован, rootfs распакован, прошит `build/boot_ubuntu3.img`
  (initramfs: ждёт `mmcblk0p54`, `switch_root /sbin/init`).
- **Наблюдение с хоста: циклических сбросов больше нет** — в отличие от
  предыдущих попыток, preloader `0e8d:2000` не появляется ⇒ система живёт
  (systemd поднялся). Подтверждение — по pstore-логу из рекавери.

Осталось: USB-UDC (сеть/SSH), затем KDE-пакеты (можно доставить в rootfs тем же
chroot-способом), KMS-панель, panfrost.

## Открытые вопросы

- **Панель закрыта**: активный LCM — `tv110xum_lb2_incell`, панель за мостом
  IT6112; init и тайминги есть в `refs/it6112/`.
- **reserved-memory**: `framebuffer` (`0x7cd80000`+`0x2e80000` = конец
  `0x7fb80000`) и `items-reserved` (`0x7fc00000`) **не пересекаются** (зазор
  `0x80000`) — поправка к прежней записи. `md-mem-usage` (256 МиБ) — первый
  кандидат на снятие (в стоке это System RAM), затем `vpu-binary`,
  `framebuffer`, `items-reserved`.
- **`simple-framebuffer`**: adomerle использует `0x7cb80000`, наш стоковый
  резерв — `0x7cd80000`. Сверить на железе, какой адрес реально отдаёт LK.

## Риски

- Дисплей: нет TRM, только исходники; объём `mediatek-drm` снижен благодаря
  MT8183-совпадению и готовому IT6112-драйверу.
- Тач Himax — отдельный драйвер (`himax,hx83102e` в adomerle DTS).
- Wi-Fi/BT: CONSYS_6771 (MT6630/MT6631) в mainline не поддержан; вендорский
  стек `wlan_drv_gen3` + `wmt_drv` + `/vendor/firmware` — отдельный крупный
  порт; сейчас Wi-Fi/BT не работают, сеть только RNDIS (см. 10.11 ниже).
- Прошивка: только через recovery/`dd` с бэкапом `boot_a`/`vbmeta`/`seccfg`.
- Отладочные MTK-узлы опасны: запись в `/proc/dispsys`/`/proc/clkdbg` валит
  стоковое ядро (проверено 28.10.2026).

## Референсы

- `docs/provenance.md` — хеши ядра/тулчейна/артефактов и как воспроизвести.
- `refs/stock-mt6771.dts` — DTS из boot-DTB (карта регистров).
- `refs/device/fdt-live.dts.gz` — живой FDT с dtbo.
- `refs/it6112/` — драйвер панели (WIP) + README с фактами.
- `refs/mt6771-next/` — полный board DTS и `mt6771.dtsi` из linux-mediatek.
- `configs/t1100.fragment` — Kconfig-фрагмент первой сборки.
- `patches/series` — порядок применения патчей.

## Сессия 29.10.2026: первый реальный тест загрузки

**Что проверено на железе**

- **Доступ**: recovery по USB (`telnet 10.42.66.66:23`, меню `3` → `y` **без
  Enter** → код блокировки), Aurora по SSH (`defaultuser`, пароль через
  `T1100_SSH_PASS`; root — `devel-su` с тем же кодом). Смена IP по DHCP:
  `.62` → `.129`.
- **Разделы** (`/dev/disk/by-partlabel`): `boot_a = mmcblk0p29`,
  `boot_b = mmcblk0p45`, `vbmeta_a = p16`, `seccfg = p11`.
- **AVB не мешает**: стоковый образ с одним изменённым байтом в хвосте
  загрузился (sha `2aaf62c9…`), т.е. проверка `boot_a` не блокирует
  модифицированные образы.
- **Главная находка**: у нашего `Image` `text_offset = 0x0`, у стокового
  `0x80000`. По протоколу ARM64 образ с `text_offset=0` требует загрузки по
  **2 MiB-выровненному** адресу, а LK (по заголовку boot.img) грузит на
  `0x40080000` — не выровнено. Это лучший кандидат на причину «нет ни одного
  printk»: ядро падает до консоли.
- Пробовали: `panic=0`, отключение PSCI, остановку TOPRGU-watchdog на
  `early_initcall`, запись в ramoops console zone (3 кандидатных смещения),
  simpledrm/fbcon на буфере LK (`0x7cd80000`), адрес загрузки `0x40200000`.
  Ни один вариант не дал лога/текста на экране; планшет уходил в сброс через
  preloader (период ~15–50 с).
- `ssh` до Aurora после падения не теряется: `console-ramoops` в
  `/sys/fs/pstore` показывает лог **предыдущей** загрузки — это рабочий канал
  для следующего шага.
- После каждого теста стоковый `boot_a` возвращён; сейчас Aurora работает
  (сток, 4.14.186), `boot_a` = `9601bcd6…`.

**Следующий шаг (boot)**

1. Выяснить, по какому адресу LK реально грузит ядро (LK для MT6771:
   `BOOTIMG_LOAD_ADDR`, обычно `0x40080000`, заголовок может игнорироваться).
2. Если LK игнорирует `kernel_addr`: либо патчить `text_offset`/загрузчик,
   либо проверить, действительно ли 2 MiB-выравнивание фатально для 6.12.
3. Альтернативы: `kexec` из стока (в стоковом конфиге `CONFIG_KEXEC` нет),
   `lk2nd`, либо подписать/подменить загрузчик — только после бэкапа.
4. Пока не подтверждён запуск mainline, не тратить время на PSCI/дисплей:
   сначала один лог с `early_initcall`.

## Дополнение: LK, прошивка и тест заглушки

- Снят **LK с платы**: `lk_a = mmcblk0p28`, 8 МиБ, sha256
  `f94d45b1c1c0e45009872a339abc23b34f955251b1823ec00abd6c3abd078c88`
  (дамп в `/tmp/opencode/lk_a.bin`). Внутри — MTK LK для
  `devices/fplus_t1100/lk/platform/mt6771`; есть отладочные строки
  `mboot_android_load_bootimg`, «Android Boot IMG Hdr – Kernel Address»,
  «mkimg header exist/absent».
- Найден локальный пакет **Aurora 5.1.6.230** (`offline-repos/out/...aarch64`):
  `hybris-boot.img` побайтово совпадает с началом нашего дампа `boot_a`
  (значит на плате именно 5.1.6.230); `lk-verified.img` из пакета **не
  совпадает** с прошитым LK (другая сборка) — анализировать надо дамп.
- Собрана минимальная arm64-заглушка (`/tmp/opencode/payload`): пишет маркер
  `T1100PLD` + адрес исполнения в 3 кандидатные ramoops-зоны и в
  `0x54400000`, заливает 128 КиБ белым в буфер LK, затем `wfi`; `Image`
  полного размера (`image_size=0x1a2e800`, как у стока).
- Заглушка **не дала ни белого экрана, ни маркера** в `/proc/last_kmsg`;
  планшет уходит в сброс (чёрный экран → лого → чёрный). То есть вопрос не в
  размере ядра и не в 6.12: LK/цепочка не запускает наш образ.
- Сток после каждого теста восстановлен; сейчас Aurora 5.1.6.230 работает.

**Следующее направление**: получить исходники LK
(`omp-bootloader-src-mtk-lk 0.4.6` из OBS Aurora) и посмотреть
`mboot_android_load_bootimg`: какие проверки (mkimg/secure boot/размер/адрес)
отбраковывают образ. Без этого дальнейшие догадки малопродуктивны.

## 02.11: попытка «экранной консоли» — упёрлась в приём DTB загрузчиком

**Что сделано:** возвращён `/chosen/framebuffer` (0x7cd80000, 1600×2176,
stride 6400) и включён `CONFIG_DRM_SIMPLEDRM=y`, собрано ядро (0 warnings).
Дополнительно initramfs теперь пишет `dmesg` в раздел `expdb` (p3) — канал
диагностики, не зависящий от pstore и дисплея.

**Результат:** текста на экране нет, и маркер «T1100-INITRAMFS-RAN» в p3
**не появился** — initramfs не запускался, т.е. ядро не получало управление.

**Решающий тест:** заглушка `probe-payload` (отключает TOPRGU и виснет) с
**нашим lk-compat DTB (патчи 0001–0019)** → плата уходит в сброс; та же
заглушка со **стоковым DTB** → плата **зависает** (LK её запускает).

**Вывод:** на этом устройстве **LK по-прежнему не принимает наш DTB**
(`check-lk-dtb.py` проверяет не всё; вероятно, мешает реальный `dtbo_a`/
форма `/chosen`). Поэтому милстоуны из документации (mainline до userspace,
eMMC, Ubuntu) с закоммиченными патчами здесь **не воспроизводятся** — их
сборочные артефакты остались на другой машине.

**Следующее:** получить с той машины точный DTB/образ рабочей сборки (сравнить
`sha256` и diff DTS) либо добить правила LK по реальному `dtbo_a` (наложение
overlay, `/__symbols__`, форма `/chosen`). Экранная консоль и всё дальше — после
того, как LK начнёт передавать управление нашему ядру.

Планшет восстановлен: Aurora 5.1.6.230, `boot_a` = сток (`9601bcd6…`).

## 02.11 (вечер, lead): проверка «LK не принимает DTB» — не подтверждается

**Факт 1. Наш DTB в дереве байт-в-байт равен DTB из образа, который загрузился.**
DTB вынут из `build/boot_ubuntu3.img` (тот самый прогон, что дал лог
`/proc/last_kmsg` от 30–31.10: 6.12 → userspace, eMMC HS400, pstore) и сравнён
со сборкой текущего дерева (`cpp -D__DTS__` + `dtc`):
оба — `52900` Б, sha256 `e11c39df…80e186`, `cmp` → идентичны. Значит вывод
02.11 «LK по-прежнему не принимает наш DTB» **не доказан**: уличаемого
различия DTB нет, а артефактов того прогона в `build/` не осталось (новых
файлов за 02.11, кроме `build/lk/lk_ubuntu_final.txt`, нет), т.е. точный
прошитый образ неизвестен. Повторять «правку правил LK» по этой гипотезе не
имеет смысла.

**Факт 2. Что реально лежит на плате (снято через recovery).**
- `p29` (`boot_a`) = `build/boot_ubuntu3.img`: `ANDROID!`, kernel `14485775` @
  `0x40080000`, ramdisk `1031181`, DTB `52964` (MTK-обёртка = 0x40 + 52900),
  cmdline `… root=/dev/mmcblk0p54 rootwait rw panic=10 …`.
- `p54` — Ubuntu 24.04.3 LTS, 587 МБ занято: `/usr/lib/systemd/systemd` (133 КБ),
  `/sbin/init → ../lib/systemd/systemd`, `ssh.service` и
  `systemd-networkd.service` **включены**, есть
  `/etc/systemd/network/usb0.network` → `Address=10.42.66.66/29`.
- Значит rootfs готов; логи 30.10 снимались, когда systemd ещё не был
  установлен.

**Факт 3. Причина паники 30.10 — не eMMC и не initramfs.** В логе
`EXT4-fs (mmcblk0p54): mounted filesystem … r/w` (t=1.395), сразу за ним
`Attempted to kill init! … Comm: switch_root` (t=1.403): `switch_root` ушёл с
кодом 1, потому что в rootfs тогда не было `/sbin/init`. Теперь он есть ⇒
образ можно просто перезагрузить, ничего не меняя в DTB/ядре.

**Факт 4. mtu3 по логу:** probe проходит (`dr_mode: 2` = peripheral, задан DT,
`USB_MTU3_DUAL_ROLE=y`, `# CONFIG_USB_MTU3_HOST is not set` — принудительный
host-режим исключён), но `IP version 0x0` против `0x20160812` у вендора ⇒
регистр `U3D_SSUSB_IP_TRUNK_VERS` в IPPC на MT6771 лежит иначе, чем в
`mt8183.dtsi`. Наличие `/sys/class/udc` этим логом не проверялось.

**Решение:** идём дальше по функциональной ветке, а не по «правилам LK»:
пересобрать ядро текущим деревом (патчи 0001–0019, в т.ч. лог UDC из 0018),
initramfs теперь сам поднимает RNDIS + `telnetd` на 2323 до `switch_root`
(канал, переживающий `switch_root`) и пишет снимки `dmesg` в `p3` (expdb),
затем `switch_root` в Ubuntu. Проверка — USB-сеть с хоста
(`tools/host/usb-net.sh`), без похода в recovery.

## 02.11 (ночь): **Ubuntu 24.04 + systemd загрузилась на железе**; USB не энумерируется

Прошит `build/boot_ubuntu4.img` (md5 `30729fab…`, sha256 `e2183a39…de2a0e`):
ядро текущего дерева (`Image` sha256 `afedc97a…`, 0 warnings, `O=build/k1`),
наш initramfs с RNDIS/telnetd, DTB `e11c39df…` (тот же, что в рабочем
`boot_ubuntu3`), `KERNEL_ADDR=0x40080000`, `root=/dev/mmcblk0p54`.
Прошивка через recovery по USB (`tools/host/recovery.py put`), md5 на устройстве
сверен: `30729fab…` — совпадает.

**Подтверждено журналом systemd с самой платы** (`refs/device/journal-ubuntu4-first-boot.txt.gz`):

```
systemd[1]: Reach target sysinit/basic/getty/usb-gadget/multi-user/graphical
systemd[1]: Startup finished in 3.540s (kernel) + 2.279s (userspace) = 5.819s
```
То есть **mainline 6.12 + Ubuntu 24.04 + systemd дошли до multi-user и
graphical.target**; hostname `t1100`. Отключение питания в 20:01:24 — это
**нажатие кнопки питания** (`systemd-logind: Power key pressed short` →
`Powering off`), а не падение.

**Что сломалось и уже исправлено:** `ssh.service` падал с
`/etc/ssh/sshd_config: No such file or directory` — в rootfs из ubuntu-base
`openssh-server` распаковался не полностью (в `/etc/ssh` лежали только
`*.dpkg-new`). С хоста починено на `p54`: `sshd_config`, `ssh_config`, `moduli`,
хостовые ключи (ed25519+rsa) и `root/.ssh/authorized_keys` (ключ этого хоста).
SSH заработает, как только поднимется USB-сеть.

**USB: гаджет собран, но хост его не видит.** Из dmesg
(`refs/device/dmesg-ubuntu4-boot.txt.gz`):

```
mtu3 11201000.usb: IP version 0x0(U3 IP)          <-- у вендора на этом SoC 0x20160812
mtu3 11201000.usb: UDC 'mtu3' registered          (маркер патча 0018)
configfs-gadget.t1100 gadget.0: MAC e6:df:28:4a:fa:b8
mtu3 11201000.usb: gadget (high-speed) pullup D+
```
`/sys/class/udc` = `11201000.usb`, `usb0` создан и `UP`, `carrier:0`; ошибок нет.
При этом на хосте за 2,5 минуты работы ядра — **ни одного нового USB-устройства**
(был только preloader `0e8d:2000` при загрузке и тишина после).
Значит D+ pull-up не доходит до разъёма: MAC пишет бит, а порт U2/IPPC не включён.

**Рабочая гипотеза (делегирована `bringup`):** `mt6771.dtsi` берёт `&ssusb` из
`mt8183.dtsi`, а идентификаторы гейтов там mt8183-шные: `CLK_INFRA_UNIPRO_SCK=61`,
`CLK_INFRA_USB=90`. В стоковом DTB MT6771 у того же узла клоки `<0x15 0x5b>` и
`<0x15 0x3e>` — **91 и 62**, ровно на 1 больше. Если биты гейтов уехали, IPPC не
так hard-тактируется, `U3D_SSUSB_HW_SUB_ID` (IPPC+0xA4) читается 0, а запись
«power on U2 port» уходит в никуда. Побочно это объясняет, почему eMMC/PMIC
работают: их гейты оставил включёнными LK, а USB-гейты LK при передаче гасит.

**Перепроверка вывода 02.11 «LK не принимает наш DTB» — не подтверждается:**
DTB из дерева байт-в-байт равен DTB внутри `boot_ubuntu3.img` (`e11c39df…`) и
внутри `boot_ubuntu4.img`; ядро с ним загрузилось до userspace (журнал выше).
Оффлайн-валидатор LK против `dtbo_a` этого планшета — 10/10 ok. Протокол и
инструменты: `docs/lk-dtb-verification.md`, `tools/lk/`.

**Артефакты этой ночи:** `build/boot_ubuntu4.img`, `build/k1/…/Image`,
`build/k1/…/mt6771-fplus-t1100.dtb`, initramfs `build/initramfs_root_usb.cpio.gz`;
`build/full` после прерванного `merge_config` **рассогласован** — для сборки
использовать `build/k1` (в нём тот же `.config`).

## 03.11 (после полуночи 02.11): **USB работает, SSH в Ubuntu с планшета — фаза 1 закрыта**

**Патч 0020 (форс device-сессии T-PHY) решил блокер с первого прогона.** Хост
увидел гаджет на 20:37:13:

```
usb 1-1.3: New USB device found, idVendor=1d6b, idProduct=0104
usb 1-1.3: Product: T1100 Ubuntu / Manufacturer: Fplus / SerialNumber: T1100-0001
rndis_host 1-1.3:1.0 usb0: register 'rndis_host' ... → enxaa5eb20b97a3
```
Доказательство причины — строка самого патча:
`phy phy-soc:t-phy@11f40000.0: forced device session: DTM1 0x000024 -> 0x003626`
(было `RG_IDDIG=1` и ни `VBUSVALID`, ни `SESSEND`-форса ⇒ PHY считал себя
хостом; после форса выставлены `FORCE_IDDIG|RG_IDDIG|FORCE_AVALID|
FORCE_SESSEND|FORCE_VBUSVALID`).

**Итог на 20:39 (по SSH):**
```
Linux t1100 6.12.114-gd7e8f7f1dd86 #2 SMP PREEMPT aarch64
PRETTY_NAME="Ubuntu 24.04.3 LTS"
systemctl is-system-running → running;  failed units → нет
UDC 11201000.usb;  usb0 = 10.42.66.66, networkd State: routable (configured)
mmcblk0 57.6G / mmcblk0p54 50.1G;  Mem 3542 MB;  load 0.00
```
Хост: `10.42.66.67/29` на `enx…` (RNDIS), `ping` 0.10–0.26 мс,
`ssh root@10.42.66.66` по ключу — доступ есть.

**Что было починено по дороге (важно для будущих сессий):**
1. `patches/0020` — `mediatek,force-device-mode` в `phy-mtk-tphy` (+DT-флаг у
   `&u2port0`). Клок-гипотеза **опровергнута**: гейты USB у MT6771 и MT8183
   совпадают побитно (INFRA2 bit 1/bit 11), раскладка IPPC тоже; ID в стоковом
   заголовке — просто «+1» из-за занятого слота 0.
2. В rootfs не было пользователя `sshd` → `ssh.service` падал
   (`Privilege separation user sshd does not exist`). Добавлены
   `sshd:x:110:` в passwd/group/shadow/gshadow, а также `sshd_config`,
   `ssh_config`, `moduli`, хостовые ключи (ed25519/rsa) и
   `root/.ssh/authorized_keys` (ключ этого хоста).
3. initramfs: монтируется `devpts` (без него busybox `telnetd` рвёт соединение),
   `chroot /mnt /usr/sbin/sshd -t` пишет результат в expdb.

**Артефакты:** `build/boot_ubuntu6.img` (md5 `7a67a79d…`, sha256 `31fe2596…`),
`Image` sha256 `59bfb0b4…` (`O=build/k1`), DTB `f8d935da…` (валидатор LK 10/10),
`refs/device/dmesg-ubuntu6-ssh.txt.gz`.
Откат: `build/boot_ubuntu5.img` / `boot_ubuntu4.img` / `boot_ubuntu3.img` /
сток `../t1100/backup_5.1.6.110/boot_a_imaoff_nodiehard_nosig.img`.

### Фаза 1 — принята
Критерий «ядро+DTB грузятся до консоли/USB, RAM/eMMC видны» выполнен:
mainline 6.12 + наш DTB → systemd `running`, eMMC HS400 и все 56 разделов,
RAM 3.5 ГБ, USB-RNDIS и SSH. Дальше — **фаза 2 (KMS)**: `mediatek-drm` без
DSI0/DPI0 не собирает CRTC (`Need at least one OVL device`), нужен `&dsi0`
+ панель BOE TV110XUM через IT6112 (`refs/it6112/`) и mmsys-route.

### Как подключиться (для следующей сессии)
```sh
tools/host/usb-net.sh up        # 10.42.66.67/29 на RNDIS-интерфейсе (нужен root: sudo)
ping 10.42.66.66
ssh root@10.42.66.66            # ключ ~/.ssh/id_ed25519 уже в authorized_keys
```
Прошивка/логи без SSH — `tools/host/recovery.py` (recovery: `telnet 10.42.66.66`, меню `3` → `y`).

## 03.11: фаза 2 в работе — KMS-стек поднят, экран чёрный

Патчи `kernel-drm` 0021–0026 (панель IT6112/BOE TV110XUM-LB2, DSI0, MT6370 DSV,
подсветка) собраны и прошиты (`build/boot_ubuntu7.img`). Стек KMS **работает**:

```
it6112_bridge 3-0056: IT6112 bridge found, product id 0x6112
mediatek-drm: bound ovl*3/rdma*2/color/ccorr/aal/gamma/14014000.dsi
[drm] Initialized mediatek 1.0.0 … ; fb0: mediatekdrmfb
dummy 3-005e: RCLK=25MHz ; it6112_bridge: MCLK=199MHz
```
По SSH: `card0-DSI-1` = `connected`, `enabled`, `1600x2176`; `/dev/fb0`
1600×2176 32bpp; CRTC `active=1`; подсветка `pwm-0 … duty 500000ns`
(100 %), `gpio-568 (enable) out hi`, DSV `vpos/vneg` 5500 мВ.
**Но экран чёрный** — картинка не доходит до панели.

Диагностика без пересборки:
- `devmem` недоступен (`/dev/mem` denied), `/proc/interrupts` для DSI = 0
  (в video-mode IRQ не используются — не признак).
- Собран `tools/i2cpeek`; регистры моста читаются и **совпадают с тем, что
  писал драйвер**: TX `0x56`: `05=00 24=01 3c=23 44=0d 45=23 47=12 b0=27`;
  RX `0x5e`: `09=ff 0a=ff 0b=3f 18=43 27=3e 72=07 0c=03 11=03 19=03 21=08
  44=22 8a=02 a0=01 80=07`. `0x21 bit3` = RX автоопределил DSI video format ⇒
  **DSI до моста доезжает**.
- `kernel-drm` доказал (по таблице MIPI-ECC `sun6i_dsi_ecc_array`), что 4 байта
  в регистр `0x73` — корректный short-packet с ECC (0x36/0x1c/0x2c/0x06), т.е.
  DCS-протокол референса верен; и что 1534.8 Мбит/с у нас против 1580 у
  вендора — не причина (лимиты downstream 1–2 Гбит/с, `posdiv=1`).

**Следующий шаг:** патчи 0027 (поднять `stby-gpios` GPIO44 и `ext-pwr-gpios`
GPIO175 — единственное известное расхождение с вендорным LCM; в стоковом dmesg
`elink_configurate_gpio … stby-gpios … active = 1`) и 0028 (замеры клоков в
`enable()` + дампы регистров моста «до потока / с потоком»), затем S2: повторная
отправка `exit sleep`/`display on` через `i2cpeek` уже после снятия `HOLD_TX`.

### 03.11: 0027/0028 — STBY/EXT_PWR и дамп моста; экран всё ещё чёрный

`build/boot_ubuntu8.img` (md5 `999cde9e…`), ядро `6.12.114-g8c7d1a98bf6a`:
`IT6112 bridge found, product id 0x6112 (stby yes, ext-pwr yes)` — пины GPIO44
(STBY) и GPIO175 (EXT_PWR) подняты, как у вендора.

Дампы моста (`pre-stream` → `stream-on` → `post-dcs`) дали главное:
- **DSI-линк до моста живой**: RX-регистры меняются при старте потока
  (`0x5e 0x0d: 0x69 → 0x61 → 0x71`), `0x21 bit3` = автоопределение video-формата;
- TX-регистры (`0x56`) читаются ровно тем, что записал драйвер
  (`05=00 24=01 3c=23 44=0d 45=23 47=12 b0=27`), после `post-dcs` без изменений;
- `RCLK=25MHz`, `MCLK=193MHz` (в прошлом прогоне 199) — при живом потоке;
- повторная отправка `exit sleep`/`display on` в `0x73` после снятия `HOLD_TX`
  (`0x05=0xfe`, `0x05=0x00`) результата не даёт.

Итог: мост настроен и видит DSI, питание/подсветка/пины в норме, но **панель
не выводит изображение**. Публичного init-тейбла BOE TV110XUM нет; в WIP-порте
adomerle узел панели вообще был `status = "disabled"`, то есть код end-to-end
никем не проверялся.

**Дальше:** `reverse-engineer` — вытащить из вендорского `boot_a_5.1.6.110.img`
последовательность I2C-записей в IT6112 и init панели (DCS через `0x73/0x74/0x75`),
сравнить с нашим драйвером (в частности, dual-channel TX: README `refs/it6112`
говорит «DSI → dual-channel»), и подготовить патч 0029+.

**Прочее по процессу:** маскированы `sleep/suspend/hibernate/hybrid-sleep`
таргеты на устройстве (RNDIS рвался после простоя), `power/control=on` для
`11201000.usb` ставится systemd-юнитом; host-интерфейс нужно снимать с
управления NetworkManager (`tools/host/usb-net.sh` уже это делает).

## 03.11: «пропажи» планшета — это разряд батареи, а не зависание

Трижды за сессию планшет исчезал с USB через 10–20 минут работы; владелец
сообщил, что он **разрядился в 0**. Причина подтверждается конфигом:

| Символ | Состояние |
|---|---|
| `CONFIG_CHARGER_MT6370` | not set |
| `CONFIG_TYPEC` / `TYPEC_TCPCI` | `=m` (модулей в образе нет) |
| `CONFIG_TYPEC_TCPCI_MT6370` | not set |
| `CONFIG_MFD_MT6370` / `REGULATOR_MT6370` | `=y` (только DSV панели) |

В mainline 6.12 драйверы есть (`drivers/power/supply/mt6370-charger.c`,
`drivers/usb/typec/tcpm/tcpci_mt6370.c`), но не включены и в DTS нет узлов
`charger`/`tcpc`/`usb-c-connector` — зарядку настраивает только LK, и после
передачи управления она прекращается. Отсюда же «нет логов и нет сбросов»:
плата просто выключается по низкому напряжению.

**До фикса:** заряжать при выключенном планшете (зарядку ведёт LK), либо от
мощного зарядника, а не от USB-порта ноутбука. `bringup` получил задачу
включить `CHARGER_MT6370` + `TYPEC_TCPCI_MT6370` и описать узлы в DTS, **не
сломав peripheral-гаджет** (TCPC умеет перетягивать роль — из-за этого его
раньше выключали).

### 03.11: зарядка — патчи 0031/0032 и конфиг

`bringup` подготовил:
- **0031** (`armsoc dts`): узел `charger` (`mediatek,mt6370-charger`) с
  `interrupts/interrupt-names` = `uvp_d_evt`/`attach_i`/`mivr` (hw-номера
  irqchip MT6370: 68/48/6) и `io-channels` из `mt6370_adc` (порядок важен:
  `ibus` — 5-й, короче 6 нельзя — драйвер индексирует массив);
- **0032**: `tcpc` (`mediatek,mt6370-tcpc`) в **sink-only** (`power-role =
  "sink"`, `data-role = "device"`, `pd-disable`) с `interrupts-extended` на
  GPIO41; **без** `ports`/`usb-role-switch` — иначе при нашем
  `dr_mode = "peripheral"` `mtu3` не регистрирует role-switch
  (`mtu3_plat.c:275`, ранний `goto out`), tcpm получает `-EPROBE_DEFER`
  навсегда; а при `dr_mode = "otg"` порт встаёт хостом и RNDIS/SSH умирает.

Конфиг (добавлен в `configs/t1100.fragment`):
```
CONFIG_CHARGER_MT6370=y
CONFIG_MEDIATEK_MT6370_ADC=y      # без него charger вечно в -EPROBE_DEFER (IIO-каналы)
CONFIG_TYPEC=y                    # TYPEC=m блокирует сборку tcpm в ядро
CONFIG_TYPEC_TCPM=y
CONFIG_TYPEC_TCPCI=y
CONFIG_TYPEC_TCPCI_MT6370=y
```

Известные ограничения, которые надо помнить на железе:
- в mainline **нет топливомера** (`mt6358_gauge` вендорский) ⇒ в
  `/sys/class/power_supply/` не будет `capacity`, только `mt6370-charger`
  (`online`, `status`, `charge_type`, `usb_type`, лимиты) и
  `tcpm-source-psy-mt6370-tcpc.N`;
- `mt6370-charger` ставит `F_USBCHGEN=0` до прерывания `attach_i` и жёстко
  пишет `ICHG=900 мА` (вендор ставил 2 А) — при необходимости поднимать из
  userspace: `echo 2000000 > /sys/class/power_supply/mt6370-charger/constant_charge_current`;
- процентов заряда не будет; «идёт ли заряд» = `online=1` + `status=Charging`
  (+ рост `vbat` через IIO).

### 03.11: «не выключается» — PSCI SYSTEM_OFF не снимает рельсы PMIC

Симптом: `systemctl poweroff` не обесточивает плату, через время она сама
перезагружается в нашу `boot_a`.

Причина (по коду): обработчик выключения **был**, но не тот — для PSCI ≥ v0.2
ядро безусловно ставит `pm_power_off = psci_sys_poweroff`
(`drivers/firmware/psci/psci.c:630`), и `do_kernel_power_off()` подхватывает его
как legacy-хендлер (`kernel/reboot.c:666-669`). На MT6771 `PSCI SYSTEM_OFF` не
снимает рельсы PMIC (это делает PMIC по RTC-последовательности), поэтому
получается сброс вместо выключения.

Патч **0033** (`rtc: mt6397: power off MT6358/MT6397 through the RTC block`):
в `rtc-mt6397.c` регистрируется `sys_off`-обработчик `SYS_OFF_MODE_POWER_OFF`
(`SYS_OFF_PRIO_DEFAULT`), который пишет `RTC_BBPU = KEY`, дёргает `WRTGR`
(`0x3a` для MT6358 / `0x3c` для MT6397) и ждёт снятия `CBUSY` — тем же
`mtk_rtc_write_trigger()`, что уже есть в драйвере. `addr_base` берётся из
MFD-ячейки (`MT6358_RTC_BASE 0x588`), поэтому DT менять не нужно. MT6323 не
затронут (у него отдельная запись `mtk_rtc_data`).

Проверка на железе: хвост dmesg должен содержать `Power down` и
`mt6397-rtc ...: powering off`, после чего плата гаснет; если вместо этого
`WARNING … Unable to power off system` — последовательность для MT6358 не
подошла, сверять с LK/ATF. Watchdog исключён: `mtk_wdt` не стартует на probe, а
`WDOG_STOP_ON_REBOOT` останавливает его на `SYS_POWER_OFF` раньше нашего
обработчика.

Попутно: host-side профиль NetworkManager был привязан к `enx*` и раздавал
`10.42.66.67/29` любому RNDIS-устройству (в том числе чужому планшету
Byterg MVK-2020); теперь интерфейс T1100 переименовывается udev-правилом в
`t1100usb` по USB ID `1d6b:0104`, и профиль матчится по этому имени.

## 05.11: **зарядка работает**; выключение — патч 0034 (вендорская последовательность)

Образ `build/boot_ubuntu13.img` (md5 `9d5aaca970beed301dd2a94812cc0927`), ядро
`6.12.114-g…` с 0031–0033, DTB `…` (валидатор LK ok). Сразу после загрузки по SSH:

```
/sys/class/power_supply/mt6370-charger:
  online=1  status=Charging  charge_type=Fast
  usb_type=[Unknown] SDP DCP CDP
  constant_charge_current=900000  constant_charge_voltage=4350000
  input_current_limit=500000
IIO: vbus=4940 мВ, vsys=3635 мВ, vbat=3645 мВ, ibus=400 мА
```
То есть mainline-зарядка MT6370 работает (от порта ноутбука — 500 мА).

Что для этого понадобилось:
- `CONFIG_CHARGER_MT6370`, **`CONFIG_MEDIATEK_MT6370_ADC`** (без него charger
  навсегда в `-EPROBE_DEFER`: `probe … returned -517`, затем успешно после того,
  как ADC поднялся), `CONFIG_TYPEC*` — всё `=y`;
- узел `charger` с `interrupts`/`interrupt-names` `uvp_d_evt`/`attach_i`/`mivr`
  и 7 IIO-каналами;
- **`tcpc` пришлось выключить**: `tcpci_parse_config()` не находит дочерний
  узел `connector` у MFD-платформенного устройства и probe падает с `-EINVAL`
  (`mt6370-tcpc …: error -EINVAL: Failed to register tcpci port`). Для зарядки
  TCPC не нужен; вернёмся к нему, когда будем делать OTG/host.

**Выключение.** Патч 0033 (рецепт MT6323: `BBPU=KEY` + `WRTGR` + poll) на
MT6358 **не гасит рельсы**: ядро зависает в `poweroff`, USB-гаджет остаётся на
шине, плата не перезагружается и не выключается. `reverse-engineer` вытащил из
LK (`rtc_power_off()` @`0x5601c510`, `mt_power_off()` @`0x5601b214`) точную
вендорскую последовательность: `BBPU |= KEY|BIT(5)`, промежуточная
`BBPU=0x4303` c ожиданием self-clear bit1, `0x001e` bit1/bit3, `0x051a` bit2,
`0x5a0`/`0x590` (сброс алярма), `0x5ac`/`0x5ae` (спары), `0x5bc` OSC32CON
(`0x586a`→`0x9136`), и в конце **снятие `POWER_HOLD`** (`0x0a08` bit0) —
именно этого нет в MT6323-рецепте.

Патч **0034** (`rtc: mt6397: reproduce the vendor MT6358 RTC power-down
sequence`, коммит `a6624bb1d`, файл `patches/0034-…`) реализует это с
`regmap_read_poll_timeout_atomic` (sys-off идёт с выключенными прерываниями) и
`dev_info` на каждом шаге, чтобы по pstore было видно, где оборвалось.

### 05.11: подтверждено — 0034 выключает плату

`systemctl poweroff` на `boot_ubuntu14` (kernel `ga6624bb1d219`):

```
15:10:08  гаджет отключился
15:10:10  preloader 0e8d:2000  (плата стартовала заново)
15:10:19  снова наш гаджет → Ubuntu
```

Признак того, что рельсы **реально снимались**: `/sys/fs/pstore` после этого
**пуст** — DRAM обесточена (при обычном ребуте ramoops с логом предыдущей
загрузки остаётся). То есть 0034 (вендорская последовательность MT6358
`BBPU` + `POWER_HOLD`) работает, а «перезагрузка» после него — это штатный MTK
«boot on charger»: плата включаетcя от VBUS. Чтобы оставить её выключенной,
нужно выдернуть кабель до/во время выключения.

Итог по двум блокерам: **зарядка и выключение в mainline работают**.

### 05.11: причина чёрного экрана найдена — `DSI_START` не писался

Симптом: CRTC активен, режим вендорский, мост настроен как в LK (проверено
побайтным повтором через `i2cpeek`), но **`/proc/interrupts` для
`14014000.dsi` = 0** при любом числе кадров, а на экране черно. То есть поток
кадров не запускался вообще.

Причина в нашем драйвере панели (унаследована от WIP-порта):
- `it6112_bridge_probe()` (I2C) вызывал `drm_panel_add()` — панель сразу
  становилась видна DRM;
- `mipi_dsi_attach()` делался позже, в отдельном DSI-клиенте (в логе —
  `attached to host …` в 1.80 с);
- первый modeset (fbdev) идёт в 1.3–1.7 с, когда `dsi->refcount == 0`, и
  `mtk_dsi_bridge_atomic_enable()` **досрочно выходит**
  (`mtk_dsi.c`: `if (dsi->refcount == 0) return;`) — `mtk_dsi_start()` не
  вызывается, `DSI_START` остаётся 0, кадров нет.

Исправление: `mipi_dsi_attach()` выполняется в том же I2C-probe до
`drm_panel_add()` (отдельный DSI-клиент удалён). Образы: `boot_ubuntu15`
(с этим фиксом + отладочный дамп 0035) — **повесился**, поэтому 0035 откачен;
`boot_ubuntu16` (md5 `5290a67e…`) — только фикс порядка attach.

Грабли: отладочный дамп регистров `mmsys/ovl/rdma` (патч 0035) читает блоки,
которые могут быть выключены по power-domain, и вешает interconnect — такие
дампы надо ограничивать только DSI/PHY или читать при гарантированно
включённых блоках.

### 05.11: что говорят другие порты с этим кристаллом

Проверено по локальным референсам:
- **adomerle/mt6771-next (та же плата, mt8788-fplus-t1100)** — узел панели
  `panel@56` стоит со `status = "disabled"`; то есть их порт панель **никогда не
  включал**, и «взять как у них» нечего (наш драйвер — их же WIP, но у них он
  не работал end-to-end).
- **affenull (PennyOS, MT6771, Planet Cosmo)** — другая панель
  (`planet,cosmocom-x800-datong-panel`), прямой DSI без моста; для IT6112 не
  применимо.
- Веб-поиск по IT6112/mainline сейчас недоступен (HTTP 403 из окружения).

**Ключевое наблюдение по вендору.** В стоковой прошивке инициализацию моста и
панели делает **LK** (в его коде есть `lcm_init`, последовательность I2C/DSI,
per-panel конфиг по смещению `0x90ea8`), а вендорское ядро потом только
дописывает 9 регистров и гонит поток. У нас LK панель не поднимает (в нашем DTB
нет вендорских LCM-параметров), поэтому всё делает наш драйвер — и, судя по
всему, чего-то не хватает.

**Проверено на железе (kernel `ga6624bb1d219`+trace):** DSI реально стартует
(`T1100DSI: started, start=0x1, mode=0x1` = sync-pulse, `ps=0x312c0` = 1600×3,
`txrx=0x3c` = 4 линии), `poweron` вызывался дважды (refcount 0→1→2), мост видит
поток (`0x5e 0x21 bit3`), подсветка 100 %, DSV 5500 мВ — **экран чёрный**.

**Следующий эксперимент:** собрать образ, где наш драйвер **не трогает** мост
в `prepare()` (только DCS + enable), и посмотреть, не оживёт ли панель на
состоянии, которое мог оставить LK. Если нет — снимать TX-половину моста после
DCS и сверять с вендорским LK-состоянием, а при неудаче — идти в RE
(инициализация панели в LK, `0x5601ef24`).

## Итог сессии 05.11

**Работает (проверено на железе):**
- mainline 6.12 → Ubuntu 24.04 + systemd (`running`, графический target);
- eMMC HS400 (57.6 ГиБ, все разделы), RAM 3.5 ГБ;
- USB-RNDIS гаджет (`1d6b:0104`) + SSH по ключу (`10.42.66.66`), прошивка по
  SSH без recovery (`tools/host/flash-ssh.sh`);
- **зарядка** MT6370 (`online=1`, `Charging`, `vbus 4940 мВ`, `ibus 400 мА`);
- **выключение** (0034, вендорская последовательность MT6358: рельсы снимаются,
  DRAM обесточивается; возврат к жизни — штатный MTK «boot on charger»);
- KMS-стек: `mediatek-drm` собран, CRTC активен в вендорском режиме
  `1600x2176@60`, DSI стартует (`DSI_START=1`), мост IT6112 настроен как в LK.

**Не работает:** картинка на панели (экран чёрный). Публичного референса нет —
порт этой же платы (`refs/mt6771-next`) панель не включал. Подробности, отвергнутые
гипотезы и план — `docs/handover.md`.

**Патчи:** 0020 (форс device-сессии T-PHY), 0021–0026 (панель IT6112 + DSI0 +
MT6370 DSV + подсветка), 0027–0030 (STBY/EXT_PWR, замеры, TX-PLL, вендорские
тайминги), 0031–0032 (зарядник MT6370 + Type-C sink), 0033–0034 (выключение),
0035 (дамп MM-регистров) — **отключён** (`patches/wip-0035-*.disabled`), т.к.
чтение `mmsys/ovl/rdma` при выключенных power-domain вешает плату.

**Инфраструктура:** `tools/host/*` (recovery по telnet, прошивка по SSH,
настройка RNDIS через NetworkManager-профиль по USB-ID, `check-power`,
`diag-drm`, `vendor-it6112` — повтор вендорской последовательности на живом
мосте), `tools/lk/*` (извлечение DTB из boot.img, оффлайн-валидатор LK),
`tools/i2cpeek`, `tools/mempeek`, `tools/fbtest`. MCP `web-search` починен
(Brave через curl) и включён в проект.

## 05.11: страховка от разряда — `t1100-power-guard`

**Решение.** Повторные «пропажи» планшета — не зависание, а отрицательный
энергобаланс: от USB-порта ноутбука BC1.2 определяет SDP = 500 мА
(`input_current_limit`), работающая Ubuntu ест больше, а топливомера в mainline
нет — разряд не виден, пока плата не выключится по низкому напряжению. Введена
страховка, чтобы плата больше никогда не уходила в ноль:

- `rootfs-overlay/usr/local/sbin/t1100-power-guard` — раз в минуту читает `vbat`
  из IIO (канал с меткой `vbat`), пишет предупреждение ниже **3.65 В** (позже,
  06.11, поднято до 3.72 В) и гасит систему ниже **3.5 В** (позже — 3.6 В)
  после 3 замеров подряд (на зарядке — после 9: если
  напряжение не растёт при VBUS, значит зарядка не тянет). Выключение идёт
  штатным путём (патч 0034), в `/var/lib/t1100-power-guard/low-battery-poweroff`
  остаётся метка, и следующая загрузка объясняет в journal, почему плата погасла;
- `rootfs-overlay/etc/default/t1100-power-guard` — пороги, ток заряда, яркость;
- `t1100-power-guard.{service,timer}` — через 45 с после загрузки и далее раз в
  минуту;
- `tools/host/install-power-guard.sh [host|--rootfs DIR]` — установка по SSH или
  в примонтированный rootfs, без пересборки образа;
- `tools/host/watch-power.sh [host] [sec]` — живой монитор `vbat`/`ibus` с
  трендом: видно, положительный ли баланс.

Попутно страховка поднимает `constant_charge_current` до **2 А** (драйвер сам
ставит 900 мА workaround'ом, вендор ставил 2 А). `input_current_limit` (IAICR,
шаг 50 мА, диапазон 100 мА–3.25 А) по умолчанию **не трогаем** — его выставляет
BC1.2; для заведомо мощного порта есть `IAICR_UA` в `/etc/default`.
`BRIGHTNESS_PERCENT` (по умолчанию пусто) гасит подсветку: пока панель чёрная,
100 % подсветки — чистый расход.

**Проверено** на фейковом sysfs-дереве (`PS`/`IIO_ROOT`/`POWEROFF_CMD`):
пороги, счётчик, метка и её снятие, повышение ICHG/IAICR, подсветка;
`systemd-analyze verify` — только ожидаемое «ExecStart не найден» на хосте.
**На планшете ещё не установлено** — он был разряжен, доступа не было.

**Осознанно не закрыто:** автовыключение не спасает от MTK «boot on charger» —
после `poweroff` плата сама включается от VBUS и снова садится. Лечится только
дисциплиной (выдернуть кабель) или зарядкой из recovery / от 2 А зарядника.
Suspend по-прежнему замаскирован (RNDIS рвётся), так что в простое плата не
экономит — кандидат на работу в фазе 4.

### 06.11: recovery, заряд и установка страховки офлайн

Планшет подключён к ноутбуку в **Jolla Recovery** (`2931:0a06`), хост получил
`10.42.66.67/29` на `enx968289f9fbed` (udhcpd адрес не выдал — назначили руками),
дальше `tools/host/recovery.py` (telnet → меню 3 → shell).

Что показал вендорский стек в recovery (это единственный источник данных о
батарее — в mainline топливомера нет):

```
/sys/class/power_supply/battery:  CAPACITY=10  VOLTAGE_NOW=3693000
                                  CURRENT_NOW=-142600…+90000 (знак «плавает»)
                                  STATUS=Charging  TEMP=28.2  HEALTH=Good
/sys/class/power_supply/charger:  ONLINE=1     ADC_Charger_Voltage=4910 мВ
/sys/devices/platform/charger/:   input_current=-1, chg1/chg2_current=-1
                                  (вендорские лимиты в этой сборке не выставляются)
```

Выводы:
- **калибровка порогов**: 3.693 В = 10 % ⇒ 3.6 В на выключение — это ещё
  несколько процентов запаса, а не «в ноль». `VBAT_LOW_MV` поднят 3500 → **3600**,
  `VBAT_WARN_MV` 3650 → **3720**, `VBAT_OK_MV` 3900 → **4000**;
- от порта ноутбука (SDP 500 мА) в recovery в батарею доходит порядка 50–90 мА —
  сущие часы на процент, так заряжать нельзя; нужен зарядник 2 А;
- менять лимиты в recovery нечем: вендорские `input_current`/`chg*_current`
  в этой сборке отдают `-1` (не поддерживаются).

**Страховка установлена офлайн**, без загрузки Ubuntu: `p54` смонтирован в
recovery на `/mnt/ubuntu`, туда распакован `rootfs-overlay` (`tar` через
`recovery.py put`), права выставлены, создан симлинк
`timers.target.wants/t1100-power-guard.timer`, `sync`, `umount`. Проверено
чтением: `VBAT_LOW_MV=3600`, скрипт 176 строк, `-rwxr-xr-x`.
**Запуск на планшете ещё не проверен** — это первое, что надо сделать при
следующей загрузке Ubuntu (`systemctl list-timers t1100-power-guard.timer`,
`journalctl -t t1100-power-guard`).

#### 06.11 (2): от порта ноутбука батарея не заряжается вообще

Перезагрузка в recovery, тот же стенд. `dmesg` вендорского драйвера
(`mt6370_pmu_charger`) показывает причину, почему `CAPACITY` за час не сдвинулся
с 10 %:

```
mt6370_dump_register: ICHG = 500mA, AICR = 500mA, MIVR = 4200mV, IEOC = 250mA, CV = 4350mV
mt6370_dump_register: VSYS = 3700mV, VBAT = 3700mV, IBAT = 0mA, IBUS = 400mA, VBUS = 4925mV
CHG_EN = 1, CHG_STATUS = progress
```

То есть SDP-порт даёт 400 мА, и **все они уходят в систему, в батарею — 0 мА**
(`IBAT = 0`), `VSYS = VBAT` (система живёт от батареи). При этом `ICHG` в recovery
вендорский драйвер держит 500 мА.

Вывод: **заряжать от порта ноутбука бессмысленно в любом режиме** — нужен
адаптер с BC1.2 DCP ≥ 2 А. В recovery это проверить одной командой:
`dmesg | grep mt6370_dump_register | tail -1` — если `AICR` поднимется до
1.5–2 А, а `IBAT` станет положительным, зарядка пошла.

Заодно в `t1100-power-guard` добавлено предупреждение: при `online=1` и
`input_current_limit <= 600 мА` (SDP) юнит раз в 15 минут пишет в journal, что
баланс отрицательный и нужен зарядник 2 А — чтобы это не выяснялось задним
числом. Обновлённый скрипт (8132 Б) переустановлен в `p54` из recovery,
`sh -n` на самой плате — `rc=0`.

#### 06.11 (3): страховка проверена на железе end-to-end

После зарядки (2 ч от 2 А адаптера: `vbat` 3.697 → 4.12 В, gauge 10 → 82 %;
проценты явно нелинейны — ориентироваться на напряжение) — ребут из recovery в
Ubuntu, ядро `6.12.114-gfd5357d80a08`, `systemd is-system-running = running`.

```
systemctl list-timers t1100-power-guard.timer   → тикает раз в 60 с, LAST = +1 мин
systemctl show -p Result                        → success
journalctl -t t1100-power-guard:
  заряд: constant_charge_current 900000 -> 2000000 мкА
  слабый порт: input_current_limit=500000 мкА (SDP) — при работе Ubuntu баланс
  отрицательный, нужен зарядник 2 А
IIO vbat: raw=812 scale=5 → 4060 мВ (вендорский gauge в тот же момент 4.12 В —
          разница на падение под нагрузкой)
```

**Тест пути защиты.** Пороги подняты выше напряжения (`CONF=/dev/null
VBAT_LOW_MV=4200 SAMPLES=1`; на зарядке `need = SAMPLES*3`, поэтому три запуска):

```
разряд: vbat=4050 мВ < 4200 мВ, отсчёт 2/3 (online=1)
разряд: vbat=4050 мВ < 4200 мВ, отсчёт 3/3 (online=1)
КРИТИЧНО: выключаю плату, чтобы не разрядить батарею в ноль
Connection to 10.42.66.66 closed by remote host.
```

Признаки настоящего выключения, а не ребута: `uptime -p` = 0 минут, в журнале
прошлой загрузки `systemd-logind: System is powering down`, `/sys/fs/pstore`
**пуст**. Плата вернулась через ~15 с — это штатный MTK «boot on charger».
Метка `/var/lib/t1100-power-guard/low-battery-poweroff` создалась и снялась
автоматически на первом же запуске (vbat 4045 > 4000).

**Попутно исправлено:**
- каждая строка журнала дублировалась (stdout + `logger`) — `logger` убран, в
  юните `SyslogIdentifier=t1100-power-guard`;
- `CONF` в скрипте переопределяемый (`CONF=/dev/null` для тестов);
- `tools/host/install-power-guard.sh` без аргументов ставит на `10.42.66.66`
  (проверено — штатная установка по SSH работает).

## 06.11–07.11: **фаза 2 — панель заработала** (эксперимент A)

Гипотеза из handover подтвердилась: **рабочее состояние моста IT6112 оставляет LK**,
а ломает его наш init. Образ `build/boot_ubuntu19.img`
(sha256 `ec6316159571470095142c06e4b9058a102106aa6f7de15e8f96dbf2ae733620`),
в cmdline `t1100.it6112_skip_init=1`: драйвер не программирует мост (и не дёргает
его GPIO), только поднимает рельсы, стартует DSI и шлёт `exit sleep`/`display on`.
**На панели консоль и приглашение логина** — подтверждено владельцем и объективно:
дамп `/dev/fb0` содержит 3216 байт текста (`Ubuntu 24.04.3 LTS t1100 tty1`,
`t1100 login:`), подсветка 1023/1023, `card0-DSI-1` = `connected`,
`1600x2176`, `T1100DSI: started, start=0x1 mode=0x1 ps=0x312c0 txrx=0x3c`.

Артефакты: ядро `6.12.114-g6252c9f5fe1e`, `Image` sha256 `2aeaae37…`,
патч **0036** (коммит `7dc074437`, `patches/0036-…patch` в `series`),
подробности и дампы — `docs/it6112-experiment-a.md`, `refs/device/*expA*`,
`build/lk/lk_a.bin` (LK с p28, для RE DCS-таблицы панели), точка отката
`build/recovery/boot_a_before_expA.img`.

**Грабли, которые стоили итерации:** запросить `stby`/`ext-pwr` как
`GPIOD_OUT_LOW` — значит **снять EXT_PWR** (GPIO175) до чтения PID; мост
становится нулевым (`id 0x0000`, все регистры `0x00`). В этом режиме GPIO
берутся только `GPIOD_ASIS`, уровни печатаются:
`reset=1 stby=0 ext-pwr=1`.

**Расхождения с работающим состоянием LK (TX 0x56 / RX 0x5e):**

| регистр | LK (картинка) | наш init (чёрный) |
|---|---|---|
| TX `0x22` | `0x30` | `0x21` (наша формула из RE) |
| TX `0x24` | `0x01` | `0x00` |
| TX `0x26` | `0x01` | `0x00` |
| RX `0x11` | `0x01` | `0x02` («inverse MCLK», bit1) |

Остальные устойчивые регистры (`0x05`, `0x10/0x11/0x1f/0x21/0x23/0x25/0x27/0x3c`,
`0x44–0x47`, `0xb0`, `0xd0`, `0xd3`) совпадают побитно.

**Следующий шаг (фаза 2 добивается до конца):**
1. режим «нормальный init, но перечисленные записи не трогать» — маска в cmdline
   (например `t1100.it6112_keep=22,24,26,5e11`) → A/B только перепаковкой boot.img;
2. подтвердить картинку и бисектить по одной записи до локализации виновника;
3. `modetest` + `kmscube` на панели — в rootfs их нет, нужен кросс-бинарник
   (libdrm/GBM для aarch64) — только после этого критерий фазы 2 закрыт.

### 07.11: разбор LK и первый «нормальный» init — причина в `HOLD_TX`, но не только

Результат итерации: **гипотеза про четыре регистра не подтвердилась** (образ с
`keep=all` — не писать TX `0x22/0x24/0x26`, RX `0x11` — всё равно чёрный), зато
по дизассемблеру LK (`build/lk/lk_a.bin`, load `0x56000000`) найдено главное:

| адрес LK | что делает |
|---|---|
| `0x56031714` | отправитель DCS; **не шлёт пакет, пока взведён `HOLD_TX` (`TX 0x05` bit5)** |
| `0x5601ed9c` | TX init, начинается с импульса `0x05=0xfe` → `0x05=0x00` |
| `0x5601f140` | «TX on»: `0x05=0xfe` → `set_bits(0x06, 0x04)` → `0x05=0x00` |
| `0x560318a0` | **power-off** моста — ровно его наш драйвер повторял как `mipi_power_on()` |
| `0x560313f0` | RX init |

Отсюда понятно, почему эксперимент A дал картинку: наш драйвер снимал `HOLD_TX`
**после** DCS, то есть `exit sleep`/`display on` до панели не доходили вовсе.
Формулы LK (для будущего): TX `0x24`/`0x26` = 1 (`set_bits(reg, 0x0f, word>>8)`),
RX `0x11` — маска `0x01` (наш «inverse MCLK» bit1 — ошибка WIP), TX `0x22` =
`((K2*8 − 3q)/(2q)) + 20`, где `K2 = 125·(cfg[0x61]·(cfg[0x24]+4) + 0x91) = 38125`
(в первом порте терялось слагаемое `+145`); при частоте LK формула даёт ровно
`0x30`. DCS-таблица LK и наш формат пакета (`0x73=05,cmd,00,ecc`, `0x74=0x44`,
`0x75=0x87`) совпадают побайтно.

Патч **0037** (`a0fd31f9f`, `patches/0037-…patch`): порядок как в LK
(снятие `HOLD_TX` до DCS), значения `0x24/0x26`, RX `0x11` бит0, формула `0x22`
с `+145`, полный дамп регистров `0x00..0x6f`, `0x78..0xff`.

**Но образ с этими правками (`boot_ubuntu21`) всё ещё чёрный** ⇒ есть минимум
одно добавочное расхождение. Что известно: после нашего init `TX 0x06 = 0x04`
против `0x00` в рабочем состоянии LK; `0x22 = 0x2f` против `0x30` (ожидаемо
из-за другой частоты 188 МГц). Полный дамп уже вшит в образы 22/23/24, но снять
его не успели — планшет ушёл на зарядку.

| образ | что в нём | экран | sha256 |
|---|---|---|---|
| `boot_ubuntu20` | `keep=all`, hold не снимался | чёрный | `46ae92d7…002f93` |
| `boot_ubuntu21` | hold до DCS + фиксы 0037 | чёрный | `691a3312…592634d` |
| `boot_ubuntu22` | 0037 + полный дамп (**сейчас на плате**) | чёрный | `afe335b2…eaf1432` |
| `boot_ubuntu24` | `skip_init=1` + 0037 + дамп — **вернуть картинку** | — | `6df4ab28…1ce903` |

**Первое действие следующей сессии:** прошить `build/boot_ubuntu24.img`
(`skip_init=1`) и вернуть владельцу картинку; затем (а) на рабочем состоянии
проверить одной записью `i2cpeek -w 3 0x56 0x06 0x04` — гипотеза «виноват
`TX 0x06` bit2»; (б) снять полный дамп в двух прогонах (`skip_init=1` и
нормальный init) и сделать дифф по всей карте; (в) если дифф чистый — проверить
гипотезу «мост не переживает наш power-cycle/reset в `probe`»: маска, где
`probe` не трогает рельсы/reset, а полный init делает `prepare()`.

## 09.11: тяжёлые вычисления перенесены на build-хост

**Решение.** Компиляция ядра и прочие тяжёлые задачи больше **не выполняются на
локальной машине**. Причина: T480 (4 ядра) постоянно занят другими проектами
(postоронние `make verify`, cargo, Chrome), load average стоял 17–39; полная
сборка ядра 06.11 заняла ~4 часа и мешала остальной работе.

| | |
|---|---|
| хост | `172.17.141.172` (Ubuntu 26.04, 12 ядер, 15 ГБ RAM, load ~0.6) |
| доступ | `l` / пароль `0`, `sudo` — тот же пароль |
| тулчейн | доустановлено: `gcc-aarch64-linux-gnu`, `bison`, `flex`, `libelf-dev`, `libssl-dev`, `rsync` |

Реализация: `scripts/build-kernel-remote.sh` (rsync дерева без `.git` →
defconfig + `configs/t1100.fragment` → `make -j$(nproc) Image dtbs` → артефакты в
`build/remote/`), инкрементальные сборки сохраняются в `/home/l/t1100-ubuntu-build`.
Правило зафиксировано в `AGENTS.md` (раздел «Сборка и тяжёлые вычисления»),
локально остаются ssh/recovery/git/документация/перепаковка boot.img.

**Первый прогон (09.11), факты:**
- полная сборка с нуля, включая rsync дерева 1.9 ГБ: **8 мин 22 с** (лог
  `build/logs/build-remote-20261109-192109.log`) против ~4 ч локально;
- `Image` 39 870 976 Б, sha256 `da7c3023…556927`, артефакт в `build/remote/`;
- `.config` совпал с локальной сборкой (`build/k1/.config`) **кроме двух
  проб хоста** `CONFIG_CC_CAN_LINK`/`CC_CAN_LINK_STATIC` (4344 против 4346
  символов) — то есть конфиг воспроизводится;
- поправка: `.git` на хост не копируется, поэтому версия ядра была бы просто
  `6.12.114`; в скрипт добавлен `LOCALVERSION=-g<sha10>[-dirty]`, как в локальной
  сборке (`kernelrelease` проверен на хосте).

### 09.11: на плату прошит `boot_ubuntu24` (картинка возвращена)

Из recovery (`tools/host/recovery.py`, RNDIS поверх USB) записан
`build/boot_ubuntu24.img` (`t1100.it6112_skip_init=1`):

- бэкап текущего `boot_a` снят потоком в хост: `build/recovery/boot_a_before_ubuntu24.img`,
  sha256 `afe335b2ba4f65dd60cf3579bbcfc1d0923ac0ff55937943131f2c323eaf1432` —
  **побайтно совпал** с `build/boot_ubuntu22.img`, то есть на плате был ровно
  предыдущий экспериментальный образ;
- запись `dd of=/dev/mmcblk0p29`: 33 554 432 Б за 1.1 с (28.9 МБ/с);
- контрольное чтение с раздела: sha256
  `6df4ab28b36cffafdaf3572248e837cf1ae0e465556d84038902f87f111ce903` — совпало
  с локальным файлом.

Батарея на момент прошивки: 27 %, 3.803 В (на порту ноутбука `IBAT ≈ 26 мА`,
`chr_type=1` SDP — почти не заряжается; от 2 А адаптера было `chr_type=4` DCP
и заряд шёл: 9 % → 27 %, 3.695 → 3.803 В).

## 10.11: фаза 2 — панель работает на **дефолтном** пути драйвера

Виновник чёрного экрана найден и устранён: наш драйвер писал **`TX 0x06` bit2**
в «TX on». Проверено на живом мосте при работающей панели:
`i2cpeek -w 3 0x56 0x06 0x04` → **чёрный экран с включённой подсветкой** (владелец),
`0x06 0x00` → картинка вернулась. В рабочем состоянии LK `TX 0x06 = 0x00`.

**Почему LK этот бит не портит (RE, `build/lk/lk_a.bin`):** функция `0x5601f124`
(«TX on», внутри неё `set_bits(0x06,0x04,0x04)`) **на пути загрузки не вызывается** —
линейный проход capstone по всем 8 МиБ не нашёл ни одного `bl`/`blx` на её вход,
32-битного указателя на `0x5601f125` в образе тоже нет (контроль метода: вызов
`0x5601efe4` внутри той же функции находится). То есть «LK ставит bit2» было
неверным чтением: запись лежит в неиспользуемой ветке.

Патч **0038** (`136880fe5`, `patches/0038-…patch`):
- `TX 0x06` не пишется вообще (импульс `0x05=0xfe` → `0x05=0x00` сохранён);
- запись `0x05` bit0 оставлена, но «тихая»: чип **всегда** NAK-ает этот байт
  (воспроизведено из userspace на рабочем мосте: `0xfe`/`0x00` проходят,
  `0x01` → `-ENXIO`), это свойство чипа, а не шины;
- для остальных записей — ретрай транзиентных `-ENXIO/-EIO` (3 попытки);
- маска `t1100.it6112_keep=` сохранена как инструмент бисекта.

**Финальный образ `build/boot_ubuntu27.img`** (sha256 `a89b264d…8283`), cmdline
**без** `skip_init`:

```
dmesg: IT6112 bridge found … skip-init 0, keep 0x0
       bridge initialised
       T1100DSI: started, start=0x1 mode=0x1 ps=0x312c0 txrx=0x3c
       TX clk: MCLK=188230 kHz -> 0x22=0x2f 0x1f=0x0b
drm:   card0-DSI-1 connected/enabled 1600x2176, подсветка 1023/1023
fb0:   3216 непустых байт = консоль + `t1100 login:` (владелец видит приглашение)
TX:    06=00 22=2f 24=01 26=01   ошибок I2C в dmesg — 0
```

Эталонные дампы для будущих сравнений: `refs/device/it6112-regs-exp38-default-path.txt.gz`,
`dmesg-exp38-default-path.txt.gz`, `fb0-exp38-default-path.png`.

**До закрытия фазы 2 осталось:** `modetest` (нужен только libdrm — собрать
кросс-компилятором на build-хосте и запустить). `kmscube` требует GBM/EGL, то
есть **работающего GPU** — переносим в фазу 3 (panfrost), иначе критерий
«modetest + kmscube» недостижим по порядку.

**Мелочь на будущее:** `0x22 = 0x2f` (наша частота 188 МГц) против `0x30` у LK
(197 МГц) — оба варианта дают картинку; если появятся артефакты, есть маска
`keep=tx22` для сравнения.

### 10.11: userspace-инструменты под aarch64 на build-хосте

На планшете нет ни apt-сети, ни `libdrm`, поэтому KMS-утилиты собираются
кросс-компилятором на build-хосте и заливаются по SSH:

- `scripts/build-tools-aarch64.sh` — libdrm `2.4.131` через meson cross-file,
  `-Ddefault_library=static -Dc_args=-static`, цель `modetest`;
  результат — `build/tools-aarch64/modetest` (ELF aarch64, **статический**,
  1 080 384 Б, sha256 `ca1f1787…8d0330`);
- `tools/host/kms-test.sh` — заливает бинарник, снимает `modetest -c/-p/-e`,
  находит connector `DSI-1` и выставляет его режим (`--dump` — только отчёт,
  `--hold N` — держать режим N секунд);
- `kmscube` **не собирается**: нужен GBM/EGL/GLESv2, то есть Mesa под aarch64 и
  работающий panfrost — это фаза 3 (в скрипте оставлено место под неё);
- на build-хосте включён `ccache` для сборок ядра (masquerade `~/.ccache-bin` +
  `CCACHE_DIR=~/.ccache-t1100`); вариант с префиксом `ccache` в переменной CC
  не работает — kbuild/ccache отвечают «unknown C compiler».

### 10.11 (2): кросс-инфраструктура для фазы 3 и подготовленный panfrost-образ

**Инфраструктура на build-хосте** (подробности — новый `docs/cross-build.md`):
`meson`, `ninja`, `ccache`, `debootstrap`, `qemu-user`; для ядра включён кэш
(`~/.ccache-bin` + `CCACHE_DIR=~/.ccache-t1100`) — на второй сборке 204 из 365
кэшируемых вызовов, **58 % попаданий**. Планшет при этом не трогали.

**arm64-sysroot** `/home/l/t1100-sysroot` (Ubuntu noble = 24.04, как на планшете):
`debootstrap --arch=arm64 --variant=minbase` + dev-пакеты. Важный нюанс: второй
этап debootstrap в chroot требует `qemu-user` (в apt он называется `qemu-user`,
а не `qemu-user-static`), и даже с ним падает на `/debootstrap/mirror`; рабочий
путь — `dpkg --add-architecture arm64` + источник `ports.ubuntu.com` с
`Architectures: arm64`, затем `apt-get download <pkg>:arm64` и `dpkg -x` в
sysroot. Sysroot нужен для Mesa/EGL в фазе 3 (заголовки и `.so`), запускать
arm64-бинари в нём не требуется.

**Фаза 3 подготовлена, но НЕ прошита** (`gpu-mesa`, патч **0039**, коммит
`eed4580b9`): `&gpu status = "okay"`, узлы `mfg`/`mfg_async` не нужны (в mainline
их нет — MFG это 5 power-domain'ов в `spm`), `sram-supply` убран по биндингу
`mt8183b-mali`, а **DVFS выключен намеренно**: OPP-таблица уронила бы VGPU до
625 мВ при VSRAM 1000 мВ, тогда как вендор держит пару с разницей ровно 100 мВ.
Образ `build/boot_ubuntu28.img` (sha256 `0ae1c4b5…12f8`), `verify-dtb` passed,
`docs/panfrost-plan.md` — разбор узлов, рисков и проверок.

**Единственный опасный сценарий** (из плана): если гейт `mfg_bg3d` на MT6771
просыпается не тем битом, обращение к `0x13040000` даст зависание AXI без лога;
всё остальное — чистый отказ probe (`-517`/`-110`), дисплей не затрагивается
(MFG и DISP — разные домены, у GPU нет larb/SMI). Откат: recovery → `dd`
`boot_ubuntu27.img` (sha256 `a89b264d…8283`) в `mmcblk0p29`.

**Порядок работ:** сначала закрыть фазу 2 (`tools/host/kms-test.sh` + `modetest`
на планшете), потом прошивать `boot_ubuntu28` — чтобы не менять два фактора
одновременно.

## 10.11 (3): **фаза 2 закрыта по KMS**, GPU (panfrost) поднялся

**`modetest` на панели** (`build/tools-aarch64/modetest`, статический):

```
Connectors:
id  encoder status     name   size (mm) modes encoders
33  32      connected  DSI-1  166x226   1     32
  #0 1600x2176 60.00 … 248356 kHz flags: preferred, driver
setting mode 1600x2176-60.00Hz on connectors 33, crtc 64
rc=0;  /sys/class/drm/card0-DSI-1 = connected/enabled
```

**Решение по критерию фазы 2.** «`modetest` + `kmscube`» разделён: `modetest`
(чистый KMS, libdrm) — **выполнен**; `kmscube` требует GBM/EGL/GLESv2, то есть
Mesa под aarch64, и физически относится к GPU-фазе. Перенесён в фазу 3
(зафиксировано в `docs/porting-plan.md`).

**GPU включён** (патч 0039, образ `build/boot_ubuntu28.img`,
sha256 `0ae1c4b5…12f8`, бэкап предыдущего `boot_a` —
`build/recovery/boot_a_ubuntu27.img`, sha256 `a89b264d…8283`). Ядро
`6.12.114-geed4580b9b`, загрузилось без зависаний:

```
panfrost 13040000.gpu: clock rate = 511999970
panfrost 13040000.gpu: mali-g72 id 0x6221 major 0x0 minor 0x3 status 0x0
panfrost 13040000.gpu: shader_present=0x7 l2_present=0x1
[drm] Initialized panfrost 1.2.0 for 13040000.gpu on minor 0
/dev/dri/: card0 (panfrost), card1 (mediatek-drm), renderD128
```

Ошибок MMU/`job timeout` нет, дисплей не пострадал (`card1-DSI-1` connected,
`fb0` 3216 Б), `vbat` 4.26 В. DVFS по-прежнему выключен: 512 МГц от LK,
VGPU 900 мВ / VSRAM 1000 мВ — как у вендора.

**Следующий шаг — фаза 3, userspace:** собрать Mesa (GBM/EGL/GLESv2) под aarch64
на build-хосте через `docs/cross-build.md` (sysroot `/home/l/t1100-sysroot`),
положить в rootfs планшета и прогнать `kmscube`/`es2gears`/`glmark2-es2`.

## 10.11 (4): **GLES через panfrost работает; `kmscube` на панели**

Mesa собрана на build-хосте под aarch64 через noble-sysroot (детали и грабли —
`docs/mesa-cross.md`, скрипты `scripts/build-mesa-aarch64.sh` +
`scripts/remote/build-mesa-aarch64.sh`, деплой/тесты `tools/host/mesa-test.sh`):

- **Mesa 25.0.7** (25.1+ требует LLVM ради panfrost-CLC — не годится для кросс-сборки),
  gallium `panfrost`, `Platforms: surfaceless drm`, GBM/EGL/GLES2 — да;
- `kmsro` в `-Dgallium-drivers` не передаётся (это winsys, включается сам);
  в Mesa 25 нет `*_dri.so`: `libEGL`/`libGLESv2` линкуются с `libgallium-25.0.7.so`,
  GBM грузит `gbm/dri_gbm.so` → нужен `GBM_BACKENDS_PATH`;
- залито в `/usr/local` (rootfs не тронут), обёртка `/usr/local/bin/mesa-env.sh`.

Проверено на железе (ядро `6.12.114-geed4580b9b`), лид перепроверил лично:

```
egl-probe /dev/dri/renderD128:
  GL_RENDERER: Mali-G72 (Panfrost)      GL_VERSION: OpenGL ES 3.1 Mesa 25.0.7
  RESULT: render OK
kmscube -D /dev/dri/card1:  Rendered 226 frames in 4.005 sec (56.4 fps)
dmesg: 0 совпадений "mmu fault|job timeout|gpu fault"
панель: куб виден (подтверждено владельцем), после прогона консоль вернулась
```

**Значит критерий фазы 2 («`modetest` + `kmscube` на панели») выполнен полностью**,
а фаза 3 закрыта по функциональности GLES (осталось: числовой бенчмарк
`glmark2-es2-drm`, решение по DVFS GPU и Wayland-композитор).

### 10.11 (5): `glmark2` на panfrost — критерий фазы 3 по бенчмарку выполнен

`glmark2 2023.01`, flavor `drm-glesv2` (`-b :drm-device=/dev/dri/card1:duration=10`,
4 сцены × 10 с), залит в `/usr/local` (rootfs не тронут):

```
GL_RENDERER : Mali-G72 (Panfrost)      GL_VERSION: OpenGL ES 3.1 Mesa 25.0.7
[build]   FPS 534   [texture] FPS 437   [shading] FPS 430   [effect2d] FPS 414
glmark2 Score: 452
dmesg: 0 × "mmu fault|job timeout|gpu fault";  панель вернулась к консоли;
vbat 4.21 В
```

Оговорка к числам: в DRM-flavor `SwapInterval(0)`, `DRM_CAP_ASYNC_PAGE_FLIP` не
поддерживается → 400–530 fps это скорость отрисовки без vsync; `kmscube` даёт
56.4 fps именно потому, что ждёт flip. Сравнивать score только с теми же
параметрами и разрешением (3.5 Мпикс).

Сборка: `scripts/build-glmark2-aarch64.sh` + `scripts/remote/build-glmark2-aarch64.sh`,
cross-file `tools/cross-aarch64-glmark2.txt`; грабли (C++ и `-isystem` на C-заголовки
sysroot, `-lm` из хоста вместо sysroot, `pkg_config_libdir` с `$prefix/lib/pkgconfig`
для `egl.pc`/`gbm.pc` Mesa 25) — в `docs/mesa-cross.md`.
Артефакты: `build/glmark2-aarch64/`, лог `refs/device/glmark2-run-20261110.txt.gz`.

**Организационная грабля (записана в `AGENTS.md`):** параллельные исполнители на
одном планшете конфликтуют за DRM master — прогон `glmark2` сначала получил
`Failed to become DRM master`, а висевший `kmscube` был снят агентом. Устройство —
эксклюзивный ресурс: один прогон в единицу времени.

## 10.11 (6): фаза 4 начата — **Weston работает на панели**

Первый Wayland-композитор на этой плате. Собран на build-хосте кроссом и залит в
`/usr/local` (rootfs, `boot_a`, ядро/DTB не тронуты):

- Weston **13.0.0**, `--backend=drm --drm-device=card1 --shell=kiosk`,
  `LIBSEAT_BACKEND=builtin` (в Weston 13 нет `--tty`; seat открывается libseat'ом
  напрямую, logind/seatd/VT не нужны), `--drm-device=card1` обязателен — иначе
  drm-backend по udev берёт `card0` (panfrost), который не умеет modeset;
- стек: wayland 1.22.0, wayland-protocols 1.45, libxkbcommon 1.6.0, libinput
  1.25.0 (+libevdev/libmtdev/libwacom), pixman 0.42.2, libseat 0.8.0,
  libdisplay-info 0.1.1, Mesa 25.0.7 из фазы 3;
- сборка: `scripts/build-weston-aarch64.sh` (+ `scripts/remote/…`, cross-file
  `tools/cross-aarch64-weston.txt`), деплой/тесты `tools/host/weston-test.sh`
  (`verify|deploy|check|smoke|run|stop|log|undeploy`), план — `docs/wayland-plan.md`.

**Факты с железа** (`/tmp/weston-live.log`):

```
DRM: supports atomic modesetting
DRM: head 'DSI-1' found, connector 33 is connected
Output 'DSI-1' … 1600x2176@60.0, preferred, current, 248.4 MHz
Output 'DSI-1' enabled with head(s) DSI-1; волокно kiosk-shell.so загружено
EGL client APIs: OpenGL, OpenGL_ES; surfaceless context: yes
```

Клиент `weston-simple-shm` подключён, **владелец видит движущийся квадрат на
панели** — композирование и KMS работают end-to-end.

**Ограничение, найденное сразу:** EGL-клиенты Wayland не работают —
`weston-simple-egl` падает на `init_egl: Assertion 'ret && n >= 1' failed`,
потому что Mesa собрана с `-Dplatforms=` (только surfaceless+drm), без
wayland-платформы EGL. Пересборка Mesa с `-Dplatforms=wayland` запущена
(`gpu-mesa`); до неё любой EGL/Wayland (KWin, GTK4, Qt) заблокирован.

**Попутно исправлено в `tools/host/weston-test.sh`:** `pkill -f
'/usr/local/bin/weston '` убивал сам remote-shell (его командная строка содержит
эту строку) → `pkill -x weston`; клиенту не передавался `WAYLAND_DISPLAY`.

### 10.11 (7): Wayland-платформа EGL работает — треугольник 56.4 fps

Mesa 25.0.7 пересобрана с `-Dplatforms=wayland` (в этой опции meson допустимы
только `auto|wayland|x11|…`; `drm`/`surfaceless` добавляются сами при наличии
libdrm — поэтому прежняя попытка `-Dplatforms=` их и оставила, но убила
wayland). В `libEGL` появились `dri2_initialize_wayland`, `wayland_drm`,
`EGL_EXT_platform_wayland`; у `kmscube`/`glmark2` SONAME не изменились.

После заливки (`libEGL` sha256 `d22d05d3…`, старый бандл сохранён в
`build/mesa-aarch64-noplatforms/`):

```
egl-probe /dev/dri/renderD128 → Mali-G72 (Panfrost), GLES 3.1, render OK
weston (kiosk, card1, atomic) + weston-simple-egl:
  has EGL_EXT_buffer_age and EGL_EXT_swap_buffers_with_damage
  282 frames in 5 seconds: 56.40 fps
  283 frames in 5 seconds: 56.60 fps
```

Владелец подтвердил: **вращающийся треугольник на панели**. dmesg чистый
(0 × `mmu fault|job timeout|gpu fault`), `vbat` 4.16 В.

Мелочи из лога Weston (не критично): `Failed to obtain a high priority context`,
`/usr/share/libinput` data files отсутствуют (в bundle нет `libinput-data` —
учесть при настройке тача).

**Фаза 4 по композитору закрыта:** Weston 13 + EGL/GLES через panfrost, kmsro,
atomic KMS. Дальше — ввод (тач), десктоп (KDE Plasma/GNOME) и DVFS GPU.
## 10.11 (8): Wi-Fi/BT — статус; аудит rootfs и userspace

**Wi-Fi/BT не начаты** (фаза 5). Факты, собранные при разборе:

- combo **CONSYS_6771 = MT6630/MT6631**; в стоковом DTS — `wifi@180f0000`
  (`mediatek,wifi`, IRQ 290/118, клок `wifi-dma`), питание — LDO MT6358
  `vcn33_wifi`/`vcn33_bt`; это не SDIO (у `msdc0` `no-sdio`, `msdc1` — карта);
- Wi-Fi — вендорский `wlan_drv_gen3` через WMT/CONNSYS, BT — HCI UART H4 через
  тот же WMT; прошивки — `/vendor/firmware` (`WIFI_RAM_CODE_6759`,
  `WMT_SOC.cfg`, `soc3_0_ram_*.bin`), в Ubuntu-rootfs их нет;
- в mainline 6.12 **нет ни драйвера, ни DTS-узлов**; `mt76` MT6631 не
  покрывает; USB-донгл требует host/OTG, которого сейчас нет (`dr_mode =
  "peripheral"`, `tcpc` отключён). Сеть — только RNDIS;
- в конфиге ядра `CONFIG_BT=m`, `CONFIG_CFG80211=m`, `CONFIG_MAC80211=m`, а
  модули в образ не ставятся — беспроводного стека нет и теоретически.

**Аудит rootfs** (по докам и последним загрузкам): p54 — ext4, метка `ubuntu`,
Ubuntu 24.04.3 LTS + systemd + sshd (root по ключу) + `t1100-power-guard`;
~587 МБ занято (03.11), LVM `sailfish` снесён 31.10. В rootfs нет `libdrm`/
`modetest` (modetest заливается статически с build-хоста), `/lib/firmware` и
модулей ядра. Локального `build/rootfs/*.tar.gz` сейчас нет — живая копия на
p54 единственная.

**Userspace сверх rootfs, всё в `/usr/local`** (rootfs, `boot_a`, ядро/DTB не
трогались): Mesa 25.0.7 (GBM/EGL/GLES2/GLES3 + wayland-платформа),
`mesa-env.sh`, `kmscube`, `glmark2`, Weston 13 с бэкендом DRM/atomic. Это
закрыло фазы 2 (KMS) и 3 (GLES): `kmscube` 56.4 fps, `glmark2` Score 452,
Weston + `weston-simple-egl` 56.4 fps на панели (см. 10.11 (3)–(7)).

Документация синхронизирована: `hardware.md` (p54/ext4, Wi-Fi/BT),
`handover.md` (0039 прошит, порог 3.6 В, rootfs-артефакт), `porting-plan.md`,
`ubuntu-rootfs-plan.md`, `README.md`, `AGENTS.md`, `provenance.md`.

**Дальше:** ввод (тач Himax, evdev/libinput), десктоп KDE Plasma/GNOME, решение
по DVFS GPU; Wi-Fi/BT — отдельная фаза 5, v1 не блокирует.


### 10.11 (9): тач — контроллер отвечает, но кадров не отдаёт (нужен RE)

Что сделано и проверено на железе (`bringup`, коммиты `77b948c59`/`344214877`,
патчи 0040/0041, образ `build/boot_ubuntu33.img` sha256 `64864160…`):

- чип **HX83102E** доказан чтением AHB `0x900000d0` = `00 2e 10 83` (id 0x83102e),
  совпадает с вендорским патчем `refs/mt6771-next/patches/0f649f913f` и логом стока;
- **найдена и исправлена обвязка питания**: ключ `ts-avdd` (GPIO163) никто не
  драйвил (pin был input bias pull-down) — аналоговое питание дигитайзера было
  закрыто. Добавлен `regulator-fixed touch_avdd` (GPIO163 ← VLDO28 1.8 В),
  питание поднимается **до** сброса; после фикса `0x900000a8 = 0x05`
  (вендор трактует как «FW reload done»);
- драйвер `CONFIG_TOUCHSCREEN_HIMAX_HX83112B=y`, устройство привязано,
  `Himax Touchscreen` = `/dev/input/event1`, capabilities на месте.

**Но событий нет:** `cat /dev/input/event1` при реальных касаниях — 0 байт;
в dmesg каждые ~1.3 с `Wrong event checksum: 33a0`. Сырые дампы (56 байт из
AHB `0x30`, до проверки checksum): покой — `00`×56, по IRQ — `ec`×56 (сумма
`0x33a0`), редкие окна — `00`×20 `01` `ff`×35. Альтернативный AHB `0x90060000`
(путь `hx83100a`) даёт только фиктивные `0xbb`. Скан блока 0x10…0x98: меняются
только `0x30`/`0x38`, а «живые» поля при касаниях видны в `0x3a…0x3e`.
IRQ `mt-eint 1` тикает ~1/с независимо от пальца (215→267 за 60 с без касаний),
т.е. EINT1 сейчас не отражает касания (pin 1 без bias — вероятно нужен pull-up).

**Вывод:** `struct himax_event` (56 байт с `0x30`) к HX83102E в таком виде не
применим, и «починить смещением» нельзя — данных кадра в этом окне нет. Вендор
перед sensing делает handshake (`sense_off 0xA5/0x87 → flash check →
reload_disable → sense_on`) и сам включает INT; в mainline-драйвере этого нет.
Нужен разбор стокового `himax_common`: последовательность инициализации, адрес и
layout блока отчёта, конфигурация INT — задача для `reverse-engineer`.

**Инструмент для интерактивных проверок:** `tools/host/screen-msg.sh`
(`--touch`, `--read N`, `--clear`, `--stop-drm`) — выводит сообщение на панель
через `/dev/tty1` перед тем, как ждать действий владельца. Важно: **кириллица в
консольном шрифте планшета не рисуется** (нет kbd/setfont и Unicode-шрифта) —
сообщения пишем латиницей; консольный loglevel при этом гасим `dmesg -n 1`,
иначе kernel-спам смывает сообщение.

### 10.11 (10): RE протокола тача — причина найдена

Разбор стокового ядра 4.14 (`../t1100/backup_5.1.6.110/boot_a_5.1.6.110.img`,
capstone; символика из kallsyms-таблиц образа) — полный документ
`docs/touch-hx83102e.md` (`f586048`). Три причины, почему наш драйвер не видел
кадров:

1. **Не тот адрес.** Вендор (`@0xA95DAC`) делает `write(0x11, 0x00)` и затем
   **burst-чтение регистра `0x30` восьмибитного пространства**;
   наш `regmap_raw_read(0x30, 56)` отправляет 4-байтный адрес `30 00 00 00`,
   то есть читает AHB `0x00000030` — отсюда `0x00`/`0xEC`-заполнитель.
2. **Нет burst-режима**: нужны `0x13 = 0x31`, `0x0D = 0x10`.
3. **Другая контрольная сумма**: у вендора 16-битная сумма по байтам **до
   первого `0x00`**, а не сумма всех 56 байт. Сам размер кадра совпадает:
   `4*(HX_MAX_PT + hx_raw_cnt_max) + 8 = 56` («protocol type B»).

Дополнительно из RE: последовательность init (`sense_off 0xA5` → поллинг
`0x900000A8 == 0x05` → подтверждение `0x87`, магия `0x10007F40 = 0x07EAFBEF`,
wait-FW-reload, `int_enable(1)`), INT — **falling edge**, `mt-eint 1` в стоке тоже
тикает сам (не признак касаний) — нужно проверить bias пина.

Реализация вендорского пути чтения кадра — в работе у `bringup` (образ 0042).

### 10.11: итог сессии (планшет ушёл на зарядку в recovery)

Закрыто за сессию: **фаза 2** (панель + `modetest` + `kmscube`), **фаза 3**
(panfrost, GLES 3.1, `glmark2` Score 452), **startup фазы 4** (Mesa с
wayland-платформой, Weston 13 → kiosk + SHM/EGL-клиенты, 56.4 fps), плюс
инфраструктура (build-хост 12 ядер, ccache, arm64-sysroot, статические
`modetest`/`glmark2`, `egl-probe`) и `t1100-power-guard`.

Осталось: **тач HX83102E** (причина найдена RE, реализация вендорского пути
чтения кадра — в работе, `docs/touch-hx83102e.md` §7), затем libinput/десктоп,
DVFS GPU, Wi-Fi/BT (фаза 5).

Состояние платы и порядок работ — `docs/handover.md`, раздел «Где остановились».

### 10.11 (11): попытка §7 — планшет подвис; запись в AHB `0x5C` не подтверждена

Эксперимент по `docs/touch-hx83102e.md` §7 на живой плате (`bringup`):

```
write 0x13=0x31, 0x0D=0x10 (burst on), write 0x11=0x00
read  reg 0x30 (56 Б)  -> 56 × 0x00
read  AHB 0x90000030   -> нули
read  reg 0x38 (8 Б)   -> нули
```

То есть кадра нет ни по вендорскому, ни по нашему адресу; при этом чип жив:
ICID `0x900000D0` = `83 10 2E`, `0x900000A8` = `0x05` (FW reload done),
heartbeat в `0x38…0x3F` (`0x3C` инкрементится, `0x3F` мигает `ff/80`),
а `0x9000005C` (sense_off) всегда `0x00` — `0x87` не приходит.

Попытка записать AHB `0x9000005C = 0xA5` последовательностью
`0x00=адрес(4Б) → 0x0C=0x1 → 0x08=0xA5` изменила `0x900000A8` (`05 → 00`), но
подтверждения `0x87` не дала — **эта AHB-запись не подтверждена** (вероятно,
данные пишутся через суб-адрес `0x00`, а не `0x08`). После серии чтений
`0x11=0 → reg 0x30` планшет перестал отвечать (SSH/ping пропали, перезагрузки
не было, `panic=10` не сработал) — похоже на livelock (шторм EINT1/зависшая
I2C-транзакция), а не панику. **Нужен физический power-cycle.**

**Грабли (записать в память):** `unbind` драйвера тача **снимает AVDD** —
линию GPIO163 держит `regulator-fixed touch_avdd`, а не драйвер; при отвязанном
драйвере регулятор выключается и *все* чтения чипа дают `0x00` (на это уже
наступили). Эксперименты с чипом вести только с привязанным драйвером или с
`regulator-always-on`.

**Безопасная последовательность после подъёма** (без записей в AHB вообще):
`0x13=0x31`, `0x0D=0x10`, `0x11=0x00` → чтение регистра `0x30` 56 Б в цикле
~20 Гц 5–10 с, печатать только изменения (`tools/evdump/hxwin.py`). Если кадр
появится — фиксировать раскладку по касаниям (1600×2176) и делать `read_events`
для `hx83102e`; если нет — добирать `sense_on` из дизасма, а не угадывать.

## 11.11: тач передан второму разработчику; следующая задача — **Wi-Fi (фаза 5)**

**Тач: где остановились** (передано, дальше ведёт второй разработчик).
Сделано и проверено: `sense_on` (патч 0043), точный AHB-протокол (`hxahb.py`),
чтение кадра burst'ом регистра `0x30`, INT по falling edge (0044), образ
`build/boot_ubuntu34.img` (sha256 `ab214a26…3435`).
Факт с железа: чип в save-режиме молчит совсем, после `sense_on` кадры идут
по прерыванию — но **все 56 байт одинаковы** (`14 × 00 03 00 00`, `sum=0x2a`),
точек нет ни при тапах, ни при удержании. Следующие шаги для второго
разработчика (в порядке приоритета):
1) добить оставшуюся инициализацию из `docs/touch-hx83102e.md` §2.2 —
   `AHB 0x10007f04 = 0` (sorting mode), `reload_disable`, `reg_re_init`/`func_re_init`;
2) `touch_avdd` → `regulator-always-on` (иначе `unbind` драйвера снимает AVDD и
   все чтения чипа дают `0x00` — проверенная ловушка);
3) pinctrl GPIO1 (EINT1) — сейчас `input bias disabled`, сток ставит pull-up.

**Новая задача лида: Wi-Fi/BT (фаза 5).** Что известно из документов:
combo **MT6630/MT6631** (CONNSYS), стоковый узел `wifi@180f0000` (IRQ 290/118,
клок `wifi-dma`), питание LDO `vcn33_wifi`/`vcn33_bt`; драйвер вендорский
`wlan_drv_gen3` (out-of-tree, 4.14), прошивки в `/vendor/firmware`
(`WIFI_RAM_CODE_6759`, `WMT_SOC.cfg`, `soc3_0_ram_*.bin`); в mainline драйвера
для MT6630/6631 нет (проверено поиском по дереву). Отсюда задача —
идентифицировать чип/шину по фактам и выбрать путь (порт вендорского или
mainline-аналог), прежде чем что-то писать в железо.

### 11.11: поворот панели и найденный сдвиг кадра; откат на рабочий boot

**Факт с платы.** KWin видит `DSI-1` как `1600x2176@60`, rotation normal, но
планшет используется в горизонтали — десктоп и консоль выходили боком.
`kscreen-doctor output.DSI-1.rotation.right` даёт правильную картинку
(`2176x1600`), но настройка не сохраняется: `~/.local/share/kscreen/` на
планшете отсутствует, после перезагрузки поворот теряется. Поэтому поворот
делаем в ядре.

**Найден баг панели (не KWin).** После правильного поворота справа осталась
чёрная полоса ~10 % ширины, а слева картинка обрезана — то есть кадр сдвинут
примерно на 212 строк к началу кадра (в портрете это верхний край). Полоса
видна и в консоли на загрузке, значит компоситер ни при чём.

**Патчи (ядро `../linux-t1100`, выгружены в `patches/`):**

- `0045` — `drm/panel: it6112: report the panel orientation to the connector`:
  `get_orientation()` в панели + `rotation = <90>` в узле `panel@56`.
  `drm_bridge_connector_init()` передаёт это в connector как DRM-свойство
  `panel orientation`, и KWin/Weston сами поворачивают вывод. **Проверено
  12.11:** `kscreen-doctor` показывает DSI-1 `Rotation: 8` (90°), KDE в
  ландшафте.
- `0046` — **проверено 12.11**, сдвиг исправлен: `vsa 8, vbp 240, vfp 8` вместо
  вендорских `8/28/220` (сумма vblank та же — 256 строк, pixel clock не
  меняется); подробности в разделе `12.11 (1)`.

**Результат прошивки `build/boot_ubuntu36.img` (0045+0046):** (историческое:
причина цикла — `ramoops@70000000`, пересекавшийся с LK `ibc-reserved`, а не
0045/0046; после удаления ramoops оба патча загрузились). Планшет ушёл в
цикл перезагрузок (в USB виден только preloader `0e8d:2000`, RNDIS не
поднимается, цикл ~15 с). `pstore` после откáта пуст — паника/зависание
происходят раньше регистрации ramoops либо это reset по watchdog без дампа.
Конфиг нового ядра побайтово совпал с работающим (`/proc/config.gz`), так что
дело не в конфиге.

**Откат выполнен:** через Aurora Recovery (меню `5) Run sshd` — device-lock
проверка обходится, если rootfs не смонтирован; `root`/`recovery`) записан
`build/boot_ubuntu35.img` (`md5 91b28bfb…`), планшет снова грузится в Plasma
(`6.12.114-g4ec74fd3e6`). Исходный `boot_ubuntu36.img` сохранён
(`md5 c9bc248a…`) для разбора.

**Грабли:**

- recovery_telnet.py с devicelock-кодом не пускает (ни `REDACTED`, ни `12345`) —
  вход теперь через `5) Run sshd` + `root`/`recovery`.
- Имя RNDIS-интерфейса меняется каждую загрузку (`enx…`), профиль NM
  `t1100-recovery` привязан к имени: перед работой
  `nmcli connection modify t1100-recovery connection.interface-name <enx…>`.
- `scripts/build-kernel-remote.sh` требует `sshpass`; на этом хосте его нет,
  ключи к build-хосту работают — стоит заглушка `~/.local/bin/sshpass`
  (игнорирует `-p`, выполняет команду). Лучше перевести скрипт на
  key-auth вместо sshpass.

**Следующий шаг:** собрать ядро только с `0045` (без 0046) и проверить
ориентацию на железе — это отделит «ориентацию» от эксперимента с таймингом;
если загрузится, вернуться к сдвигу кадра (кандидаты: `vbp 220`, либо
явная установка line rate вместо pixel clock).


## 11.11 (2): тач снова у нас; Wi-Fi — план и выбор пути

**Тач.** Второй разработчик переключился на другую задачу, работа возвращена в
проект. Запущено два потока:
1) на железе (`bringup`): добрать вендорскую инициализацию из
   `docs/touch-hx83102e.md` §2.2 (`AHB 0x10007f04 = 0` (sorting mode),
   `reload_disable`, `reg_re_init`/`func_re_init`), `touch_avdd` →
   `regulator-always-on`, pull-up на GPIO1, затем повторная проверка кадра при
   тапах/удержании/мультитаче;
2) поиск публичного вендорского драйвера HX83102E на build-хосте (сеть там
   есть) — нужны настоящие init-таблицы и раскладка 56-байтного кадра, а не
   реконструкция по дизасму.

**Wi-Fi (фаза 5).** Идентификация и план — `docs/wifi-plan.md` (`ea2cb94`):
- combo **MT6631** (CONSYS_6771), Wi-Fi через **AHB/CONNSYS shared memory +
  WFDMA/CQDMA** (не SDIO/USB); прошивки в `/vendor/firmware`
  (`WIFI_RAM_CODE_6759` 480 752 Б, `mt6631_fm_v1_*`), `wifi-dma` = гейт
  `CLK_INFRA_CQ_DMA` (уже есть в mainline);
- важный факт: в стоковом dmesg Aurora **внутренний Wi-Fi не поднимался**
  (`wmt_core_stp_init: no hif info`, `opfunc_wlan_probe: hifType 0x2 … NOT
  IMPLEMENTED`), то есть «как в стоке» — не эталон;
- **путь A (порт вендорского gen3)**: на build-хосте найден публичный GPL-стек
  Motorola под MT6771 (`connectivity-common` `platform/mt6771.c`,
  `wlan-core-gen3` ~190k строк, MT6631→6759). Оценка: 2–3 недели до
  «собирается/power-on», 1.5–3 месяца до устойчивого `wlan0`, успех средний;
- **путь B (USB host + mainline-донгл)**: 2–5 дней, риск низкий; нужны
  role-switch T-PHY (готовый патч adomerle в `refs/mt6771-next/patches`),
  `tcpc` с узлом `connector`, VBUS через OTG-регулятор MT6370, конфиг
  `MT7601U`/`RTL8XXXU` + прошивки донгла; ограничение — один порт: в host-режиме
  нет ни RNDIS, ни зарядки (откат через recovery/`boot_b`);
- **DoD фазы 5**: после cold boot есть `wlan0` в `iw dev`, WPA2-PSK ассоциация,
  DHCP, ping+DNS; конфиг в git, откат проверен.

### 11.11 (3): решение по Wi-Fi — **путь A** (порт вендорского стека)

Выбран **A**: порт публичного GPL-стека Motorola Pie-9 под MT6771 на наше ядро
6.12. Обоснование: внутренний чип (MT6631/CONSYS) — единственный вариант без
внешнего железа и без «одного порта» (путь B лишает RNDIS и зарядки
одновременно); исходники есть, лицензия GPL-2.0, SoC-часть для MT6771 уже
написана вендором (`common_main/platform/mt6771.c`, 1067 строк).

Источники (зафиксированы в `docs/wifi-plan.md`):
`MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-common`
@ `Pie-9-release-POBS` `3ff67212` и `...-connectivity-wlan-core-gen3`
(213 файлов, 189 991 строка).

План по майлстоунам:
1. **Build-only спайк** (сейчас): обе части в отдельном дереве на build-хосте,
   сборка против 6.12, каталогизация API-долга 4.14→6.12 по файлам.
2. KAL (`os/linux/`, cfg80211/netdev) — привести к 6.12, модуль должен
   собираться и загружаться.
3. Power-on CONSYS: `wmt_core` + `platform/mt6771.c` (клоки, DCXO, EMI MPU,
   reserved memory `0xbfc00000`), проверка по `dmesg` (без сети).
4. Загрузка `WIFI_RAM_CODE_6759`, первая попытка `wlan0`.
5. WPA2/DHCP/ping — DoD фазы 5.

Ограничения пути A: вендорский `wmt_loader` — только бинарник; возможно
понадобится воспроизвести его последовательность (у нас уже есть опыт с
`sense_on`/AHB у тача). Путь B остаётся как резерв, но не выбран.

### 11.11 (4): поправка — в стоковой Aurora Wi-Fi **работал**

Владелец подтвердил: на стоковой Aurora Wi-Fi использовался, жалоб не было.
Наш `refs/device/dmesg-stock.txt.gz` — лог вендорского 4.14, но **неудачной**
загрузки: `wmt_core_stp_init: no hif info`, `hifType 0x2 = BTIF`,
`opfunc_wlan_probe … NOT IMPLEMENTED`. Правдоподобная причина — порядок
загрузки `wmt_loader`/модулей либо изменённая security-off конфигурация, а не
отсутствие поддержки чипа. Поправка внесена в `docs/wifi-plan.md`.
Следствие: для пути A есть **эталон рабочего поведения** — при отладке power-on
искать последовательность в рабочем стоке, а не в этом логе.

### 11.11 (5): Wi-Fi, майлстоун 2 — модули собираются под 6.12

Build-only (устройство не трогали, `../linux-t1100` не менялся; правки — в копии
на build-хосте, экспортированы в `patches/wifi/`, разбор — `docs/wifi-port-log.md` §18,
скрипты `scripts/build-wifi-remote.sh`):

| модуль | sha256 | размер | примечание |
|---|---|---|---|
| `wmt_drv.ko` | `0b4a2bfafc20…9162924b4` | 1 109 408 Б | 154 экспорта `mtk_wcn_*` |
| `wlan_drv_gen3.ko` | `cfd182c52813…b0638b8` | 2 895 080 Б | `depends: cfg80211,wmt_drv` |

`vermagic` — `6.12.114-g95e3b41b86-dirty SMP preempt mod_unload aarch64`, ошибок и
unresolved символов 0, сборка «с нуля» воспроизводит те же байты.

Что пришлось править (85 % механически): `proc_create`→`proc_ops`, time API,
`ioremap_nocache`→`ioremap`, `platform_driver.remove`→`void`, `timer_setup`,
`set_fs/get_fs`→`filp_open`/`kernel_read`, `netif_rx_ni`, `access_ok`,
`ip6_ptr`→`__in6_dev_get`, cfg80211-сигнатуры (`link_id`, `mgmt_frame_register`→
`update_mgmt_frame_registrations`, `current_bss`→`links[0]`, `roam_info.bss`).
В `mt6771.c` — `clk_buf`→no-op (TODO), PMIC LDO-биты убраны (это делает MT6358).

Stub'ы с `pr_warn_once` + TODO: AEE/AED, весь SDIO-транспорт (у нас AHB/WFDMA),
STP-over-UART (BT), WMT STEP, Android-хуки wlan, `show_stack`, `gConEmiPhyBase`
(нужно заполнить из DT — задача следующего шага). Не собираются осознанно:
SDIO-ветка, `stp_uart.c`, `wmt_step.c`, чужие SoC, `ahb_pdma.c` (у нас CQDMA).

**Следующий шаг (M3, power-on CONSYS)** — после того как закончим тач: DT-узлы
`consys@18070000` + `wifi@180f0000` + `consys-reserve-memory` 2 МиБ +
`<&infracfg CLK_INFRA_CQ_DMA>`, `gConEmiPhyBase` из DT, образ с этим ядром и
модулями (vermagic должен совпасть), первый признак — `wmt: power on ok` и
чтение WCIR `0x788`. Главный открытый риск — кто регистрирует STP-HIF для
MT6631 до power-on (BTIF vs собственный initcall; публичного `wmt_loader` нет).

## 11.11: итог дня (планшет на зарядке, работа приостановлена)

**Готово:** фазы 2 и 3 закрыты; фаза 4 — панель, GPU, Mesa 25.0.7 (GLES 3.1),
Weston 13 с EGL/Wayland (56.4 fps) работают на железе. `t1100-power-guard`,
build-хост с ccache и arm64-sysroot, статические `modetest`/`glmark2`/`egl-probe`,
`tools/host/screen-msg.sh` (сообщения на панель латиницей).

**В работе, но не доведено:**
1. **Тач HX83102E.** Найден вендорский исходник (`refs/himax-v2/`) — стало
   известно, чего не хватало: `AHB 0x100072EC = 0` (raw-out sel, вероятная
   причина шаблона `14 × 00 03 00 00`), `0x10007F04 = 0` (sorting), `sense_on`,
   `reload_to_active` (`0x90000048 = 0xEC`), затем чтение регистра `0x30`.
   Раскладка кадра доказана (be16 x/y ×10, `num_points = buf[52] & 0x0F`,
   checksum — сумма 56 байт ≡ 0 mod 256). Проверка на железе — следующий шаг.
2. **Wi-Fi (фаза 5, путь A).** M1 (build-спайк) и M2 (модули) закрыты:
   `wmt_drv.ko` `0b4a2bfa…`, `wlan_drv_gen3.ko` `cfd182c5…`, vermagic
   `6.12.114-g95e3b41b86-dirty`, 0 ошибок. M3 подготовлен (DT-узлы `consys`/
   `wifi`, reserved-memory, `wifi-dma`, `gConEmiPhyBase`, образ
   `boot_ubuntu35`, скрипт деплоя `tools/host/wifi-deploy.sh`) — **на железе не
   проверялся**.

**Порядок на следующую сессию:** 1) тач — прошить образ с вендорским init и
проверить кадр при касаниях (сообщение на панель заранее); 2) Wi-Fi M3 — прошить
`boot_ubuntu35`, разложить модули, `insmod wmt_drv` → `wmt: power on ok` +
WCIR `0x788`; 3) затем libinput/десктоп и DVFS GPU. Не смешивать две прошивки в
одном шаге.

### 11.11 (6): **тач работает** — координаты и `ABS_MT_*` есть

Причина «константного кадра» найдена и устранена: кадр надо читать через
**1-байтный суб-адрес `0x30`** (`himax_bus_read_reg`), а не через
`himax_bus_read()`/`regmap_raw_read()` (они уходили в AHB `0x30` — отсюда был
`14 × 00 03 00 00`). Плюс полный вендорский init (патч **0047**):
`AHB 0x100072EC = 0` (raw-out sel), `0x10007F04 = 0` (sorting mode),
`sense_on`, reset GPIO158, **`reload_to_active`** (`0x90000048 = 0xEC`, ack
`ec 01`), поллинг `0xA8 == 0x05`, честная 56-байтная сумма.

Факты с железа (образ `build/boot_ubuntu40.img`, sha256 `986bce63…7938`,
ядро `6.12.114-g95e3b41b86-dirty`):

```
кадр: 03 81 04 3d ff ff … 0f 00 … 00 01 00 00 37
      x=897 y=1085  majors[0]=15  num_points=1  sum(56 Б) ≡ 0
event1 (1746 событий за сессию): TRACKING_ID, POS_X/POS_Y, TOUCH_MAJOR,
      WIDTH_MAJOR, BTN_TOUCH, SYN
тапы: (1467,145) (933,880) (48,2103) (771,1115) — в диапазоне 1600×2176,
      но X инвертирован
```

Патч **0048**: `touch_avdd` → `always-on`, pull-up на EINT1,
`touchscreen-inverted-x` (на железе ещё **не перепроверялся** — устройство уже
отключено).

**Осталось (первый шаг следующей сессии):**
1. загрузить `boot_ubuntu40` и проверить, что `inverted-x` дал правильную
   ориентацию (тап в левый верхний угол → малые x,y);
2. холодная загрузка даёт `power on init: FW did not report reload (0x0)` и
   `-110`: `0xA8` становится `0x05` только через минуту (на «прогретом» чипе —
   с первой пробы). Гипотеза: как в стоке, перед init нужен `sense_off`
   (`0x9000005C = 0xA5` с ожиданием `0x87`); проверить с dynamic debug на
   `himax_sense_on` и, если подтвердится, добавить `sense_off` перед
   `power_on_init`;
3. после этого — `libinput` + проверка тача в Weston.

### 11.11 (7): Wi-Fi M3 подготовлен (build-only, на железе не проверялся)

**Образ:** `build/boot_ubuntu41.img` (не 35 — имя `boot_ubuntu35` занято рабочим
откатным образом), sha256 `0c21c2f3261bae95456923fb9b79ff9780d73e196929ea89e2b6274997a9589e`,
ядро + модули собраны на `675178729` + патч 0049, **vermagic у всех идентичен**:
`6.12.114-g675178729a-dirty SMP preempt mod_unload aarch64`.

| артефакт | sha256 |
|---|---|
| `Image` | `696ce20e1bb51038cda80a2be13a5a76b6f2b8761eb8d1a5b2442480d03da9d7` |
| DTB `mt6771-fplus-t1100.dtb` | `bebd312f62e5f7089d4d6715ab90d8da1eb72796486b348cb78acf12c665fa33` |
| `wmt_drv.ko` | `cc2f061d59824e25677837a751166c516be58cd1cf6016f6811a16f87031176a` |
| `wlan_drv_gen3.ko` | `ba69c10fddc6377104d81e7f11054ae2aff858701f87426560c49ce8ee6c413c` |
| `cfg80211.ko` / `mac80211.ko` / `rfkill.ko` | `e30338f8…` / `c8acef16…` / `d765f566…` |

**DT (патч 0049):** `consys@18070000` (окна 0x18070000/0x10007000/0x10001000/0x10006000,
IRQ 289/291), `wifi@180f0000` (0x180f0000/0x10212180/0x10001000/0x180e0000, IRQ 290/118,
`clocks = <&infracfg CLK_INFRA_CQ_DMA>`, `hardware-values = <0x788 0xa5800 0xa5800>`),
`consys-reserve-memory` 2 МиБ `no-map` с `alloc-ranges`. Оба новых узла
`status = "disabled"` — поведение HEAD не меняется (тач 0047/0048 не откатывается).
Четыре отклонения от стока обоснованы в патче: без `clocks` у consys (нет
`mediatek,scpsys` в mainline; домен поднимается SPM `0x1000632c` = `ctl_offs 0x032c`,
как `MT8183_POWER_DOMAIN_CONN`), `alloc-ranges` вместо фиксированного `reg`
(LK-конфликт-чек), `wifi-dma` = инфра-гейт `CLK_INFRA_CQ_DMA` (а не topckgen `0x4e`),
`vcn33_wifi`/`vcn33_bt` — один rail.

**Драйверная часть** (`patches/wifi/0002`): `gConEmiPhyBase/Size` из DT
(`of_reserved_mem_lookup` → fallback `of_address_to_resource`), `devm_clk_get_optional`,
нормализация `ERR_PTR` от `regulator_get`; `CONFIG_MTK_COMBO_CHIP="CONSYS_6771"`
(в кавычках) передаётся в сборку.

**Деплой:** `tools/host/wifi-deploy.sh` (`--apply` → `.ko` в
`/lib/modules/<release>/updates/wifi` + `depmod`; `--apply --enable` → юнит
`t1100-wifi.service`, `start` не делает), release сверяется с `uname -r`.

**План проверки M3:** `--load wmt` → ожидаем
`CONNSYS EMI from DT: phys …, size 0x200000` → `Clearing Connsys EMI …` →
**`wmt: power on ok`** → chip id **`0x788`**. Риск №1 прежний: STP-HIF для MT6631
(публичного `wmt_loader` нет); прошивки `WIFI_RAM_CODE_6759`/`WMT_SOC.cfg` в rootfs
пока нет.

### 12.11 (1): сдвиг кадра на панели исправлен — 0046 проверен на железе

**Симптом:** изображение (и консоль, и KDE) было сдвинуто примерно на 10%
экрана — ~212 строк из 2176: чёрная полоса на верхнем краю портрета,
противоположный край обрезан. Это не userspace: сдвиг виден и в консоли.

**Исправление:** патч 0046 переносит 212 строк из front porch в back porch:
`vsa 8`, `vbp 240`, `vfp 8` вместо `vsa 8`, `vbp 28`, `vfp 220`. Общий vblank
(256 строк) и pixel clock не меняются, поэтому это только сдвигает активное
окно внутри кадра. Раньше 0046 подозревали в boot loop, но причиной был
`ramoops@70000000` (пересечение с LK `ibc-reserved`), а не сам патч.

**Проверка:** `build/boot_shift.img` (Image sha256
`b0fba96d30347cf384eae3e0e16ff52cab6306334a920c6d9b2eff4128bdd81d`,
DTB `45dbffdc…`, initramfs `0cfa596d…`, md5 p29
`0f1ba550272fd049c92cb98dd2208116`) прошит в `boot_a`; ядро
`6.12.114-g400cb6f-touch-rot`; пользователь подтвердил 12.11: «отступ
починился, теперь это корректно».

**Тач в этом же образе:** после удаления `reload_to_active`
(`0x90000048=0xEC`) в `himax_sense_on` исчезли `Wrong event checksum: 33a0`,
но `/dev/input/event1` пока не выдаёт событий; `A8` после reset поднимается
до `0x05` и затем читается как 0. Идёт отладка (гипотеза: отладочное чтение
`0x48`/порядок `addr_raw_out_sel`), чистовой патч и образ — после подтверждения.

### 12.11 (2): тач работает; координаты совпадают с экраном

**Причина молчания:** отладочная `himax_dbg_state()` читала `0x900000A8`
сразу после reset, а этот регистр read-clear — флаг `0x05` «съедался» до
poll. После удаления всех debug-чтений A8 предупреждение
`FW did not report reload` исчезло, `himax_sense_on()` проходит штатно.
В host-дереве рабочая последовательность: `sense_off`, burst, `0x100072EC=0`,
`0x10007F04=0`, `0x9000005C=0`, reset 20/50 мс, **без** `reload_to_active`,
poll A8 до 3 с. Патч 0047 в репозитории ещё содержит reload — чистовой
driver-патч нужно оформить отдельно.

**Ориентация (окончательно):** панель используется в ландшафте 2176×1600,
но KWin 5.27 сам применяет 90-градусный output transform к координатам
устройства: `devicePointToGlobalPosition()` берёт `output->modeSize()`
(портретные 1600×2176) и поворачивает их. Поэтому kernel не должен ни
инвертировать, ни менять оси — иначе KWin поворачивает второй раз и курсор
уходит зеркально. Патч **0051** убирает `touchscreen-inverted-x` (0048) и
`touchscreen-swapped-x-y` (0050); координаты остаются native portrait.
Четыре угла проверены на `boot_touch6`, тач в KDE работает.

**Образ:** `build/boot_touch6.img`, md5 p29
`0325328c7a5fe68f9780c61f7b5bbff4`, sha256 `daee7324…`, Image `63e023ad…`,
DTB `2b53c552…`; прошит и проверен на железе, `p29` readback совпал.
Осталось: разобраться с задержкой выделения в приложениях (evdev даёт
~112 Гц, kernel не тормозит) и оформить чистовой driver-патч без reload/
debug-чтений A8.

### 12.11 (3): Ubuntu 26.04 + KDE Plasma 6.6.4, 8 ядер, финальный сдвиг (0052)

- **Rootfs:** p54 перезаписан Ubuntu 26.04 LTS (debootstrap, затем chroot+qemu
  desktop): KDE Plasma 6.6.4, SDDM с autologin root, Konsole, Dolphin, Kate,
  Ark, Gwenview, Okular, KCalc, Spectacle, Plasma Keyboard, Mesa 26.0.3.
  Старый 24.04 сохранён в `/home/l/t1100-rootfs2404-backup.tar.gz` (498 MB,
  sha256 `29f440bd…`); 26.04 desktop tar — `/home/l/t1100-rootfs2604-desktop.tar.gz`
  (1.2 GB, sha256 `b75a40c4…`).
- **8 ядер:** в cmdline был последний `maxcpus=1`; `build/boot_touch7.img`
  заменил его на `maxcpus=8` — `nproc=8`, online 0–7.
- **Сдвиг панели:** после 0046 оставалась чёрная полоса ~2% слева; патч
  **0052** увеличил `vbp` 240→284 (`vtotal` 2476, pixel clock не изменён,
  refresh 58.93 Hz). Образ `build/boot_touch8.img` (sha256 `757f7e03…`,
  md5 p29 `75aff081…`) прошит, сдвиг убран, пользователь подтвердил.
- **Тач:** работает в KDE, native portrait (0051); остаётся задержка выделения
  в приложениях — evdev отдаёт ~112 Гц, причина в userspace.
- **Plasma Keyboard:** по запросу добавлен ряд цифр 1–0 в
  `/usr/share/plasma/keyboard/layouts/fallback/main.qml` (и `en_US/main.qml`);
  клавиатура проверена через `org.kde.kwin.VirtualKeyboard.forceActivate`,
  ряд отображается и работает. Это настройка rootfs, не патч ядра.
- **Дальше:** задержка выделения, DVFS GPU, Wi-Fi/BT (фаза 5).

### 12.11 (4): «сон» — это DPMS-гашение, а не suspend; панель после него ломается

**Что происходит.** В журнале нет ни `PM: suspend`, ни `Suspending system`:
планшет **не засыпает**, PowerDevil просто гасит экран (DPMS off). «Просыпание»
кнопкой — это DPMS on.

**Баг.** После DPMS off → on изображение возвращается сдвинутым (~10 %) и с
цветными полосами. Воспроизводится вручную:

```
kscreen-doctor --dpms off; sleep 5; kscreen-doctor --dpms on
```

**Причина (частично).** Драйвер работает с `t1100.it6112_skip_init=1`: мост
остаётся в состоянии, которое оставил LK, и на `->enable()` драйвер только
повторяет DCS exit-sleep/display-on. При остановке потока мост теряет
синхронизацию и сам не восстанавливается.

**Что чинит.** Вендорский импульс TX-on, который LK посылает перед DCS:
`i2c3 0x56`, регистр `0x05`: `0xfe` → `0x00`. Проверено на живом «сломанном»
мосте: после импульса картинка сразу нормальная.

**Что не сработало.** Патч, который посылал этот импульс в `->enable()`
(сначала всегда, потом только после `->unprepare()`), дважды приводил к
циклу перезагрузок; `pstore` пуст, точное место клина не найдено. Патч лежит
в `patches/wip-0053-dpms-tx-pulse.disabled`, образы —
`build/boot_dpmsfix{,2,3}.img`.

**Временно (на планшете):**

```
systemctl mask --now sleep.target suspend.target hibernate.target hybrid-sleep.target
systemctl --user mask --now plasma-powerdevil.service   # от root-сессии
```

Гашения экрана и сна нет; заряд/индикатор остаются на `t1100-power-guard`.

**Откат boot после неудачной прошивки:** Recovery → меню `5) Run sshd`
(`root`/`recovery`) → `dd` рабочего образа `build/xfer/cur_boot.img`
(md5 `75aff08106e36c5ba207081c8cfc77ad`) в `/dev/mmcblk0p29` → `reboot -f`.

**Важно про дерево ядра.** Актуальное дерево — на build-хосте
`/home/l/t1100-ubuntu-build/src` (патчи 0001–0052, touch, Wi-Fi) и
out-дерево `out-normal` (release `6.12.114-g400cb6f-touch-rot`). Локальное
`../linux-t1100` отстаёт (0042 + два патча 0045/0046) — `scripts/build-kernel-remote.sh`
синхронизирует локальное дерево на хост и **затрёт** актуальное, поэтому
собирать надо прямо на хосте.

### 12.11 (5): клавиатура Plasma — восстановлены `normalKeyWidth`/`functionKeyWidth`

**Симптомы:** в английской раскладке часть кнопок не отображалась, пробел
растягивался на всю строку, служебные клавиши (Shift, глобус, `&123`,
backspace) уезжали за край. Русская раскладка при этом работала.

**Причина:** в `layouts/fallback/main.qml` и `layouts/en_US/main.qml` были
потеряны две строки, которые есть в `ru_RU/main.qml`:

```
readonly property real normalKeyWidth: normalKey.width
readonly property real functionKeyWidth: mapFromItem(normalKey, normalKey.width / 2, 0).x
```

Без них `weight` служебных кнопок и `Layout.preferredWidth` подстрок были
`undefined`, а `SpaceKey` (единственный с `fillWidth`) забирал всю строку.

**Цифровой ряд (добавлен позже, 12.11).** Панель имеет фиксированную высоту
под 5 рядов (замерено 555 px при экране 1600), поэтому 6-й ряд сам по себе
уезжает за экран. Решение: у всех `KeyboardRow` выставлен
`Layout.fillHeight: true`, у всех клавиш — `Layout.minimumHeight: 0`, и ряды
делят высоту панели поровну (6 × ~92 px). Цифровой ряд есть во всех трёх
раскладках (`fallback`, `en_US`, `ru_RU`), у клавиш `1..0` символы
`! @ # $ % ^ & * ( )` доступны удержанием (`alternativeKeys`) и показаны
мелким `smallText`.

Файлы зафиксированы в `rootfs-overlay/usr/share/plasma/keyboard/layouts/`
(`fallback/main.qml`, `en_US/main.qml`) — это же лежит на планшете.

### 12.11 (6): раскладки клавиатуры зафиксированы в `rootfs-overlay/`

Итоговые раскладки (проверены на планшете, пользователь подтвердил):

- верхний ряд `1..0` во всех трёх — `fallback`, `en_US`, `ru_RU`;
- у цифр удержание даёт `! @ # $ % ^ & * ( )`, мелкий `smallText` их показывает;
- из верхнего буквенного ряда английской раскладки убраны лишние цифровые
  `smallText`/`alternativeKeys` (`q1`, `w2`, …) — цифры теперь и так в отдельном
  ряду; акценты в `alternativeKeys` сохранены;
- 6 рядов делят высоту панели (`Layout.fillHeight` + `Layout.minimumHeight: 0`).

Файлы: `rootfs-overlay/usr/share/plasma/keyboard/layouts/{fallback,en_US,ru_RU}/main.qml`.

### 12.11 (7): батарея — топливомера нет; сборка ядра с build-хоста не грузится

**Индикация заряда.** В mainline нет `mt6358_gauge`. В `/sys/class/power_supply/`
только `mt6370-charger` (`type=USB`, `online`, `status=Charging`, без
`capacity`). Напряжение читается через IIO MT6370 ADC:
`iio:device0`, `in_voltage3_raw` × `scale=5` = мВ (`vbat`), `in_current6_raw`
× 50 = мА (`ibat`). Сейчас: vbat ≈ 3825 мВ, status Charging.
PowerDevil замаскирован (см. 12.11 (4)), поэтому значка батареи в трее нет.

**Страховка от разряда** восстановлена на новом rootfs:
`tools/host/install-power-guard.sh 10.42.66.66` — таймер активен, ток заряда
поднят до 2 А, предупреждение про SDP.

**Попытка №1 — драйвер батареи в ядре (не удалась).** В
`drivers/power/supply/mt6370-charger.c` добавлен второй `power_supply`
(`mt6370-battery`: PRESENT/TECHNOLOGY/STATUS/VOLTAGE_NOW/CURRENT_NOW/CAPACITY,
проценты по OCV-таблице 1S Li-ion). Собирается, но **прошитый образ уходит в
цикл перезагрузок**: в cmdline следующей загрузки `androidboot.bootreason=lk_crash`,
`pstore` пуст — падает/зависает LK, а не ядро. Ранее так же падали мои образы
`boot_ubuntu36` и `boot_dpmsfix*` (панель/DPMS). То есть дело не в конкретном
патче: **перепакованные на этом хосте образы LK не принимает**, хотя раньше
`boot_ubuntu36` собирался тем же `repack_boot.py`. Причина не выяснена —
сравнивать надо gzip-поток/размеры/адреса с образами, которые собирала
вторая сессия (`build/boot_touch8.img`).

**Откат** (рабочий): Recovery → меню `5) Run sshd` (`root`/`recovery`) →
`dd` `build/xfer/cur_boot.img` (md5 `75aff081…`) в `/dev/mmcblk0p29` → `reboot -f`.

**План для индикации заряда:** сделать пользовательский виджет KDE (QML),
читающий `vbat`/`ibat` из IIO и показывающий процент в панели — без правок
ядра. Причина: прошивка ядра сейчас рискованна (LK crash), а виджет безопасен.

### 12.11 (8): индикация заряда работает; причина циклов — образ без initramfs

**Причина всех «циклов перезагрузок» найдена.** В перепакованных мной образах
не было initramfs: в заголовке `ramdisk_size = 0`, а у рабочего образа
`1 396 043` Б. Ядро без initramfs не монтировало root и уходило в панику
(`androidboot.bootreason=lk_crash` вводил в заблуждение). Патчи панели и
батареи были ни при чём: ядро, собранное с ними, грузится после того, как в
образ добавлен ramdisk.

**Исправление инструмента:** `scripts/repack_boot.py` теперь, если `--ramdisk`
не задан, берёт ramdisk из `--ref` и пишет об этом в лог, вместо тихого
`ramdisk 0`.

**Батарея (патч 0053, `drivers/power/supply/mt6370-charger.c`).** Второй
`power_supply` `mt6370-battery`: PRESENT/TECHNOLOGY/STATUS/VOLTAGE_NOW/
CURRENT_NOW/CAPACITY, проценты — по OCV-таблице 1S Li-ion (грубо, без
кулоновского счётчика). На железе (`build/boot_battery2.img`, ramdisk включён):

```
mt6370-battery: type=Battery status=Charging present=1 capacity=50
                voltage_now=3805000 current_now=0 technology=Li-ion
```

UPower видит `battery_mt6370_battery` (50 %, 3.805 В, charging), PowerDevil
размаскирован, в трее есть значок с процентом.

**Осторожно:** с PowerDevil снова действует гашение экрана по простою, а после
DPMS off/on панель ломается (см. 12.11 (4)) — в System Settings → Энергия
выставить «Гасить экран: Никогда» (сон тоже). Иначе снова полосы.

### 12.11 (9): PowerDevil — гашение экрана и автосон отключены через `powerdevilrc`

PowerDevil вернули (нужен для значка батареи), но убрали гашение экрана и
автосон — иначе после DPMS off/on панель снова ломается (12.11 (4)).
Ключи в Plasma 6.6 — CamelCase и группы `[Профиль][Display]` /
`[Профиль][SuspendAndShutdown]` (см. `PowerDevilProfileSettings.kcfg`):

```
[AC][Display]
DimDisplayWhenIdle=false
TurnOffDisplayWhenIdle=false
LockBeforeTurnOffDisplay=false

[AC][SuspendAndShutdown]
AutoSuspendAction=0
AutoSuspendIdleTimeoutSec=0
```

то же для профиля `[Battery]`. Проверка: в журнале PowerDevil пропадают
строки `DPMS: registering idle timeout …` и `DimDisplay: registering idle
timeout …` (при неверных ключах он регистрирует дефолтные 600/300 с).
Файл зафиксирован в `rootfs-overlay/root/.config/powerdevilrc`.

### 12.11 (10): датчики — шина i2c1 включена, чипы найдены, драйверы ещё нет

**Сделано:** в DTS включён `&i2c1` (`0x11011000`, `vbus-supply = <&i2c_vbus>`) —
это шина датчиков, раньше она была `disabled`. После прошивки
(`build/boot_i2c1.img`) в системе есть `/dev/i2c-1`.

**Что найдено на шине (проверено вручную через SMBus):**

- **ICM-42607** на `0x68`: `WHO_AM_I (0x75) = 0x60` — чип живой и отвечает;
- **STK3x3x** на `0x57`: ACK есть, запись в регистр `0x00` проходит
  (`0x00 = 0x03` — state ALS+PS), но `0x0E/0x0F` (PID/VID у вендора
  `0x5b/0x00`) читаются как 0 — нужен вендорский power-up/банк регистров.

**Почему драйверы пока не подключаем:**

- `inv_icm42600` в 6.12 знает 42600/42602/42605/42622/42631/42686/42688,
  **42607 нет**; кроме того драйверу нужен аппаратный INT, а в вендорском DT
  у gsensor/gyro прерывания нет (MTK-драйвер опрашивает сам) — нужен патч
  драйвера (+ поиск/подтверждение INT-линии);
- `stk3310` в 6.12 знает ID `0x31/0x13/0x1D/0x15/0x1E/0x12/0x51`, нашего
  `0x5b` (STK3338) нет; плюс неизвестна последовательность включения — нужен
  разбор вендорского `stk3x3x` (как когда-то с тачем).

**Что уже видно в стоковом логе для справки:** ALS/PS `stk3x3x` инициализируется
с `psctrl=0x32, alsctrl=0x32, ledctrl=0xc0, wait=0x1f, int=0x1`,
`pid=0x5b, vid=0x00`, IRQ — GPIO6 (`interrupts = <6 …>` в узле `alsps@49`).

Дальше: разобрать вендорский `stk3x3x` (регистры/power-up) и добавить
ICM42607 в `inv_icm42600` — каждый пункт отдельной задачей.

## 12.11 (8): соединены ветки, ядро второго разработчика прошито, rootfs 26.04 + Plasma развёрнут

**Слияние.** В `master` вошли 12 коммитов второго разработчика (fast-forward,
конфликтов не было): сдвиг кадра (0046 проверен, 0052 — `vbp` 240→284,
refresh 58.93 Гц), тач-ориентация (0050/0051 native portrait),
Plasma Keyboard (`rootfs-overlay/usr/share/plasma/keyboard/layouts/*`),
tooling (`recovery_get_boot_header.py`), большая синхронизация документации.

**Ядро.** Образ собран из ЕГО дерева на build-хосте
(`/home/l/t1100-ubuntu-build/out-normal`, release `6.12.114-g400cb6f-touch-rot`)
с нашим `cmdline` и `maxcpus=8`:
- `build/boot_merged12.img`, sha256 `651ab53c22b6bcbab0843a0c782a6cd2bf6326279706c17c85927341254e2ab6`,
  md5 `251492a50a1c163c9c6701f1ebe3f093`;
- DTB `2b53c552…e9ff89` (52 669 Б), `tools/lk/verify-dtb.sh` → **validator passed**;
- прошит в `p29` из recovery, sha раздела сверен; **загрузился**:
  `uname -r` = `6.12.114-g400cb6f-touch-rot`, `nproc` = **8**,
  `card1-DSI-1` = connected, `Himax Touchscreen` = `event1`.

**Rootfs.** `p54` заменён на Ubuntu **26.04 LTS + KDE Plasma 6.6.4** из
тарбола второго разработчика (`b75a40c4…`, 1.2 ГБ, с build-хоста) — развёрнут
потоком `nc | tar` из recovery, 3.5 ГБ на разделе, `display-manager.service` →
`/lib/systemd/system/sddm.service`.

**Блокер доступа (на момент записи).** В новом rootfs пароль root заблокирован
(`/etc/shadow`: `root:*`), а в `/root/.ssh/authorized_keys` лежит только ключ
второго разработчика (`leonidy85@gmail.com`). Наш ключ нужно дописать из
recovery (30 секунд) либо получить его приватный ключ. Пароли (`0`, `1`,
`12345`, `root`, `password`, `ubuntu`) отклоняются — это не гадание, а
следствие `root:*`.

**Wi-Fi M3 (build-only).** Модули пересобраны под прошитое ядро:
`wmt_drv.ko` sha256 `8228dd5c…9bbead`, `wlan_drv_gen3.ko` `4bbdb1d5…5f2b91`,
плюс ядерные `cfg80211.ko` `ae891d54…`, `mac80211.ko` `b4ad9b62…`,
`rfkill.ko`, `libarc4.ko`; vermagic у всех — `6.12.114-g400cb6f-touch-rot`.
Важно: в конфиге второго разработчика `CFG80211=m` и нет
`configs/t1100-wifi.fragment`, поэтому в копии out включён
`CONFIG_NL80211_TESTMODE=y` — **`cfg80211.ko` из нашего набора обязателен**
(иначе рассинхрон layout `cfg80211_ops`). WEXT на этом ядре недоступен
(`wext-core` built-in при `CONFIG_WEXT_CORE=y`), nl80211/wpa_supplicant — работают.
Прошивки `WIFI_RAM_CODE_6759`/`WMT_SOC.cfg` в rootfs нет — до неё `wlan0`
не появится.
### 12.11 (11): автоповорот работает — бэкпорт драйвера `inv_icm42607`

**Почему раньше «не работал».** ICM-42607-P — не 42600/42605: у него **другая
карта регистров**. `DEVICE_CONFIG` там `0x01`, а `0x11` — это `GYRO_DATA_X1`
(данные гироскопа, read-only). Поэтому записи «не применялись»: мы писали в
регистры данных, а читали `0x80` — это старший байт гироскопа, а не признак
ошибки. `WHO_AM_I (0x75) = 0x60` соответствует именно 42607**P**.

Проверенная тупиковая гипотеза: питание датчика. Включал `vmch`, `vcamio`,
`vcamd`, `vcn28` через `regulator-always-on` — на записи это не влияет, откатил.

**Решение — патч `0054`, бэкпорт upstream-драйвера.** В mainline (2026) появился
отдельный `drivers/iio/imu/inv_icm42607/` (10 файлов + Kconfig/Makefile).
Перенёс на 6.12 с тремя правками под старые API:

- `devm_kzalloc_obj(dev, *st)` → `devm_kzalloc(dev, sizeof(*st), GFP_KERNEL)`;
- `PM_RUNTIME_ACQUIRE_AUTOSUSPEND/PM_RUNTIME_ACQUIRE_ERR` (scope-based API
  появился после 6.12) — шим в `inv_icm42607.h`: `pm_runtime_resume_and_get()`
  + `__attribute__((cleanup))` с `pm_runtime_put_autosuspend()`;
- пространства имён: `"IIO_ICM42607"` → токен `IIO_ICM42607` (строковая форма
  в 6.12 ещё не поддерживается генератором экспорта).

**DTS.** `&i2c1` (`0x11011000`) — шина датчиков, переведена на 400 кГц, как в
вендорском DT (`clock-frequency = <0x61a80>`). Узел:

```dts
imu@68 {
	compatible = "invensense,icm42607p";
	reg = <0x68>;
	vdd-supply = <&reg_sensor_vdd>;		/* fixed, always-on */
	vddio-supply = <&reg_sensor_vdd>;
	mount-matrix = "-1", "0", "0", "0", "-1", "0", "0", "0", "1";
};
```

`mount-matrix` — эмпирика: вендорский `icm42607_a_direction = 0` для нашей
панели неверен, с единичной матрицей интерфейс во всех ориентациях стоял
вверх ногами; поворот на 180° (X и Y с минусом) исправляет.

**Результат на железе:**

```
iio:device1: icm42607p-accel      iio:device2: icm42607p-gyro
mount_matrix: -1, 0, 0; 0, -1, 0; 0, 0, 1
```

Автоповорот в KWin через iio-sensor-proxy работает, проверено пользователем
(«Теперь верно»). INT1 на плате не разведён — драйвер это учитывает (IIO
direct read), прерывание не нужно.

Осталось из датчиков: STK3x3x (свет/приближение) — отдельная задача, там тоже
своя карта регистров и нужен разбор вендорского power-up.

### 12.11 (12): датчик света/приближения STK3338 работает

**Чип опознан.** `stk3310_check_chip_id` в mainline читает ID из регистра
`0x3E` — там `0x5B`, это **STK3338**. В списке `stk3310_chip_ids[]` его не было,
поэтому драйвер не биндился; добавлен ID и compatible `sensortek,stk3338`
(патч `0055`).

**DTS.** На `&i2c1` узел:

```dts
light-sensor@57 {
	compatible = "sensortek,stk3338";
	reg = <0x57>;
	interrupt-parent = <&pio>;
	interrupts = <6 IRQ_TYPE_EDGE_FALLING>;
	pinctrl-0 = <&alsps_irq_pins>;	/* GPIO6, pull-up как в вендорском DT */
};
```

**Проверено на железе** (`iio:device3: stk3310`):

- ALS: на свету `in_illuminance_raw` ≈ **272–287**, при закрытии датчика —
  **0**; реакция повторяемая (несколько прогонов);
- PS: при накрытии ладонью `in_proximity_raw` падает **≈117 → 0–15**, после
  снятия возвращается ≈120. То есть у STK3338 «объект рядом» даёт **низкое**
  значение, а не высокое, как у вендорских порогов (`thld_high = 0x6a4`);
  для событий «near/far» это надо будет учесть, для автοяркости не важно;
- регистры при этом: `state = 0x03` (ALS+PS), `alsctrl = 0x02`, `psctrl`,
  `ledctrl` — штатные значения драйвера; ручная подстройка gain/IT через
  sysfs (`in_illuminance_scale`, `in_illuminance_integration_time`) работает.

Замечание: при записи `in_proximity_scale`/`in_proximity_integration_time`
USB-гаджет один раз отвалился на несколько секунд — повторить не удалось,
на работу датчика не повлияло; вероятнее всего совпало с переподключением
кабеля, а не с sysfs.

Автοяркость в KDE 6 из коробки не подключена (Plasma не умеет ALS без
стороннего демона) — датчик готов, демон можно добавить отдельно.

### 12.11 (13): звук — ALSA-карточка, динамик поёт через PipeWire + UCM

**Что выяснилось:** аудиоблок MT6771 (`0x11220000`) регистрово совпадает с
MT8183, поэтому mainline-драйвер AFE `sound/soc/mediatek/mt8183` работает на
нём без правок (в dmesg: `mt8183-audio 11220000.audio-controller: ... num of
dai 20`, кодек `mt6358-sound` поднялся). Не хватало только machine-драйвера,
связывающего AFE с кодеком MT6358; I2S-кодека на плате нет — звук идёт через
DAC MT6358 и **внешний аналоговый усилитель**, включаемый GPIO159.

**Патч 0056** (`sound/soc/mediatek/mt6771/mt6771-mt6358.c` + Kconfig/Makefile
+ DTS-узел `sound`):
- FE `Playback_1`/`Capture_1`: CPU `DL1`/`UL1` (AFE), `.dynamic`, `.dpcm_*`;
- BE `Primary Codec`: CPU `ADDA`, CODEC `mt6358-sound`/`mt6358-snd-codec-aif1`;
- GPIO159 (`amp-gpios`) включается на playback.

**Маршрут (главное открытие):** тишина была не из-за DPCM, а из-за mux'ов
кодека, которые по умолчанию стоят в `Open`. Нужно:
```
ADDA_DL_CH1 DL1_CH1   1
ADDA_DL_CH2 DL1_CH1   0
ADDA_DL_CH2 DL1_CH2   1
DAC In Mux            Normal Path
HPL Mux               LoudSPK Playback
HPR Mux               LoudSPK Playback
```
после чего DAPM включает `AIF_RX`/`DACL`/`AUDIO_TOP_DAC_CTL`/`AFE_ON`.

**Автоматизация — UCM2** (в `rootfs-overlay/usr/share/alsa/ucm2/conf.d/mt6771-mt6358/`:
`mt6771-mt6358.conf` + `HiFi.conf`, устройство `Speaker`), PipeWire/wireplumber
подхватывают профиль: в `wpctl status` появляется Sink «Built-in Audio Internal
speaker», маршруты выставляются сами при старте потока. Проверено
`pw-play /tmp/tone.wav` — **слышно тон**.

**Инструменты проверки** (статически собраны для aarch64, в `/tmp/opencode/`):
- `rawplay` — ALSA-плеер на сырых ioctl (синус 440 Гц), нужен, когда PipeWire не поднят;
- `ctlroute` — LIST/SET только для boolean-контролов (AFE-микшеры);
- `ctlenum` — LIST/SET для enum-контролов (`DAC In Mux`, `HPL/HPR Mux`, …),
  `ctlroute` их не умеет.

**Замечания:** PipeWire в этом rootfs не стартует как сервис (нет DBus-сессии в
`/run/user/0`), запускается вручную: `XDG_RUNTIME_DIR=/run/user/0 setsid pipewire`
и `setsid wireplumber`. `alsaucm`/`amixer`/`alsactl` в rootfs нет — UCM
проверяется только через PipeWire. GPIO159 в `/sys/kernel/debug/gpio` не виден,
но звук работает (усилитель, похоже, включён всегда/через другую линию — уточнить).

### 12.11 (14): звук — автозапуск PipeWire и маршрут динамика на загрузке

**Задача:** после перезагрузки звук должен работать сам, без ручных команд.

**1. PipeWire под root.** Стоковые user-юниты содержат `ConditionUser=!root`,
поэтому у нас они скипались (`pipewire.socket - skipped, unmet condition
check ConditionUser=!root`). Добавлены drop-in'ы
`/etc/systemd/user/{pipewire,pipewire-pulse}.{service,socket}.d/90-allow-root.conf`
и `wireplumber.service.d/90-allow-root.conf` с

```
[Unit]
ConditionUser=
```

плюс `loginctl enable-linger root` — менеджер пользователя поднимается на
загрузке, `pipewire.socket`, `pipewire.service`, `wireplumber.service` active.

**2. Sink без ACP.** WirePlumber 0.5 держит у карты профиль `off`
(`api.acp.auto-profile=false`), а ACP на этой карте не отдаёт профилей, хотя
UCM парсится (`snd_use_case_mgr_open("mt6771-mt6358") == 0` через
ctypes/libasound). Поэтому выход создаётся напрямую в
`/etc/pipewire/pipewire.conf.d/51-alsa-sink.conf`:

```
context.objects = [
  { factory = adapter
    args = { factory.name = api.alsa.pcm.sink
             node.name = "alsa_speaker"
             node.description = "MT6358 speaker"
             media.class = "Audio/Sink"
             api.alsa.path = "hw:0,0"
             api.alsa.period-size = 1024
             audio.position = [ FL FR ] } }
]
```

**3. Микшер на загрузке.** `/usr/local/bin/t1100-audio-mixer.sh` ждёт
`/dev/snd/controlC0` и выставляет `ADDA_DL_CH1 DL1`, `ADDA_DL_CH2 DL1`,
`DAC In Mux = Normal Path`, `HPL/HPR Mux = LoudSPK Playback`;
`t1100-audio-mixer.service` (oneshot, `RemainAfterExit=yes`,
`WantedBy=multi-user.target`).

**Проверено после перезагрузки:** `t1100-audio-mixer.service` active,
`pipewire`/`wireplumber` active, в Sinks `32. MT6358 speaker` и
`49. Built-in Audio Internal speaker`; `pw-play /tmp/tone.wav` — слышно тон.

**Инструменты** (`rawplay`, `ctlroute`, `ctlenum`) лежат в `/usr/local/bin`;
исходники — `tools/device/` (статическая сборка на build-хосте:
`aarch64-linux-gnu-gcc -O2 -static <src>.c -o <bin>`).

### 12.11 (15): микрофон — путь найден (AIN1), сигнал пока нулевой

> **Уточнено 13.11:** сигнал был нулевым не из-за AIN1/кодека, а потому что
> DAPM-маршрут `UL1 -> ADDA` был выключен. Рабочая конфигурация — `PGA L/R
> Mux = AIN0`; см. `13.11 (6)` ниже.

Захват заводится как отдельный узел PipeWire (`api.alsa.pcm.source` на `hw:0,1`,
`/etc/pipewire/pipewire.conf.d/52-alsa-mic.conf`), Source виден в `wpctl`.
Маршрут для аналогового микрофона: `Mic Type Mux=ACC`, `PGA L/R Mux=AIN1`,
`ADC L/R Mux=Left/Right Preamplifier`, `AIF Out Mux=Normal Path`,
`UL1_CH1/CH2 ADDA_UL=on`, `PGA Volume=4` (+24 дБ).

**Факты с железа.** Перебор входов (по 9 с, пользователь говорил):
`ACC+AIN0` peak 1345, **`ACC+AIN1` peak 23100 (реальный сигнал)**, `ACC+AIN2`
peak 1024, `DMIC+AIN0` peak 0. То есть микрофон сидит на **AIN1**.

**Проблема.** Повторить успешный замер не удаётся: все последующие записи
(3×7 с, 15 с с переключением mux на ходу) дают `peak 0, rms 0`, при этом
dmesg показывает корректный `mt6358_amic_enable(), mux, mic 1, pga l 1, pga r 1`.
Гипотеза: в mainline `mt6358.c` ветка ACC не поднимает MICBIAS/`mtkaif` так,
как это делает ветка DMIC (`mt6358_dmic_enable()` ставит MICBIAS0=1P9V), либо
порядок `mt6358_restore_pga()`/`AFE_UL_SRC_CON0` не совпадает с вендорским.
Нужен разбор `mt6358_amic_enable()` против вендорского `mt6358_codec.c`.

**Инструменты:** `/usr/local/bin/{rawplay,ctlroute,ctlenum,ctlset}` (исходники —
`tools/device/`), запись `pw-record --target <mic-node> --rate 48000 --channels 2`.

### 12.11 (16): перенос ручных установок в образ rootfs

Пакеты, поставленные на планшете вручную, зафиксированы, чтобы попадать в
новую сборку rootfs:

- `configs/rootfs-packages.txt` — по одному аргументу apt на строку
  (клавиатура Plasma, kate/ark/gwenview/okular/kcalc/spectacle, language-pack-kde-ru,
  qmmp, htop/btop/wget/gcc, systemd-timesyncd). Строка `local:ai.storyteller`
  помечает четыре локальных пакета (cadcraft/gridcraft/photocraft/wordcraft,
  ~364 МБ) — они в git не кладутся, берутся из `$LOCAL_DEB_DIR`.
- `scripts/rootfs-extra-packages.sh` — ставит список в chroot собранного rootfs
  (или на устройстве): `apt-get update`, затем `apt-get install -y
  --no-install-recommends <строка>`; для `local:ai.storyteller` — `apt-get
  install -y $LOCAL_DEB_DIR/*.deb` (по умолчанию `/root/Downloads/arm`).

Также на планшете теперь есть интернет по USB (NAT на ноутбуке, `default via
10.42.66.67`), поэтому apt работает и после перезагрузки достаточно вернуть
маршрут (или прописать шлюз в NM-профиле).

### 12.11 (17): экран блокировки — root не мог войти (PAM)

KDE-стек PAM в этом rootfs лежит в vendor-каталоге `/usr/lib/pam.d/`
(`kde`, `kde-fingerprint`, `kde-smartcard`), причём `kde` содержал

```
auth required pam_succeed_if.so user != root quiet_success
```

— правило, запрещающее вход root. Наш рабочий стол работает под root, поэтому
разблокировка всегда отклонялась (в journal: `requirement "user != root" not
met by user "root"`). Проверка `pamtester kde root authenticate` подтвердила
отказ, после удаления строки — «successfully authenticated».

**Что сделано:** очищенные файлы положены и в `/etc/pam.d/` (перекрывает
vendor-каталог), и в `/usr/lib/pam.d/` (чтобы правка пережила обновление
пакета); оба набора зафиксированы в `rootfs-overlay/`. Пароль root сменён на
`1` (по просьбе пользователя). Проверено на железе: блокировка →
`loginctl lock-session 2` → ввод пароля → «Пустило».

**Замечание по безопасности:** root-сессия и пароль из одного символа — это
временное решение для порта; в образе стоит завести обычного пользователя.

## 12.11 (11): смержены 6 новых коммитов (аудио/PAM/пакеты); оверлей разложен

**Merge.** `fast-forward` на `79d7ded`: патч **0057** (machine-driver
`mt6771-mt6358` + DTS-узел звука), `configs/t1100.fragment` (`SND_SOC_MT8183`,
`MT6358`, `MT6771_MT6358`), `rootfs-overlay` (UCM-профиль, pipewire/wireplumber
конфиги, автозапуск под root, mixer-скрипт, PAM `kde*` для root на экране
блокировки, `powerdevilrc`), `configs/rootfs-packages.txt` +
`scripts/rootfs-extra-packages.sh`, `tools/device/{ctlenum,ctlroute,rawplay}.c`.

**Что разложено на планшет:** весь `rootfs-overlay` (UCM
`/usr/share/alsa/ucm2/conf.d/mt6771-mt6358`, `/etc/pipewire`, `/etc/wireplumber`,
user-юниты с `90-allow-root.conf`, `/etc/pam.d/kde*`), `ctlenum/ctlroute/rawplay`
собраны статически под aarch64 (только заголовки `sound/asound.h`, без libasound)
и положены в `/usr/local/bin`, юнит `t1100-audio-mixer.service` включён и активен.

**Грабли (стоили доступа к плате).** Распаковка `rootfs-overlay` обычным
`tar -C / -xf -` сохраняет uid/gid репозитория (1000) → `/etc`, `/usr`, `/root`
становятся чужими, и **sshd с `StrictModes=yes` отказывает в ключе**
(`bad ownership or modes for directory /root`); пароль не спасает — root-логин по
паролю запрещён политикой. Лечение — из recovery `chown -R root:root` (сделано).
Для будущих раскладок добавлен `tools/host/deploy-overlay.sh`
(`tar --owner=0 --group=0 --numeric-owner` + `--no-same-owner` + chown).

**Звук пока не работает** (`/proc/asound/cards` пуст): в загруженном ядре нет
machine-driver из 0057 — сборка объединённого ядра (наш Wi-Fi DT + его аудио,
2 варианта: с включёнными `consys`/`wifi` и «безопасный» только с аудио) идёт
на build-хосте.

### 12.11 (12): объединённое ядро впервые загрузилось; звук работает; Wi-Fi — дубль символа

**Смержены 6 коммитов** (`79d7ded`): патч **0057** (machine-driver `mt6771-mt6358`),
SND-опции, `rootfs-overlay` (UCM/pipewire/PAM), список пакетов, `tools/device/*`.

**Объединённое дерево** собрано из патчей (`/home/l/t1100-merge2-src`, локально
воспроизводимо): 0001–0057, включая **0042** — именно её отсутствие ломало
прошлые образы: в DTB оставался `ramoops@70000000`, пересекавшийся с LK-резервацией
`ibc-reserved` → LK ассертил и уходил в цикл. Теперь DTB проходит валидатор
**с** `LK_EXTRA_RES=0x70000000:0x10000:ibc-reserved`. В дерево влит и **его драйвер
тача** (`sense_off`, reset 20 мс, без `reload_to_active`) — ровно тот, что работал
на `boot_merged12`.

**Прошито и загрузилось:**
- `build/boot_merge_audio_v2.img` (`860ae2b2…`, Wi-Fi-узлы выключены) — первый
  успешный запуск: `6.12.114-g400cb6f-touch-rot`, `nproc=8`, панель `connected`,
  тач `Himax`, **звуковая карта `mt6771-mt6358`**, Plasma/SDDM активны;
  **владелец слышал тестовый тон 440 Гц** (`pw-play`, sink `MT6358 speaker`),
  `mt6358_codec_dai_hw_params(rate 48000)` в dmesg;
- `build/boot_merge_audio_wifi_v2.img` (`d1e4a2e9…`, `consys`/`wifi` = okay) —
  тоже загрузился, `consys@18070000`/`wifi@180f0000` в живом DT присутствуют и
  включены, `consys-reserve-memory` есть; панель/тач/аудио целы.

**Wi-Fi M3 — первый шаг пройден:** `wmt_drv.ko` грузится
(`WMT-DETECT: driver(major 154) installed`). Следующий модуль падает:
`wlan_drv_gen3: exports duplicate symbol connectivity_export_show_stack (owned by
wmt_drv)` → `Exec format error`. Это наша заглушка `show_stack()` экспортируется
из обоих модулей; фикс (экспорт только в `wmt_drv`, в `wlan` — внешняя ссылка)
в работе.

**Инфраструктурная грабля** (см. 12.11 (11)): раскладка `rootfs-overlay` обычным
`tar` сохраняет uid 1000 и ломает `StrictModes` sshd; теперь есть
`tools/host/deploy-overlay.sh`.

### 12.11 (13): Wi-Fi M3 — дубль символа устранён, дальше `vendor_commands.policy`

1. **Дубль `connectivity_export_show_stack`** (наш стаб `show_stack()` был
   определён и экспортирован и в `wmt_drv`, и в `wlan_drv_gen3`):
   исправлено — экспорт остаётся только в `wmt_drv`, в `wlan` символ
   undefined и резолвится через `Module.symvers` (`patches/wifi`, коммит
   `c6ff83c`). Новый `wlan_drv_gen3.ko`: `796b4a32…`, 2 894 616 Б.
2. **Новый WARN в cfg80211:** `wiphy_register+0x524` →
   `net/wireless/core.c:999` = `WARN_ON(!rdev->wiphy.vendor_commands[i].policy)`.
   Вендорский `mtk_wlan_vendor_ops` (`gl_init.c`) не задаёт `.policy` — в 4.14
   `NULL` допускался, в 6.12 обязателен (для «raw data» есть сентинел
   `VENDOR_CMD_RAW_DATA = (void *)(long)(-ENODATA)`). Итог:
   `createWirelessDevice:(INIT ERROR) wiphy_register error`, init возвращает -1
   и модуль не вставляется. Фикс (vendor-команды отключаем на первом рубеже,
   они нужны только MTK-`iwpriv`) — в работе.

**Замечание по инструменту:** `wifi-deploy.sh --apply --load all` в одном
прогоне не положил новый `wlan_drv_gen3.ko` (на устройстве остался старый
`be1df2ac…`); пришлось копировать `scp` вручную. При следующем деплое смотрим
вывод `apply` целиком (scp идёт с `-q`, ошибки не видны) — возможно, стоит
добавить проверку sha256 после копирования.

### 12.11 (14): Wi-Fi — модули грузятся, `phy` создаётся; не хватает только файрмвари

Цепочка от «не вставляется» до «нет прошивки»:

1. `wlan_drv_gen3` падал на `wiphy_register` (WARN `vendor_commands[].policy`) —
   фикс: vendor-команды MTK отключены (они нужны только `iwpriv`), патч
   `patches/wifi/0002-wlan-port-6.12-vendor-commands.patch`, новый
   `wlan_drv_gen3.ko` `20e64fc0…`.
2. После фикса модуль **загружается**: `Create wireless device success`,
   `HifAhbPltmProbe`, `mtk_wcn_wmt_wlan_reg: wmt wlan cb register`,
   `initcall initWlan ... returned 0`; в `/sys/class/ieee80211/` появились
   `phy1`/`phy2` (AIS + P2P).
3. **Chip-type выставляет userspace** (как вендорский `wmt_loader`): сделан
   `tools/device/wmtctl.c` (static aarch64, ~150 строк, ioctl к `/dev/wmtdetect`):
   `detect` → `soc chip id: 0x6771`, `setid 0x6771` → `g_chip_type = SOC`,
   `init` → `COMBO_IOCTL_DO_MODULE_INIT` (`mtk_wcn_common_drv_init()`).
4. **`init` падает на отсутствии прошивки**:
   `Direct firmware load for WMT_SOC.cfg failed with error -2` →
   `wmt_conf_read_file fails` → `wmt_lib_init() fails (-1)` → `WMT_init:fail`,
   дальше deinit-путь дергает `platform_driver_unregister()` на
   незарегистрированном драйвере (WARN в `driver_unregister`, безвредно).

**Откуда взять файрмварь.** В rootfs её нет (и в 26.04-тарболе тоже), стоковый
`/vendor` — внутри динамического раздела `super` (`mmcblk0p49`, **6 ГБ**,
`blockdev --getsize64` = 6 442 450 944), который на планшете цел (мы стирали
только `p54`). `lpunpack` в apt нет, поэтому раздел снят целиком
(`/home/l/super_t1100.img`) и в нём ищется ext4-образ `vendor`; нужны
`WMT_SOC.cfg` (119 Б, sha256 `ea673ab1…cf32`) и `WIFI_RAM_CODE_6759`
(480 752 Б), плюс `mt6631_fm_v1_{patch,coeff}.bin` для FM.

### 12.11 (15): Wi-Fi — CONSYS поднялся, прошивка на месте; остался запуск WLAN-функции

**Что сработало:**
- `wmtctl setid 0x6771` → `g_chip_type = SOC`; `wmtctl init`
  (`COMBO_IOCTL_DO_MODULE_INIT`) вернул **успех**;
- CONSYS-платформа **пропробиндилась**: `CONNSYS EMI from DT: phys 0xbfc00000
  size 0x200000`, `Clearing Connsys EMI … 2097152 bytes`,
  `COREDUMP EMI mapping OK`, `probe of 18070000.consys returned 0`,
  `wmtd_thread starts`;
- файрмварь найдена и установлена на планшет: `super` (`mmcblk0p49`, 6 ГБ)
  оказался **бэкапом инсталлятора Aurora** (`root.img.gz` 1.2 ГБ + `home.img.gz`),
  внутри `root.img` → `/vendor/firmware/{WMT_SOC.cfg (119 Б, sha256 ea673ab1…),
  WIFI_RAM_CODE_6759 (480 752 Б), soc3_0_ram_*.bin, mt6631_fm_v1_*}` → скопированы
  в `/lib/firmware` планшета (`tar --owner=0 --numeric-owner`);
- `wlan_drv_gen3` грузится: `Create wireless device success`, `HifAhbPltmProbe`,
  `wmt wlan cb register`, `initWlan … returned 0`; есть `phy0`/`phy1`.

**Что осталось:** нет `wlan0` и не происходит WLAN power-on. В вендоре
`wlanProbe()` вызывается как колбэк после `wmt func on (WIFI)`; у нас
`/dev/wmtWifi` не создаётся (в gen3 он есть только в режиме
`CONF_HIF_DEV_MISC=1`, а у нас платформенный драйвер `mt-wifi` с
`of_match` по `wifi@180f0000`). Попытка `modprobe -r wlan_drv_gen3` → модуль
завис в `refcnt -1` (как `wmt_drv` раньше) — лечится только ребутом; это
известное слабое место вендорского кода при выгрузке.

**Следующие шаги (в порядке):**
1. Дать userspace-инструмент для nl80211: собрать статический `iw` (нужен
   libnl) и `iw phy phy1 interface add wlan0 type managed` — это дёргает
   `gl_cfg80211_add_iface` → `wlanNetCreate` → `register_netdev`, после чего
   `ip link set wlan0 up` инициирует power-on и загрузку `WIFI_RAM_CODE_6759`;
2. либо включить `CONF_HIF_DEV_MISC=1` (тогда появится `/dev/wmtWifi` и
   power-on можно дёргать ioctl'ом) — но это меняет путь пробинга;
3. после появления `wlan0`: `wpa_supplicant` + DHCP = DoD фазы 5.

## 12.11: итог сессии (продолжение в новой сессии)

**Состояние планшета на конец сессии** (проверено по SSH):
```
p29 sha256 : d1e4a2e976b793fe…44c43   (build/boot_merge_audio_wifi_v2.img)
uname      : 6.12.114-g400cb6f-touch-rot, nproc 8
rootfs     : Ubuntu 26.04 LTS + KDE Plasma 6.6.4 (SDDM active)
экран      : card1-DSI-1 connected; тач Himax в event1
звук       : 0 [mt6771mt6358] mt6771-mt6358, тестовый тон 440 Гц слышен
файрмварь  : /lib/firmware/{WMT_SOC.cfg, WIFI_RAM_CODE_6759, soc3_0_ram_*, mt6631_fm_*}
модули     : wmt_drv/wlan_drv_gen3 сейчас НЕ загружены (после ребута)
```

**Что сделано за день**
1. Смержены 12+6 коммитов второго разработчика (fast-forward): панель (0046,
   0052), тач (0050/0051), Plasma Keyboard, аудио (0057), PAM, packages list.
2. Собрано объединённое дерево из патчей 0001–0057; **найдена причина прошлых
   «LK crash»**: `ramoops@70000000` пересекался с LK-резервацией `ibc-reserved`
   (не был применён 0042). Валидатор теперь прогоняется с
   `LK_EXTRA_RES=0x70000000:0x10000:ibc-reserved`.
3. Прошит `boot_merge_audio_wifi_v2.img` — работает всё: панель, тач, **звук**
   (machine-driver + UCM/pipewire), 8 ядер.
4. Развёрнут rootfs второго разработчика (Ubuntu 26.04 + Plasma) с его
   оверлеем; восстановлен доступ (ключ) и, отдельно, испорченный ранее
   `/etc/shadow` (`root:HASH` → валидный yescrypt, пароль `0`).
5. Wi-Fi: см. (13)–(15) — модули грузятся, CONSYS поднимается, файрмварь на
   месте; остался запуск WLAN (нужен `wlan0` через nl80211).

**Грабли, которые записаны в этой сессии**
- `tar` оверлея с uid 1000 → sshd `StrictModes` отказывает в ключе
  (`deploy-overlay.sh` теперь ставит `--owner=0 --numeric-owner` + chown);
- сломанный `sed` с `$HASH` записал литерал `HASH` в `/etc/shadow` — пароль
  root перестал работать, лечится `chpasswd`; проверять
  `getent shadow root | cut -d: -f2`;
- `rmmod` вендорских модулей (`wmt_drv`, `wlan_drv_gen3`) зависает
  (`refcnt -1`) — только ребут;
- `super` на этой плате — **бэкап инсталлятора Aurora** (`root.img.gz` +
  `home.img.gz`), а не Android-раздел: файрмварь Wi-Fi лежит в `root.img.gz`.

**Следующая сессия:** (1) статический `iw` (libnl) или `CONF_HIF_DEV_MISC=1`
→ `wlan0` → wpa_supplicant/DHCP; (2) `libinput` + проверка тача в Plasma;
(3) DVFS GPU; (4) закрепить порядок загрузки модулей Wi-Fi юнитом
(`t1100-wifi.service` уже есть, не включён).

## 12.11 (18): Wi-Fi M6 — nl80211 интерфейс не создаёт; probe упирается в окно CONNSYS

Рубеж M6 (`wlan0` + скан) **не взят**. Сделано и проверено на железе:

- **`iw` собран** статически (`scripts/build-iw-aarch64.sh`: libnl 3.11.0 + iw 6.9),
  `build/tools-aarch64/iw`, sha256 `c4d68b70…b81374`, 1 267 888 Б, `NEEDED` = 0;
  на планшете `/usr/local/bin/iw`, `iw version 6.9`.
- **nl80211-путь закрыт драйвером**: `iw phy phy0 interface add wlan0 type managed`
  → `Operation not supported (-95)`, потому что в `mtk_wlan_ops` (`gl_init.c:261`)
  нет `.add_virtual_intf` (у P2P закомментирован). Вывод 12.11 (15) «интерфейс
  создаёт userspace через nl80211» — неверен; его создаёт `wlanProbe()` из
  колбэка WMT «func on (WIFI)».
- **Колбэк недостижим без STP**: `opfunc_pwr_on` → `wmt_core_stp_init` требует
  `WMT_OP_HIF_BIT` и STP-транспорт, а uart/sdio — заглушки (`-ENOSYS`), отсюда
  `-3` и `func(3) pwr_on fail`.
- **Обход (патчи `0003-wlan-t1100-probe-param`, `0004-common-export-wmt-plat-pwr-ctrl`)**:
  `modprobe wlan_drv_gen3 t1100_probe=1` сам питает чип (`wmt_plat_pwr_ctrl(FUNC_ON)`,
  `CONSYS-HW-PWR-ON, finish(0)`) и зовёт `wlanProbe()`. netdev создаётся, но
  обмена с HIF нет: `sdio_open: Enable function failed, error -62`,
  `nicpmSetDriverOwn: LP fail … cpupcr:00000000` → `wlanProbe failed`, драйвер
  остаётся загруженным (`phy0`/`phy1` есть), `wlan0` не регистрируется.
- **Осторожно:** вариант с `HifAhbProbe()` (с rollback `pfWlanRemove()` на ошибке)
  **вешает ядро** (sshd не отвечает, ping идёт) — лечится только Power 10 с.
  Поэтому rollback убран: провал probe теперь только пишется в лог.

Итог: следующий шаг — регистровая видимость окна CONNSYS (`mmap`-`/dev/mem`,
`0x18070008`/`0x180f0000` до и после power-on) и сверка SPM-последовательности
`mt6771.c:consys_hw_power_ctrl()` с вендорской (вопрос к `bringup`);
подробности — `docs/wifi-port-log.md` §26.

## 12.11 (19): Wi-Fi M7 — окно CONNSYS ожило, причина найдена (bringup)

**Диагноз доказан, `wlan0` пока нет.** Окно `0x18070000`/`0x180f0000` молчало
не из-за питания/регулятора, а из-за двух вещей в вендорском коде
(`refs/consys-regs-2026-11-12.md` — сырые дампы до/после):

1. `CONSYS_PWR_ON_OFF_API_AVAILABLE` для mt6771 равно **1**, а не 0 (как было
   записано в §26.4): единственное действие power-on —
   `clk_prepare_enable(clk_scp_conn_main)`; клока `conn` в mainline нет
   (патч 0002 сделал lookup необязательным), а `clk_enable(NULL)` — успешный
   no-op. Поэтому `CONSYS-HW-PWR-ON, finish(0)` ничего не включал:
   `0x1000632c = 0x112` (iso=1, clk_dis=1, pwr_on=0), `0x10006180 = 0x008fff4c`.
2. Ручная SPM-ветка вендора снимает CONN AXI-protect через «read & ~mask» по
   `0x100012a4`, а это **write-1-to-clear** зеркало `0x100012a0` — protect
   остаётся, окно читается нулями, а запись в него встаёт намертво.

Сделан патч **`patches/wifi/0005-common-consys-spm-power-on.patch`**:
SPM-последовательность с таймаутами как fallback при отсутствии клока `conn` +
корректное снятие protect (`0x100012a0` RW / `0x100012a4` W1C). После неё:
`0x18070008 = 0x00000788` (chip id!), `0x180f000c = 0xa07f0000` (WFDMA),
запись ROM-deselect проходит. Модули собраны и лежат на планшете
(`wmt_drv.ko` `de80dcce…`, `wlan_drv_gen3.ko` `2a6d8c5b…`).

**Новый риск, важный для следующего шага:** с живым доменом
`modprobe wlan_drv_gen3 t1100_probe=1` **вешает ядро наглухо** (нет ping/sshd/
USB-gadget, авторебута нет) — нужен Power 10 с. Устройство на момент отчёта
недоступно. Лог прогона — `/root/wifi-test.log` на планшете. Не запускать probe
вслепую: сначала пошаговый параметр (`t1100_probe_stage=N`), затем смотреть,
какой первый MMIO клока не имеет (WFDMA/`wifi-dma`, AFE `0x180b6000`,
EMI-MPU). Подробности — `docs/wifi-port-log.md` §27.

## 12.11 (20): Wi-Fi M7 взят — окно CONNSYS отвечает; драйвер доходит до прошивки

**Рубеж M7 закрыт.** С патчем 0005 CONSYS реально включается:
`consys_hw_power_ctrl_spm: CONN SPM power on: 0x10d/0x408fff4e/0x18600098`,
`polling_consys_chipid: retry(8) consys chipId(0x00000788)`,
`nicpmSetDriverOwn: DRIVER OWN, status=1 count=25` (HIF-хендшейк!),
`nicInitializeAdapter: Chip ID[6771] Version[E1]`,
`kalFirmwareOpen: WIFI_RAM_CODE_6759 success` → `FW download end` →
`Waiting for Ready bit timeout, Device to Host MailBox 0x38`, `cpupcr:00015730`
(MCU исполняет код). Не хватает только `WLAN_READY` от прошивки.

**Причина «смерти ядра» после probe найдена**: `wlan_lib.c:633` на таймауте
ready-бита вызывает `GL_RESET_TRIGGER` → `schedule_work(rst_trigger_work)`, а
`INIT_WORK` для него делается в `glResetInit()`, который `initWlan()` вызывал
**после** probe → вызов NULL в kworker. Патч **0006** переносит `glResetInit()`
до probe, добавляет `t1100_no_reset=1` и `t1100_probe_stage` (1 = только
питание, 2 = питание + probe). Прогон `stage=1` безопасен, плата жива.

**Питание/клоки закрыты** (`refs/consys-regs-2026-11-12.md` §7):
`vcn18`/`vcn28`/`vcn33_bt` включены консьюмерами `18070000.consys-*`;
`vcn33_wifi` = 0 мВ (`consys_hw_wifi_vcn33_ctrl()` под `#if 0`) — нужен только
для TX; гейт `infra_cqdma` (DTS `wifi-dma`) никем не взят и для окна WFDMA не
нужен — правка DTS не потребовалась.

**Новый блокер:** на `stage=2` oops в `wlanNetCreate` (`gl_init.c:1791`,
`netif_tx_stop_all_queues`, запись в read-only адрес) → SIGSEGV и ребут, ядро
не висит. Похоже на latent-порчу памяти, чувствительную к раскладке (на сборке
0005 этот же шаг проходил). Следующий шаг: `slub_debug=U,F` + печать
`dev/num_tx_queues/_tx` в `wlanNetCreate`, сверка `sizeof(GLUE_INFO_T)` с
размером wiphy priv.

## 12.11 (21): Wi-Fi M8 — причина oops в `wlanNetCreate` найдена: сборка против чужого out-дерева

**Корень найден и устранён.** Модули собирались против
`/home/l/t1100-ubuntu-build/out-normal`, а на плате крутится ядро из
**`/home/l/t1100-merge2-out`**; конфиги расходятся на 23 строки, и ключевая —
`CONFIG_WIRELESS_EXT`: она добавляет в `struct net_device` два указателя и
сдвигает все последующие поля на 16 байт. Поэтому `dev->num_tx_queues`
читался как 0 (ядро пишет 4 в `net/core/dev.c:11393`), а ядро в
`netif_tx_stop_all_queues()` (`dev.c:10518`) уходило циклом по мусору и писало
в rodata — `pc: netif_tx_stop_all_queues+0x2c`, как в STATUS 12.11 (20).
Печать полей это подтвердила: `type=1 mtu=1500 real=4`, но `num_txq=0`.

Сделано: вендорские **и** ядерные модули (`cfg80211`/`mac80211`/`rfkill`/
`libarc4`) пересобраны против `merge2-out`
(`KERNEL_OUT=/home/l/t1100-merge2-out … scripts/build-wifi-remote.sh`), в
`scripts/remote/build-wifi-remote.sh` добавлен отказ собирать без
`CONFIG_WIRELESS_EXT=y`. Артефакты: `wlan_drv_gen3.ko` `4de6e1d9…92ed69`,
`wmt_drv.ko` `de80dcce…b3817`, `cfg80211.ko` `76a90f08…`.

**Прогон теперь чистый** (oops нет, ребута нет): chip id `0x788`, DRIVER OWN
OK, FW download end, reset подавлен `t1100_no_reset=1`. `wlan0` **нет** —
единственный блокер остался прежний: прошивка не выставляет `WLAN_READY`
(`WCIR 0x18070038 = 0`, mailbox `0x18070078 = 0x55aa`, `cpupcr` живой).

## 12.11 (22): Wi-Fi M8 — READY не встаёт: MCU сидит в ROM, MPU и ROM-patch не реализованы

Диагноз уточнён (см. `docs/wifi-port-log.md` §30). Окно MCR —
`of_iomap(of_node, 0)` = **0x180f0000** (`ahb.c:293`), `MCR_WCIR = 0`
(`mt6630_reg.h:79`), `WCIR_WLAN_READY = BIT(21)`; измерено
`0x180f0000 = 0x1000f004` → READY = 0 (а `0x180f0004 = 0x38` — это то самое
«MailBox 0x38» из лога, не адрес).

Главное: **MCU не исполняет прошивку**. `cpupcr` (`0x18070160`) стоит в tight
loop `0x1572a…0x15730`, а `0xbfca5800` (EMI base + `0xA5800` = fw load addr из
DT) читается нулями; `CPUPCR` не в диапазоне прошивки. `FW download end`
ничего не доказывает: `CFG_ENABLE_FW_DOWNLOAD_ACK=1` отключает
`wlanImageQueryStatus()`.

Не реализованы два куска: (1) EMI MPU — обе реализации
(`plat_priv.c:70`, `mt6771.c:991`) под `#ifdef CONFIG_MTK_EMI`, которого в
mainline нет, а `mt_emi_api.h` в compat — пустая заглушка (политика регионов
25/26 известна из вендорских исходников, неизвестна раскладка регистров);
(2) ROM-patch — в `mt6771.c` его нет вовсе, тогда как `mt6765.c`/`mt6761.c`
зовут `consys_dl_rom_patch()` → `mtk_wcn_soc_rom_patch_dwn()`, и данные патча
кладутся в EMI через `osal_memcpy_toio()` (не по STP).

`wlan0` нет. Модули: `wlan_drv_gen3.ko` `4de6e1d9…92ed69`, `wmt_drv.ko`
`de80dcce…b3817` (собраны против `merge2-out`). Прогоны — только с
`t1100_no_reset=1 t1100_probe_stage=3`, плата жива.

## 12.11 (23): Wi-Fi M9 — прошивка легла правильно, но MCU остаётся в ROM

Печать таблицы секций (патч 0007, `wlanImageDividDownload`): 4 секции —
`0x020a1000`/28032 и `0x000a5800`/33776 идут «direct to chip» (MCIF), а
`0xf0000000`/342320 и `0xf0055000`/76512 — в EMI по `&0xfffff`, т.е. `EMI+0` и
`EMI+0x55000`. Проверка `mempeek` совпала с файлом байт в байт
(`0xbfc00000` = файл@0x0f1c8, `0xbfc55000` = файл@0x62af8) → **образ ложится
правильно**, адрес `0xA5800` из DT — это dest секции 1 (память MCU), а не EMI.

Остаётся старт: `cpupcr` до/после = `0x15730`/`0x1572a` (петля ROM),
`WCIR 0x180f0000 = 0x1000f004` (READY бит21 = 0). Гейт `infra_cqdma`
(=`wifi-dma`) раньше был выключен (`enable=0, deviceless`) — в патче 0007
включается в `HifDmaInit()` (`ret=0 rate=156000000`, в `clk_summary` теперь
`enable=1`, consumer `180f0000.wifi`), но READY это не изменило: гейт был
выключен, однако не был блокером.

Стокового baseline по `soc3_0_ram_*` нет: `dmesg-stock.txt.gz` обрывается на
`wmt_core_stp_init: no hif info!`. Следующий шаг: проверить, что
`wlanImageSectionConfig()/Download()` и `wlanConfigWifiFunc()` (WIFI_START, его
return игнорируется) реально доходят до MCU, затем ROM-patch по образцу
`mt6765.c` с `soc3_0_ram_mcu_e1_hdr.bin`. `wlan0` нет.

## 12.11 (24): Wi-Fi M10 — MCIF исправен, `WIFI_START` шёл без адреса старта

Дамп MCR-страницы `0x180f0000` до/после команд и return-коды: `section-config`
→ `status=0` дважды, причём этот статус = ответ MCU на `INIT_EVENT_ID_CMD_RESULT`
(`CFG_ENABLE_FW_DOWNLOAD_ACK=1`), и `WASR (0x20)` меняется `0x10200 -> 0x200`.
**Команды доходят до MCU, MCIF исправен.**

`WCIR (0x00) = 0x00100788` — chip id `0x788` совпадает с DT, `WLAN_READY`
(бит21) = 0 всегда. Причина: `include/config.h:569`
`CFG_OVERRIDE_FW_START_ADDRESS 0` → `wlanConfigWifiFunc(prAdapter, FALSE, 0)`,
т.е. чипу говорили «стартуй по умолчанию», а адрес из DT
(`hardware-values[2] = 0xa5800`) не передавался. Патч **0008** включает
override: теперь `WIFI_START override=1 addr=0x000a5800 seq=3 -> status=0`,
но READY всё равно 0 (`cpupcr 0x1572a`) → нужен ROM-patch.

Гейт `wifi-dma` (`infra_cqdma`) с патча 0007 включён (`enable=1`, 156 МГц).
`wlan0` нет.

## 12.11 (25): Wi-Fi M11 — ROM-patch записан в EMI, но MCU его не подхватывает

Формат: `struct wmt_rom_patch` (48 Б) + тело, `soc3_0_ram_mcu_e1_hdr.bin`
(165 344 Б) → `ucPLat="ALPS"`, Hw/Sw `0x108a`, **`u4PatchAddr = 0xf0000000`**
(пространство MCU/EMI, как у секций прошивки), `u4PatchType = 0x4000000`,
тело 165 296 Б; файлы `*_mcu_{e1,1_1,1a_1}_hdr.bin` идентичны. Вендор берёт имя
и адрес из userspace (`wmt_ctrl_ul_cmd("srh_rom_patch")` → `wmt_loader`), в нашем
`WMT_SOC.cfg` этой секции нет, `mt6771.c` шаг не вызывал.

Сделан патч **0009**: `consys_dl_rom_patch()` читает файл, разбирает заголовок и
кладёт тело в EMI+0 (`osal_memcpy_toio`), вызов из `polling_consys_chipid()` как
в `mt6765.c:681`. На железе патч **записался** (readback совпал), но
`cpupcr = 0x15730`, `WCIR = 0x1000f004` (READY=0) — MCU к этому моменту уже
вышел из сброса и патч не читает. Следующий шаг: перенести запись внутрь
`consys_hw_power_ctrl_spm()` между снятием изоляции и снятием сброса.
`wlan0` нет.

## 12.11 (26): Wi-Fi M12 — ROM-patch перед сбросом MCU; старт всё равно в ROM

Патч **0010**: запись ROM-patch перенесена внутрь `consys_hw_power_ctrl_spm()` —
между снятием изоляции (`~CONSYS_SPM_PWR_ISO_S_BIT`) и снятием сброса
(`| CONSYS_SPM_PWR_RST_BIT`), плюс печать `cpupcr` сразу/+50/+100 мс.
Поэтому патч теперь гарантированно в EMI (`rompatch: EMI 0xbfc00000 readback
0000dbb0 00018830 …`) до выхода MCU из сброса.

Результат: `cpupcr` сразу после сброса и через 100 мс = `0x00000000`, позже в
probe `0x15730/0x1572a` (ROM-петля); `WCIR 0x180f0000 = 0x1000f004` (READY=0),
`0x18070008 = 0x788`, hang-debug `0x18070400/404/408 = 0`. Значит MCU патч не
принимает (смещение/проверка версии в заголовке). Дальше — RE стокового
`wmt_loader`/ROM (таблица `addRess[]` для `srh_rom_patch`). `wlan0` нет.

## 12.11 (27): Wi-Fi M13 — `rom_desel` не виноват; MCU стартует из ROM

`rom_desel` у MT6771 — прямая запись `0x001702a4` в `0x18070600`
(`mt6771.h:132` `CONSYS_ROM_DESEL_MASK = (0x17<<16)|0x2a4`), без DT/конфига.
Патч **0011** перепрошивает его уже после снятия CPU SW reset и печатает `cpupcr`:
`ROM_DESEL=0x001702a4` читается обратно (прежние `0x0` в логе были артефактом
момента чтения), `cpupcr` сразу после сброса `0x0`, через 20 мс — `0x1170`,
в probe — `0x15730`. Оба адреса ниже RAM-образа (`0xa5800`), т.е. MCU исполняет
ROM. `WCIR 0x180f0000 = 0x1000f004` (READY=0), `wlan0` нет.

Т.е. ни `rom_desel`, ни ROM-patch в EMI не дают RAM-загрузки. Следующий
кандидат — EMI MPU (нет доступа MCU к EMI; нужна публичная раскладка регистров),
реверс `srh_rom_patch` — после него.

## 12.11 (28): Wi-Fi M14 — клок CONN main в исходниках не найден; SPM `PWRON_CONFG` не гейт

Клок CONN main у MT6771 — это `clocks = <&scpsys 2>` (`mediatek,scpsys` @
`0x10001000`, стоковый DT), в драйвере `devm_clk_get(dev, "conn")`. Самого
провайдера (`clk-mt6771.c`/`mt_scpsys.c`) в нашем дропе нет, поэтому **регистр и
бит неизвестны** — не выдумываем.

Единственное задокументированное вендором место — пустая
`consys_hw_spm_clk_gating_enable()` с комментарием
`PWRON_CONFG_EN 0x10006000 32'h0b160001`; патч 0012 пишет это значение, и
железо принимает только бит0 (`0x00000003 -> 0x00000001`), т.е. это не гейт
CONN main. `cpupcr` без изменений: `0x1170` (+20 мс) → `0x1572c` (probe),
`WCIR = 0x1000f004` (READY=0), `wlan0` нет.

EMI MPU (гипотеза B) не делал: нужна публичная раскладка регистров, это
следующий шаг.

## 12.11 (29): Wi-Fi M15 — клок CONN main = тот же `SPM+0x32C`, гипотеза A закрыта

По публичному дереву (`Hadenix/android_kernel_alps-4.4` @ `e73397b5…`,
`drivers/clk/mediatek/clk-mt6771-pg.c`, выдержка в `refs/mt6771-scpsys/`):
`CONN_PWR_CON = SPM_REG(0x32C)` (pg.c:189), `CONN_PWR_STA_MASK = BIT(1)`
(pg.c:379) — т.е. вендорский `clk_prepare_enable("conn")` пишет **ровно
`0x1000632c`** и читает статус в `0x10006180` бит1, как и наш
`consys_hw_power_ctrl_spm()`. Отдельного infracfg/scpsys-гейта у CONN нет
(`bus_prot_mask = 0`, `sram_pdn_bits = 0`); bus protect — отдельный API
`spm_topaxi_protect()` (наши биты 13/14 в `0x100012a0`).

Значит недостающего клока CONN нет, гипотеза A закрыта; `cpupcr` по-прежнему
`0x1170` → `0x1572c`, `WCIR = 0x1000f004` (READY=0), `wlan0` нет. Следующая —
гипотеза B (EMI MPU) с публичной раскладкой регистров.

## 12.11 (30): Wi-Fi M16 — EMI MPU: публичной раскладки для MT6771 нет

В публичном дереве (`Hadenix/alps-4.4` @ `e73397b5…`) EMI MPU есть **только для
MT6739**: `EMI_MPU_CTRL 0x0`, `SA0 0x100`(+region*4), `EA0 0x200`,
`APC0 0x300`(+region*4+(domain/8)*0x100), `CTRL_D0 0x800`,
`EMI_MPU_REGION_NUMBER 24`, `EMI_MPU_DOMAIN_NUMBER 8`,
`SET_ACCESS_PERMISSON(lock,d7..d0)` — 3 бита/домен (выдержка в
`refs/emi-mpu-mt6739-layout.txt`). Вендорский MT6771 использует регионы **25/26**
и **16 доменов** — другой вариант блока, поэтому реализацию не делал (аналогия
вместо факта запрещена).

Baseline с устройства: `0x1020e000 = 0x01004000`, `0x1020e004 = 0x00004000`,
`0x10217000 = 0`, `0x10219000 = 0xf053f154`. `cpupcr` по-прежнему `0x1170` →
`0x1572c`, `WCIR = 0x1000f004` (READY=0), `wlan0` нет. Следующий шаг — взять
`emi_mpu` v2 (32 региона/16 доменов) из публичного mt6771/mt6765 4.14 (Realme,
см. `docs/research.md`) и реализовать регионы 25/26.

## 12.11 (31): Wi-Fi M17 — EMI MPU v2: раскладка есть, база не подтверждена

Найдена раскладка нужного варианта (`nokia-dev/android_kernel_nokia_mt6771`,
`drivers/misc/mediatek/emi_mpu/mt6758/emi_mpu.h`, выдержка в
`refs/emi-mpu-v2-mt6758-layout.txt`): **32 региона / 16 доменов**,
`EMI_MPU_CTRL 0x0`, `SA0 0x100`(+region*4), `EA0 0x200`, `APC0 0x300`
(+region*4+(domain/8)*0x100), `CTRL_D0 0x800` — совпадает с тем, что использует
вендор MT6771 (регионы 25/26, 16 доменов).

Базу блока подтвердить пока нельзя: в стоковом DT MT6771 узла `emi_mpu` нет,
рядом только `infracfg@1020e000` и `emi@10219000`; дампы `0x1020e000 =
0x01004000`, `0x10217000 = 0`, `0x10219000 = 0xf053f154`. Следующий шаг —
прочитать `emi_mpu_init()` в mt6758-драйвере (откуда берётся база) и только
потом писать регионы 25/26. Реализацию не делал, чтобы не угадывать.
`cpupcr`/`WCIR`/`wlan0` без изменений.

## 12.11 (32): Wi-Fi M18 — EMI MPU пишется только из secure world (SMC), не блокер

Публичный `mt6758/emi_mpu.c` (выдержка — `refs/emi-mpu-smc-arm64.txt`): на ARM64
`emi_mpu_set_region_protection()` идёт через `emi_mpu_smc_set()`, база —
`mt_emi_mpu_base_get()`/`CEN_EMI_BASE`. Т.е. APC/SA/EA пишет secure world
(LK/ATF), Linux туда ходит SMC-вызовом.

Дамп из NS-мира (`0x1020e000`): `CTRL = 0x01004000`, `DBG = 0x00004000`, а
SA/EA/APC регионов 25 и 26 (`0x164/0x168`, `0x264/0x268`, `0x364/0x368`,
`0x464/0x468`) и `CTRL_D0` (`0x800`) читаются как 0. LK стоковый и не менялся,
регион CONNSYS сконфигурирован им ⇒ **EMI MPU не блокер** и из Linux не
настраивается. Гипотеза B закрыта; дальше — M19 (порядок DLM/ILM → `WIFI_START`).
## 12.11 (33): Wi-Fi M19 — порядок сбросов вендорский; WCIR разложен, chip-id не тот

Сверка кода: и у вендора, и у нас AP_RGU `0x10007018[12]` снимается **после**
ROM_DESEL и ROM-patch (патч 0010 пишет патч внутри `consys_hw_power_ctrl_spm()`),
т.е. «отпускаем CPU рано» не подтверждается; лишняя перезапись ROM_DESEL из 0011 —
косметика.
`WCIR (0x180f0000) = 0x1000f004`: биты 28, 15..12, 2; `WCIR_CHIP_ID[15:0] = 0xf004`
(не `0x788`!), `WLAN_READY(BIT21) = 0`. Chip-id в этом окне не совпадает с DT/
`0x18070008` ⇒ под вопросом сама идентификация окна WCIR для MT6631; проверять
следующим узким шагом вместе с формой `WIFI_START` (seq/ack) и
`wlanImageQueryStatus`.

## 12.11 (34): Wi-Fi M20 — MCR-окно верное, вопрос был в дампе; ROMv4-патч идёт по STP

Гипотеза «READY читается не из того регистра» **закрыта**. В `ahb_sdioLike`
регистры MCU не memory-mapped: `sdio_cr_readl()` (`sdio_bus_driver.c:107`)
пишет слово CMD53 в `0x180f0000+0x0` и читает ответ из `+0x1000`, а
`HAL_MCR_RD` (`hal.h:214`) идёт именно этим путём. Поэтому `0x1000f004` из §40 —
это leftover командного слова (func=1, `addr=0x78` = mailbox 0, count=4, read),
а не chip-id. Замер в одном прогоне: настоящий `WCIR=0x00100788` (chipid 0x788,
POR=1, READY=0), сырое `0x180f0000` = 0 ⇒ READY действительно не встаёт.

`wlanImageQueryStatus()` (раскрыт из `#if !CFG_ENABLE_FW_DOWNLOAD_ACK`) вернул
**0 = ok**: MCU считает образ принятым. `WIFI_START` с `0xa5800` и `0x020a1000` —
оба `status=0`, `cpupcr` уходит с `0x1572a` в `0x700…0x18000` (ROM), READY=0
⇒ адрес старта не блокер, MCU не уходит в RAM-код.

Ключевое: для chip-id `0x788` вендор качает ROM-патч **по STP**
(`mtk_wcn_soc_normal_patch_dwn()`, `wmt_ic_soc.c:2753`: для `0x0788` — «ROMv4
patch RAM base» + фрагменты `WMT_PATCH_CMD` через `wmt_core_tx`), а не в EMI;
EMI-путь — механизм mt6765/6761, в `mt6771.c` такого шага нет. Значит патч
0009 (EMI+0) не вендорский; файла `ROMv4_be_patch_1_0_hdr.bin` (229 384 Б) в
нашем наборе нет. Код: накопительные 0009…0012 заменены одним
`0009-common-mt6771-consys-rompatch.patch` (убраны перезапись `ROM_DESEL` после
сброса и `PWRON_CONFG_EN`), добавлен `0009-wlan-query-status-and-two-start.patch`.
Модули `f862e768…c91c63` / `6465d6b1…bcbe7262`, oops нет, плата жива, `wlan0` нет.
Подробности и следующий шаг (STP over MCR `WTDR1 0x34`) — `docs/wifi-port-log.md` §41.

## 12.11 (35): Wi-Fi M21 — ROMv4-протокол разобран, транспорт = BTIF (не MCR)

Патч `ROMv4_be_patch_1_{0,1}_hdr.bin` доставлен быть не может через MCR-порты:
STP на MT6771 идёт через **BTIF** (`CONFIG_MTK_BTIF=y`, `btif@1100c000`,
`hifType=0x2` в логе стока, `stp_btif.c:80` → `mtk_wcn_btif_open()`), а
AHB-порт `0x180f0000` отдельного пространства STP-функции не даёт — проверено
read-only CMD53 по func 0/1/2: `CTDR/CRDR` (0x18/0x1c) = 0, `CHISR/CHLPCR` не
отвечают, func=2 по адресу 0 возвращает тот же `WCIR`. Драйвера `mediatek,btif`
в mainline 6.12 нет.

Протокол из исходников зафиксирован: `WMT_PATCH_ADDRESS_CMD` (для `0x0788` —
«ROMv4 patch RAM base», `[8..9]=0x18/0x05`), `WMT_PATCH_P_ADDRESS_CMD`
(`0x7c/0x0b` + адрес из userspace), фрагменты `WMT_PATCH_CMD` по 1000 Б с
флагами 1/2/3, ответы `WMT_PATCH_ADDRESS_EVT`/`WMT_PATCH_EVT`; имя файла
(1_0 vs 1_1) выбирает `wmt_loader`, не ядро.

EMI-путь (`soc3_0_ram_mcu_e1_hdr.bin` → `EMI+0`) выключен по умолчанию
(`t1100_emi_rom_patch=0`). Прогон stage=3: EMI-записи в логе нет, `section-config`
status=0 ×2, `wlanImageQueryStatus()=0`, `WIFI_START` c `0xa5800`/`0x020a1000`
status=0, `WCIR=0x00100788` READY=0, `wlan0` нет, oops нет. Модули
`71f9ffcc…c9020ef` / `02764d83…6523bdc`. Следующий рубеж — BTIF-транспорт WMT.
## 13.11 (1): GPU DVFS включён (0058/0059), high-OPP 698/743/800

- `0058-soc-mediatek-regulator-coupler-support-MT6771-and-MT8788.patch`:
  `mediatek_regulator_coupler_init()` разрешает `mediatek,mt6771`/`mt8788`.
- `0059-arm64-dts-t1100-enable-GPU-DVFS-with-a-safe-OPP-subset.patch`:
  возвращено наследование `gpu_opp_table`, удалены нижние OPP (остались
  698/743/800 МГц), добавлены взаимные `regulator-coupled-with` и
  `regulator-coupled-max-spread = <100000>` для VGPU/VSRAM, с VSRAM снят
  `regulator-always-on` (иначе `scpsys` power-on получал `-EPERM` от coupler).
- Образ `build/boot_gpudvfs10.img` sha256 `68c74d1e0a765c877244c1d6eb96278800829bdc9643332a1439ff38499f6bf0`,
  p29 md5 `d4cdc9ef563139034dda6afff98a6dbb`; Image `82c62a46…`, DTB
  `2dc07050…`; cmdline `maxcpus=8`.
- Проверено: `/dev/dri` card0/card1/renderD128, panfrost probe OK,
  `/sys/class/devfreq/13040000.gpu` `simple_ondemand`, доступны 698/743/800;
  при 800 МГц VGPU 825 мВ / VSRAM 925 мВ (spread 100).
- `glmark2-es2-wayland -d 5 -s 800x600`: Score **1409** (high-OPP), при
  фиксированных 800 — **1583**. В сценах `conditionals`, `function`, `loop`,
  `logic` — `panfrost ... gpu sched timeout` (js=0, status=0x8) и при 698,
  и при 800; одиночные `shading`/`bump`/`buffer`/`build`/`texture`/`terrain`/
  `effect2d`/`desktop`/`refract`/`pulsar`/`jellyfish` проходят без ошибок.
  Вывод: DVFS работает; таймауты — отдельная shader-особенность panfrost,
  не частота/напряжение.
- Откат: `/tmp/opencode/boot_a_before_gpudvfs.img` md5 `886c86cb…`.

## 13.11 (2): Wi-Fi M22 — MCIF-канал патча закрыт железом; BTIF взят в работу

Формат `INIT_CMD_ID_PATCH_*` найден (gen4m: `PATCH_START` = `DOWNLOAD_CONFIG`
{u4Address,u4Length,u4DataMode} с CID 5, тело пакетами по 2 КБ, `PATCH_FINISH`
{ucCheckCrc=0}, семафор CID 0x10) и реализован в
`0009-wlan-query-status-and-two-start.patch` (`t1100_rom_patch_send()`).
На железе ROM **не ответил ни на 0x10, ни на 5** (`nicRxWaitResponse timeout`,
mailbox `0x02000020`), тогда как `section-config`/`WIFI_START`/`QUERY` отвечают
`status=0` — в таблице init-команд ROM'а патч-команд нет, MCIF-путь закрыт не
форматом, а железом.

Заголовок `ROMv4_be_patch_1_0_hdr.bin` уточнён: `ALPS`, hw=sw=`0x008a`,
`PatchAddr=0x00098022`, `PatchType=0x0fe3ffff`, тело 229 336 Б. Прогон stage=3:
READY=0, `wlan0` нет, oops нет, `wlan_drv_gen3.ko` `c0566930…63ed5ec3`.

Дальше — BTIF как транспорт WMT: публичные исходники найдены
(`/home/l/wifi-src/rb/.../btif/`, 7 457 строк), нужен DT-узел `btif@1100c000`
(сток `refs/stock-mt6771.dts:2198`), `stp_btif.o` в Kbuild и часы
`btifc`/`apdmac`.

## 13.11: решение по Wi-Fi — идём только внутренним чипом (BTIF/STP)

**Дата/решение.** 13.11, владелец: продолжаем **только внутренний MT6631**;
STP-транспорт (BTIF) — отдельный рубеж. Варианты «USB-донгл», «cutter»,
«отложить в бэклог» **не рассматриваются**.

**Обоснование.** MCIF-путь закрыт железом (ROM не обслуживает `PATCH_*`:
`nicRxWaitResponse timeout` на CID 0x10/5 при живых `section-config`/`WIFI_START`),
MCR-STP закрыт железом (`CTDR/CRDR`=0, func2 = тот же `WCIR`). Единственный
транспорт, который остался и подтверждён стоком (`CONFIG_MTK_BTIF=y`,
`hifType=0x2`, `btif@1100c000`), — **BTIF**. Он же нужен для BT, то есть это
не распыление, а общий кусок фазы 5.

**Следствие.** Ближайшие рубежи: (1) BTIF как модуль (`mtk_btif` + плат-слой
под MT6771: базы `apdma`, клоки `btifc`/`apdmac`), (2) `stp_btif.o` в `wmt_drv`
и `hifType = WMT_HIF_BTIF`, (3) `mtk_wcn_soc_normal_patch_dwn()` с
`ROMv4_be_patch_1_0_hdr.bin` (на планшете, sha256 `83f7e9bc…`), (4) `WIFI_START`
→ `WLAN_READY` → `wlan0` → ассоциация/DHCP.

## 13.11 (3): M23 — BTIF собран и открывается, но ROM не отвечает по STP

- Публичный порт BTIF (`/home/l/wifi-src/rb/.../btif`, mt6765) собран как
  `mtk_btif_drv.ko` под 6.12 без правок источника; наш слой
  (`scripts/remote/m23-btif/`) даёт platform device без DT, базы/IRQ из
  параметров (0x1100c000 / 0x11000a80 / 0x11000b00, SPI 114/139/140) и гейты
  `btifc`/`apdmac` напрямую в INFRACFG_AO (`0x10001090` бит31, `0x10001094`
  бит18 — оба уже стояли). `LSR=0x60`, `IIR=0x1` — блок живой;
  `mtk_wcn_btif_open() = 0`, IRQ мапятся через `sysirq` (virq 395/396/397).
- `wmt_drv` со `stp_btif.o` + `t1100_btif_stp=1`: HIF_CONF и PWR_ON проходят,
  STP открывается, WMT REG_READ (chip id 0x80000008) уходит в BTIF, но ответа
  нет (`Rx REG_EVT fail!(-1)`, IRQ 0, RX пуст) → `hw_check fail` → CONSYS
  гасится. ROMv4-патч не доставлен (`cpupcr=0x1170` в ROM, READY=0), `wlan0` нет.
- Готово к следующему шагу: путь «патч из `/lib/firmware`» уже в ядре
  (`t1100_rom_patch`), `t1100_pwr_on_done` не даёт `wlan_drv` повторно
  поднимать чип; проверены и отвергнуты гипотезы «нет пробуждения» и
  «пейсинг CTS/RTS» (`m23_wak_pulse`, `m23_no_handshake`) — чип молчит так же.
  Подробности и следующие гипотезы — `docs/wifi-port-log.md` §44,
  регистры/цитаты — `refs/m23-btif.md`.

## 13.11 (4): M24 — окно BTIF write-dead: «пакет уходит» из M23 было ошибкой

- Проверка записи в BTIF (`/dev/mem` и драйвер): **ни один регистр не меняется**
  — `IER`, `TRI_LVL`, `WAT_TIME`, `RTOCNT` читаются как до записи, 40 записей в
  `THR` не заполняют FIFO (`LSR=0x60`). Контроль: `eem_fsm` и гейты INFRACFG
  пишутся нормально, `irtx` — тоже write-dead.
- Baud/делителя в BTIF нет (в вендорском драйвере их нет вообще); единственная
  частота — гейт `btifc` = INFRACFG_AO IFR0 бит31 (`clk-mt6771.c:1173`,
  родитель `axi_sel`), он **включён** (`0x10001090=0x9befffdd`), управление
  гейтом проверено. SW-сброс (банки 0x1120…) = 0, AXI protect очищен, пинмукс
  BTIF не использует (`pinctrl-mt8183` функции BTIF не имеет).
- Следовательно STP-пакеты никогда не покидали SoC, ROM не мог ответить:
  `cpupcr=0x1170` (ROM при включённом домене), ROMv4-патч не доставлен,
  `wlan0` нет. Артефакты: `refs/m24-btif-bus-write-dead.md`,
  `tools/device/btif-probe.sh`; прогон — повторить на стоке Aurora и сравнить
  дамп infracfg/pericfg/SPM/DEVAPC.

## 13.11 (5): USB host/OTG — флешка видна, динамический возврат нестабилен

- Патч **0060** (`phy: mediatek: tphy: Add software role switching`,
  adomerle `96fe48bed8`) заменяет старый 0020 `force-device-mode`: T-PHY
  управляется workqueue по `usb_role_switch`, добавлены `usb-role-switch`,
  `role-switch-default-mode = "peripheral"` и graph PHY↔ssusb.
- Патч **0061** (`arm64: dts: t1100: enable USB role switch and OTG VBUS`):
  `dr_mode = "otg"`, `mediatek,software-role-switch`, graph endpoints;
  MT6370 OTG boost `mt6370_otg_vbus` подключён как `vbus-supply`.
- `patches/series`: 0020 удалён, 0060/0061 добавлены в конец.
- Образ `build/boot_usb_host.img` 33,554,432 B, sha256
  `c79819ee2219d169204dfb957b38ffc5ff38340e0c28aa42bd72941e97713d9b`,
  p29 md5 `d0d9bca926d8bf82e6a95732502b3c40`; Image `381f7e1b…`,
  DTB `3de99997…`; cmdline `maxcpus=8`. Откат —
  `/tmp/opencode/boot_a_before_usb_role.img`.
- Проверено на `boot_usb_host`: role switch `device → host → device`,
  dmesg `software role switch enabled`, `mtu3 dr_mode: 3`, VBUS
  5050 мВ / 2400 мА. В host с флешкой: `usb-storage`, `sd 0:0:0:0`,
  62.9 GB, `sda1 sda2` — **флешка определяется**.
- Ограничение: возврат `host → device` при активном xHCI убивает контроллер
  (`xHCI host not responding`, `HC died`). Kernel-фикс с
  `ssusb_host_exit/host_init` вызывал перезагрузку при входе в host; unbind
  xHCI из userspace тоже привёл к boot loop. Оба варианта откачены.
- Текущее состояние: p29 = `boot_usb_host` (md5 `d0d9bca9…`), role `device`,
  SSH/RNDIS работают, 8 ядер; failed только `accounts-daemon.service`.
  Host включать можно, возврат — **только перезагрузкой**.
- Следующее: не трогать dynamic role switch; при необходимости — корректный
  останов xHCI/host controller перед сменой роли, затем оформить 0060/0061
  в git и docs.

## 13.11 (6): M25 — DEVAPC MT6771 распознан, но из Linux недоступен

- Найдены базы/offset'ы DEVAPC MT6771 (сток DT: `devapc@10207000` + APC-инстанс
  `0x1000e000`, SPI 145, клок `infracfg_ao 45`) и номер слейва **BTIF = 102**
  (`PERISYS_BTIF` в `devapc_infra_devices[]`, 379 записей; APDMA=90, UART0=92).
- На устройстве: `APC_CON` (0x10207f00) = 0 и **не пишется** (запись 0x80000000
  отбрасывается), `VIO_MASK/STA/DBG` = 0 (слово BTIF `0x1020740c` бит6 = 0),
  APC-таблицы `0x1000e000` и DMPU `0x10015000` = 0, гейт `DEVICE_APC`
  (INFRA1[20]) **не включается**, хотя соседние биты регистра пишутся.
- Права на MT6771 задаёт LK/ATF (`MTK_SIP_LK_DAPC 0x82000101`; вендорский
  `start_devapc()` пишет только APC_CON и комментирует «SMC call is called to
  set Device APC in LK»). Запись в BTIF после всех попыток по-прежнему
  отбрасывается ⇒ открыть права из Linux нельзя. Факты — `refs/m25-devapc-mt6771.md`.

## 13.11 (7): M26 — LK зовёт ATF по SMC; DTB совпадает со стоком; DEVAPC нарушений не даёт

- Из дампа `lk_a` (md5 `fab6c0a7…`): `[DEVAPC] platform_sec_post_init - SMC call
  to ATF from LK`; LK ищет узлы `devapc@10207000`, `devapc_mpu_ao@10015000`,
  `btif@1100c000`, `irtx@1100d000` по compatible в **нашем** DTB (строки 0xaf7dc,
  0xae904, 0xb2764, 0xb2920). Права ставит ATF; `gz_a` упакован, офлайн не разобрать.
- Сравнение живого DTB со стоком: по всем этим узлам (reg/int/clocks/status) —
  **идентично** ⇒ DTS не меняли, boot не прошивали.
- DEVAPC-блок жив (`VIO_MASK0=0xffffffff`), но отброшенный write в BTIF не даёт
  ни `VIO_STA` (слово 3 = 0), ни `DBG0/1` ⇒ DEVAPC как блокиратор не подтверждён.
  `APC_CON` не пишется, гейт `INFRA_DEVICE_APC` (IFR1[20]) не включается; попытка
  вендорского `start_devapc()` добавлена в код (`m23_devapc_open`).
- Запись в BTIF по-прежнему отбрасывается (`IER` 0xa5a5a5a5 → 0), ROM молчит,
  ROMv4-патч не доставлен, `wlan0` нет. Массовое включение всех гейтов INFRACFG_AO
  вешает плату (ребут) — метод запрещён. Факты — `refs/m26-lk-devapc.md`.

## 13.11 (8): микрофон — capture работает (маршрут UL1→ADDA)

- `arecord` падал с `set_params:1462: Невозможно установить параметры hw:`.
  `strace` показал, что `HW_PARAMS` и `SW_PARAMS` проходят, а `PREPARE`
  возвращает `EINVAL`; `journalctl -k` дал точную причину:
  `Capture_1: ASoC: no backend DAIs enabled for Capture_1`.
- Виноват выключенный DAPM-маршрут FE(UL1) → BE(ADDA): контролы
  `UL1_CH1 ADDA_UL_CH1` и `UL1_CH2 ADDA_UL_CH2` были `off`. После
  `amixer -c0 cset name='UL1_CH1 ADDA_UL_CH1' on` и то же для CH2 capture
  заработал; `dpcm_fe_dai_prepare()` больше не возвращает `-EINVAL`.
- Проверка: `arecord -D hw:0,1 -f S16_LE -r 48000 -c 2
  --period-size=1024 --buffer-size=4096 -d 2 /tmp/t.wav` → RC=0, 384044 B,
  `sox stat`: peak 0.176, RMS 0.015. PipeWire source `alsa_mic` (node 33,
  `api.alsa.path=hw:0,1`) даёт ненулевой WAV; `wpctl set-default 33` сделан.
- В `rootfs-overlay/usr/local/bin/t1100-audio-mixer.sh` добавлен маршрут
  `UL1_CH1/CH2 ADDA_UL` и аналоговые муксы `Mic Type Mux=ACC`, `ADC L/R
  Mux=Left/Right Preamplifier`, `PGA L/R Mux=AIN0`; сервис
  `t1100-audio-mixer.service` теперь `After=alsa-restore.service
  sound.target` и `Wants=alsa-restore.service`. После перезагрузки capture
  работает, маршрут применяется сервисом.
- `PGA Volume` (numid 81) после закрытия потока читается как 0,0:
  `mt6358_amic_disable()` явно пишет «L/R PGA 0 dB gain». Это не мешает
  захвату; для громкости можно выставить `amixer -c0 cset numid=81 4,4`
  перед записью. Устойчивый gain — отдельный возможный kernel-патч.
- Текущее: p29 = `boot_usb_host` (md5 `d0d9bca9…`), role `device`, SSH/RNDIS,
  rootfs Ubuntu 26.04 + KDE 6.6.4; микрофон и динамик работают.
- Следующее: при необходимости — persistent PGA gain, затем отчёт/коммит.

## 13.11 (9): CPU DVFS — mtk-cpufreq, полные OPP, schedutil

- Первая попытка с полной OPP-таблицей зависла. Причина: на MT6771 первым
  регистрировался `cpufreq-dt` (`mtk-cpufreq ... error -EEXIST`), а он не
  управляет `proc`/`sram`-регуляторами: частота уходила на 1.989 ГГц при
  800 мВ (undervolt). С безопасной таблицей 793/1100/1200 МГц при 800 мВ
  `cpufreq-dt` работал, переходы частоты проходили.
- `CONFIG_CPUFREQ_DT` выключен, включён `CONFIG_ARM_MEDIATEK_CPUFREQ`.
  В `mediatek-cpufreq.c` добавлены `mediatek,mt6771`/`mediatek,mt8788`
  с `ccifreq_supported = false` (CCI на порту отключён). Драйвер policy:
  `mtk-cpufreq`, governor `schedutil`.
- В board DTS добавлены две полные OPP-таблицы по 16 точек (793…1989 МГц)
  с напряжениями MT8183: little 650…1050 мВ, big 700…1050 мВ; CPU0–3 питаются
  от `vproc12`/`vsram_proc12`, CPU4–7 — от `vproc11`/`vsram_proc11`.
- Проверено на железе: все 16 переходов обеих policy, максимум 1.989 ГГц при
  1.05 В; `schedutil` под нагрузкой 8 ядер держит 1.989 ГГц, в простое уходит
  на 793 МГц; система остаётся живой.
- Финальный образ `build/boot_cpufreq_sched.img`, sha256 `0c368fc9…`,
  md5 `4f2d9aa039a94defa7908cc651f090a9`, p29 md5 совпадает; kernel
  `e0058abb…`, DTB `7c859bc2…`, initramfs `0cfa596d…`; cmdline
  `cpufreq.default_governor=schedutil`. Откат — рабочий
  `/tmp/opencode/boot_a_cpufreq_full_ok.img` (sha256 `f4d4890d…`).
- Патчи `0062` (cpufreq MT6771/MT8788) и `0063` (CPU OPP в DTS) добавлены
  в `patches/series`; в `configs/t1100.fragment` закреплены
  `CONFIG_ARM_MEDIATEK_CPUFREQ=y` и `# CONFIG_CPUFREQ_DT is not set`.
- **Thermal/SVS пока нет:** `CONFIG_MTK_THERMAL` выключен, thermal zones
  пустые, `&svs` disabled. Длительный soak-тест на максимуме без thermal
  protection не проводился — это следующий шаг.

## 13.11 (10): thermal — CPU-зона работает, throttling проверен

- Первая попытка включить только `CONFIG_MTK_THERMAL=y` не дала драйвера:
  этот символ — только «ворота», сам AUXADC-драйвер собирается по
  `CONFIG_MTK_SOC_THERMAL`. После включения обоих символов
  `mtk-thermal 1100b000.thermal-sensor` успешно пробует устройство.
- Калибровка MT6771 через efuse не декодируется: драйвер пишет
  `Device not calibrated, using default calibration values` и использует
  дефолтные коэффициенты MT8183. Температура при этом правдоподобна:
  простой 34–38 °C, нагрузка 8 ядер — 76–79 °C.
- В board DTS включена только `cpu-thermal` (sensor 0), остальные
  унаследованные MT8183-зоны (`soc`, `gpu`, `md1`, `cpu-little`, `cpu-big`,
  `tsabb`) выключены до проверки их датчиков/калибровки. Трипы:
  80 °C passive, 90 °C passive/target, 115 °C critical.
- Cooling devices: `cpufreq-cpu0` (15 состояний), `cpufreq-cpu4` (15),
  `devfreq-13040000.gpu` (2). Проверка throttling: временно target-трип
  снижен до 70 °C; на 70.4 °C cooling state стал 2, частоты снизились
  с 1.989 ГГц до 1.846/1.924 ГГц, после снятия нагрузки состояние вернулось
  в 0. Трипы восстановлены (80/90/115).
- Финальный образ `build/boot_thermal_final.img`, sha256
  `880ffdbac265ccb358f0d7a76362b07418e62e90e2e996b2dc489d9cd96188bd`,
  md5 p29 `e96c91f6e67921e82dfa874b4bfa3a87`; kernel `1529250198…`,
  DTB `8190d9d0…`, initramfs `0cfa596d…`; cmdline `maxcpus=8`,
  `cpufreq.default_governor=schedutil`.
- Откат без thermal: `/tmp/opencode/boot_a_before_thermal.img`
  (md5 `4f2d9aa0…`, boot_cpufreq_sched); тестовый read-only thermal
  `/tmp/opencode/boot_a_thermal_test_ok.img` (md5 `6a74560f…`).
- SVS по-прежнему выключен (`&svs` disabled): его efuse-калибровка MT6771
  не документирована; thermal throttling уже работает через CPU cooling.

## 13.11 (11): suspend — s2idle работает, deep mem не восстанавливается

- `freeze` (s2idle) при подключённом RNDIS сначала падал: `11201000.usb`
  не давал уснуть, `last_failed_errno = -EBUSY`. Причина — MTU3 gadget.
- Решение: перед сном отцеплять UDC (`echo "" > .../usb_gadget/t1100/UDC`),
  после пробуждения возвращать `11201000.usb`. Это делает systemd-хук
  `t1100-usb-gadget.sh`; для штатного `systemctl suspend` используется
  `SuspendState=freeze` в `sleep.conf.d/10-t1100.conf`.
- Проверено: `rtcwake -m freeze -s 10` при отцепленном UDC — успешно;
  `systemctl suspend` с RTC-будильником на 25 с — USB исчезает и возвращается,
  `systemd-suspend.service` завершается, `suspend_stats.success=2`, KWin,
  DRM и thermal zone после пробуждения живы.
- **Deep `mem` (PSCI deep) не восстанавливается**: после `rtcwake -m mem`
  плата не проснулась ни по RTC, ни по USB; потребовался power-cycle.
  Поэтому deep не используем, `mem_sleep` принудительно `s2idle` через
  `t1100-suspend-default.service` (проверено после reboot: `[s2idle] deep`).
- Sleep/suspend/hibernate/hybrid-sleep таргеты размаскированы скриптом
  `t1100-suspend-enable.sh`; повторно маскировать не нужно.
- Rootfs-файлы: `rootfs-overlay/etc/systemd/sleep.conf.d/10-t1100.conf`,
  `rootfs-overlay/usr/lib/systemd/system-sleep/t1100-usb-gadget.sh`,
  `rootfs-overlay/usr/local/sbin/t1100-suspend-enable.sh`,
  `rootfs-overlay/etc/systemd/system/t1100-suspend-default.service`.
- Boot-образ не менялся: p29 остаётся `boot_thermal_final.img`
  (md5 `e96c91…`); suspend — это userspace/rootfs-настройка.

## 13.11 (12): SVS на MT6771 нет; efuse-калибровка thermal расшифрована; qmmp на PipeWire; образ собран

### SVS — включать нечего (вопрос закрыт)

Стоковая конфигурация (`refs/device/config-stock.gz`) содержит
`CONFIG_MTK_CPU_FREQ=y`, `CONFIG_MTK_CM_MGR=y`, `CONFIG_MTK_SWPM=y`,
`CONFIG_MTK_CPU_CTRL_CFP=y` — и **ни `CONFIG_MTK_SVS`, ни `CONFIG_MTK_PPM`,
ни `CONFIG_MTK_EEM`**. В вендорском дереве (Motorola/Realme, 4.14) каталога
`svs` в `drivers/misc/mediatek/` тоже нет: в `base/power/` лежат `eem_v1`,
`eem_v2` (в т.ч. `eem_v2/mt6771/`), `cpufreq_v1/v2`, `spm_v4`, `hps_*`,
`pbm_*`, `upower_*`, а `base/power/mt6771/` — только GPU
(`mtk_gpufreq_core.c`, `mtk_gpu_bw.c`, `mtk_picachu.c`).

Значит на MT6771 SVS не использовался и в стоке: `&svs { status = "disabled" }`
в `mt6771.dtsi` — не «недоделка», а правильное состояние. Из ограничений
пункт убираем (формулировка: «SVS на MT6771 отсутствует и в стоке»).

### Thermal: efuse-калибровка MT6771 расшифрована, адрес ячейки — кандидат

Вендорский `thermal/mt6771/src/mtk_tc.c` + `inc/tscpu_settings.h` (ветка
`android-13.0`) дают точную раскладку: `ADDRESS_INDEX_1=100` → `buf0`
(VTS1 `[25:17]`, VTS2 `[16:8]`, O_SLOPE_SIGN `[7]`, DEGC_CALI `[6:1]`,
ADC_CALI_EN `[0]`, O_SLOPE `[31:26]`), `ADDRESS_INDEX_0=101` → `buf1`
(ADC_GE `[31:22]`, ADC_OE `[21:12]`, VTS3 `[8:0]`), `ADDRESS_INDEX_2=102`
→ `buf2` (VTS4 `[31:23]`, VTSABB `[22:14]`, VTS5 `[13:5]`).

Это **бит-в-бит mainline `MTK_THERMAL_V1`**, причём индексы 100/101/102 идут
подряд, поэтому одно 12-байтовое чтение от слова 100 даёт ровно
`[buf0, buf1, buf2]`. Вендорские дефолты совпадают с mainline
(`adc_ge` 265..758 иначе 512, `vts` −8..484 иначе 260, `degc_cali` 1..63
иначе 40), а множитель `1534/10` = mainline `cali_val 153`. То есть драйвер
менять не нужно — только указать правильный адрес ячейки.

Отображение индекс→смещение: `offset = 4 * index` (на MT8183 индекс 96 →
0x180 = `calib@180`). Для MT6771 это `0x190`, т.е. ячейка должна читать
`reg = <0x190 0xc>`.

**Риск:** на MT8183 ровно по 0x190 лежит `mipi_tx_calibration`, которую
использует `&mipi_tx0` (DSI работает, панель жива). Поэтому адрес меняем
только после чтения реальных слов efuse на плате. Утилита для этого —
`tools/device/efuse-thermal-decode.sh`: перебирает слова nvmem-устройства,
проверяет каждый трёхсловный блок по вендорской валидации, разбирает поля
для 0x190 и печатает сырые слова вокруг 0x180/0x190.

### qmmp переключён на PipeWire

Плагин в пакете есть (`plugins/Output/libpipewire.so`), имя плагина —
`pipewire`. Ключ подтверждён по исходнику `src/qmmp/output.cpp`:
`Output/current_plugin`. В образ положен
`rootfs-overlay/root/.config/qmmp/qmmp.conf`:

```ini
[Output]
current_plugin=pipewire
```

### Итоговый образ rootfs собран

- overlay (PAM для root, drop-in'ы PipeWire, `t1100-audio-mixer`, qmmp,
  пакеты `cadcraft/gridcraft/photocraft/wordcraft`) применён в chroot
  `/home/l/t1100-rootfs2604`;
- проверено: `/etc/pam.d/kde` без `user != root`, `/root/.config/qmmp/qmmp.conf`;
- архив: `/home/l/t1100-rootfs2604-full-2026-11-13.tar.gz`,
  **1 846 217 781 Б**, sha256
  `7b407d93c8d3f9d1b62865004ddf3a7518508ce42ddcc81aaa58760a0762eadf`,
  `gzip -t` — OK.

## 13.11 (13): сдвиг кадра вернулся — фикс 0052 восстановлен

После пересборки ядра на build-хосте пользователь снова увидел чёрную полосу
сверху и обрезку снизу. Причина: в локальном дереве `linux-t1100` верхушкой
был WIP-коммит `be4c58d5a` «move 212 lines of vblank into the back porch»,
где в `panel-it6112-boe-tv110xum-lb2.c` остались **старые** значения
эксперимента — `vsync_end = 2176 + 8 + 240`, `vtotal = 2432`. Проверенные на
железе 12.11 `+284` / `2476` (патч 0052) в дерево не попали, поэтому полоса
~2 % вернулась.

`git apply` патча 0052 не проходил (APPLY_FAIL): в патче цитировался старый
текст комментария, а в дереве стоял текст WIP-эксперимента. Поэтому значения
восстановлены правкой файла напрямую, а патч
`patches/0052-drm-panel-it6112-move-44-more-vblank-lines.patch`
**перегенерирован** под текущее дерево (`git apply -R --check` проходит),
комментарий описывает итог: 212 + 44 строки, `vbp 284`, vblank 2432→2476,
58.93 Гц при неизменном `clock = 248356`.

Проверка на устройстве:
- образ `build/boot_shift284.img`, md5 `6621147a175724fc1c140767388bde68`
  (kernel 14 584 957 Б, ramdisk 1 396 043 Б из `--ref`, dtb 52 560 Б);
- после прошивки p29 md5 совпал, `uname -r` → `6.12.114-gbe4c58d5a5-dirty`;
- пользователь: **«Сдвиг ушёл»**.

Замечание: комментарии в шапке режима («1702 x 2432 x 60 = 248355840 Hz»)
оставлены как есть — они описывают вывод `clock` из вендорских 2432 строк,
сам `clock` не меняется.

### 13.11 (14): пропал значок батареи — патч 0053 не был в дереве

После пересборки ядра из `/home/leo/Aurora_All/device/linux-t1100` в
`/sys/class/power_supply/` остался только `mt6370-charger` (line-power);
UPower показывал `DisplayDevice: unknown, 0%`,
`icon-name: battery-missing-symbolic`, и KDE прятал индикатор.

Причина: в mainline нет топливного счётчика (`mt6358_gauge`), заряд отдаёт
второй `power_supply` `mt6370-battery`, который добавляет патч
**0053** (`drivers/power/supply/mt6370-charger.c`, +96 строк OCV-таблицы).
В дереве ядра его не было (`git apply --check` проходил чисто), поэтому
пересобранное ядро ушло без батареи. Применено и закоммичено (`6f577eafa`).

Проверено на железе после прошивки (`6.12.114-g6f577eafa7`):

```
/sys/class/power_supply/  mt6370-battery  mt6370-charger
capacity=22 status=Charging present=1 voltage_now=3570000
upower: Device /org/freedesktop/UPower/devices/battery_mt6370_battery (battery, has statistics)
```

Заодно закоммичен `vcn33` (`c6f3a4e1c`): рейка CONN теперь always-on 3.3 В,
`regulator_summary: vcn33 use_count=1 3300mV` (было 0 / 3500 mV).

## 13.11 (14): M27 — recovery не даёт дискриминатора; на стоке тоже нет CONFIG_DEVMEM

- `reboot recovery` не работает (в GPT нет `misc`); вошли кнопками. Recovery —
  вендорское ядро `4.14.186`, но **`/dev/mem` нет** (`CONFIG_DEVMEM=n`), debugfs
  не монтируется ⇒ MMIO из userspace недоступен, `btif-probe.sh` там неприменим.
- Драйверы в recovery привязаны (`1100c000.btif → mtk_btif`, `10207000.devapc →
  devapc`, оба ioremap'ят окна), но логи BTIF выключены, self-test'ы не
  скомпилированы, WMT не запущен ⇒ записей в BTIF в recovery не происходит.
- Стоковый конфиг: `CONFIG_MTK_BTIF=y`, `CONFIG_MTK_DEVAPC=y`, **`# CONFIG_DEVMEM
  is not set`** ⇒ запланированное чтение регистров на стоке через mempeek
  невыполнимо.
- Подтверждены ID/биты гейтов (`BTIF_CG=27` → IFR0[31], `AP_DMA=43` → IFR1[18],
  `DEVICE_APC=45` → IFR1[20]); в mainline `infra_btif`/`infra_device_apc` никем не
  запрошены (enable_cnt=0), гейт BTIF включается сырой записью мимо CCF ⇒
  родители (`axi_sel`/PLL) не включаются. Запись в BTIF по-прежнему
  отбрасывается, `wlan0` нет. Факты — `refs/m27-recovery-discriminator.md`.

## 13.11 (15): M28 — CCF/XO_WCN/домен CONNSYS включены, записи в BTIF всё равно теряются

- `infra_btif`/`infra_device_apc` включены **через CCF** (не сырым битом):
  `enable_cnt 0→1`, родитель `axi_sel` 156 МГц; но `clk_summary` для
  `infra_btif` остаётся `hw=N` при сыром бите31=1 (`0x10001090=0x9befff5d`).
- `pwrap+0x184 = 0x3` (`DCXO_CONN_ENABLE` стоит), домен поднят
  (`cpupcr=0x1170`, `chipid=0x788`) — записи в `0x1100c000` по-прежнему
  отбрасываются: `IER 0→0`, `TRI_LVL 0x5a→0x5a` после `hw_init`.
- Критерий «`TRI_LVL` стал 0x18» не достигнут ⇒ STP/ROMv4/`WLAN_READY`/`wlan0`
  не запускались. Остаток подозрений (CCF `hw=N`, третья частота из домена
  CONNSYS, APB write-protect без VIO) — `refs/m28-btif-ccf.md`, §50 журнала.

## 13.11 (16): M29 — записи в BTIF пошли (гейт инвертирован), ROM ответил, ROMv4-патч доставлен

- Проба на трёх initcall (патч 0065, ядро собрано/прошито с ramdisk): на
  `late_initcall` `TRI_LVL 0x5a→0xda` **принято**, `IFR0=0x4800` (бит31 = 0).
- Причина «write-dead» с M23: на MT6771 бит «CG» = 1 **закрывает** клок
  (`IFR0[31]=1` → записи отброшены, `=0` → `TRI_LVL 0x5a→0x18`, `IER 0→1`);
  наш `m23_clk_enable()` (SET) выключал BTIF. Glue переведён на **CLR**.
- После фикса: `wmt_core_hw_check: get hwcode (chip id) (0x788)` — **ROM
  ответил по STP**, ROMv4-патч **доставлен** (`patch dwn:0 frag(230,336) ok`,
  `ROMv4 patch download -> 0`, 229 336 Б, addr `0x98022`).
- Осталось: пост-патчевый «WMT reset» (`init_table_3`) падает
  (`cmd len err(-2, 5)`), `cpupcr` в ROM (`0x14xxx` < `0xa5800`), `WLAN_READY=0`,
  `wlan0` нет. Артефакты — `refs/m29-btif-early-probe.md`, §51 журнала.

## 13.11 (17): M30 — `-2` = STP закрыт (assert после таймаута RX патча); блокер — «wmt reset» без ответа

- `-2` и `err(-2,5)` расшифрованы: `wmt_ctrl_tx_ex` «STP is not enabled»; STP
  закрывал in-band assert, который вызывал таймаут RX на последнем фрагменте
  патча. На последнем фрагменте RX больше не читается (+пауза 100 мс), у
  `init_table_3` 3 попытки — `-2` ушёл.
- Патч по-прежнему доставляется целиком (`ROMv4 patch download -> 0`), но ROM не
  отвечает на `WMT_RESET_CMD {01 07 01 00 04}` (`rx:0`) → assert → STP закрыт →
  `init_table_3 fail`; `cpupcr=0x14eea` (ROM), `WLAN_READY=0`, `wlan0` нет.
- BTIF здоров: `IER=1`, `IIR=1`, `LSR=0x60`, IRQ 395 = 94 028 (RX шёл),
  `IFR0=0x1befff5d` (клок открыт).
- Прогон без reset (`t1100_skip_reset=1`): патч доставлен, `wlan_drv` доходит до
  `wlanProbe`, но `cpupcr` остаётся в ROM (`0x14f08`) ⇒ патч **сам не
  стартует**, стартовая команда нужна, а ROM её не выполняет. Следующее —
  подавить assert на время патча и/или найти вендорскую «стартовую»
  последовательность для icId `0x0788` (`refs/m30-wmt-reset-blocker.md`, §52).

## 13.11 (18): M31 — у вендора нет иной «start»-команды; reset всё ещё без ответа

- Из стока (`/home/l/aurora_root.img`): `wmt_loader` — только `/dev/wmtdetect`
  (чип-id + module init); `wmt_launcher` — `srh_patch`/`srh_rom_patch` и
  `patch info` (имя + 4 байта адреса), «BTIF Mode» по умолчанию. Отдельной
  команды «start patch» в userspace **нет** — старт делает ядро `WMT_RESET_CMD`
  `{01 07 01 00 04}`, и mt6765 использует те же байты.
- `P_ADDRESS` подтверждён кодом (обе address-команды до цикла, ошибка → -1;
  у нас `patch dwn:0` 230/230).
- Подавление `wmt_lib_trigger_assert` + `mtk_wcn_stp_set_wmt_trg_assert(0)` перед
  ретраями не помогло: первая отправка reset уходит, ответа нет (`rx:0`), STP
  всё равно сбрасывается coredump/assert-путём (`set f/w assert`) ⇒ ретраи
  падают с `-2`, `cpupcr=0x14ef8` (ROM), `wlan0` нет. Следующий шаг — заглушить
  весь coredump/assert-путь на время патча (`refs/m31-wmt-loader-and-reset.md`).

## 13.11 (19): M32 — best-effort reset; стек дошёл до MCIF `driver own`, READY не встаёт

- `WMT_RESET_CMD` теперь best-effort (`t1100: reset ack: no`, STP не рвётся),
  `wmt_lib_hw_rst` не чистит `WMT_STAT_STP_*` при `t1100_patch_active` — `-2`
  между попытками больше нет.
- `cpupcr` до/после патча — тот же ROM-цикл (`0x19d8…0x14f12`), патч передан
  (230/230), но не применён/не стартовал.
- `wlan_drv` (stage=3) доходит до MCIF: `nicpmSetDriverOwn: DRIVER OWN,
  status=0 count=513`, затем `wlanAdapterStart: nicpmSetDriverOwn() failed`
  (READY=0) → `wlanProbe -5`; `wlan0` нет. Следующий шаг — последний фрагмент
  патча (229 ack, 230-й молчит) и «patch info» из `wmt_launcher`
  (`refs/m32-best-effort-reset.md`, §54).

## 13.11 (20): M33 — последний фрагмент уходит целиком (347/347), patch info в ядре не используется

- TX-трассировка: последний фрагмент `stp->btif len=347 written=347`
  (4 STP + 5 WMT + 336 тело + 2 CRC) ⇒ обрезки нет, ROM реально игнорирует
  230-й фрагмент; `reset ack: no`.
- `struct wmt_rom_patch` разобран: ядро берёт только 4 байта `u4PatchAddr`
  (`WMT_PATCH_P_ADDRESS_CMD[12..15]`), `u4PatchType` не используется нигде; наш
  загрузчик передаёт то же, что вендор ⇒ гипотеза «patch info» закрыта.
- `cpupcr` в ROM-диапазоне (нормально и для пропатченного ROM); стек (stage=3)
  доходит до `nicpmSetDriverOwn` (`DRIVER OWN status=0 count=513`) и падает на
  READY=0; `wlan0` нет. Следующий шаг — прочитать память по `0x98022` через
  WMT `REG_READ` и сравнить с телом файла (`refs/m33-last-fragment-and-patchinfo.md`).
### 13.11 (18): Type-C — `mt6370-tcpc` наконец пробнится (18 Вт всё ещё за PD)

Драйвер `mt6370-tcpc` в дереве был, конфиг (`CONFIG_TYPEC_TCPM/TCPCI/MT6370`)
тоже, узел `pmic@34/tcpc/connector` — в DTS и в прошитом DTB, но probe
всегда падал:

```
mt6370-tcpc mt6370-tcpc.7.auto: error -EINVAL: Failed to register tcpci port
probe with driver mt6370-tcpc failed with error -22
```

**Причина — не железо и не DTB, а обязательное свойство.** В нашем коннекторе
стоит `pd-disable` (PD выключен намеренно: у коннектора нет `usb-role-switch`
и graph-endpoints, иначе tcpm дёргает роль `mtu3` и рвёт RNDIS-гаджет, через
который идёт SSH). При этом `tcpm_fw_get_caps()`
(`drivers/usb/typec/tcpm/tcpm.c`) в non-PD ветке **требует** строковое
свойство `typec-power-opmode`:

```c
if (!port->pd_supported) {
	ret = fwnode_property_read_string(fwnode, "typec-power-opmode", &opmode_str);
	if (ret)
		return ret;      /* -EINVAL */
```

Его не было → `-EINVAL` → `Failed to register tcpci port` → probe `-22`.
Сообщение `Can't find connector node.` при этом не печаталось: `connector`
находился, падало позже.

**Фикс** (коммит ядра `c1c0a897d`): `typec-power-opmode = "default";` в узел
`connector`. После прошивки: `probe of mt6370-tcpc.7.auto returned 0`,
появился `/sys/class/typec/port0` с `data_role=[device] power_role=[sink]
usb_typec_revision=1.2`.

**Что это даёт и чего нет.** Детект Type-C-порта теперь работает, но
PD-негоциации нет (`pd-disable`), `/sys/class/usb_power_delivery` пуст, а
`usb_type` зарядника по-прежнему `[Unknown] SDP DCP CDP` — класс BC1.2 от
USB-порта ноутбука не определяется. 18 Вт (9 В × 2 А) требуют **PD-зарядника**
и снятия `pd-disable` — отдельный шаг с риском потерять USB-сеть (SSH идёт по
RNDIS-гаджету), делать при физическом доступе к плате.

**Питание сейчас:** лимит входа 900 мА (`IAICR_UA=900000`), при нём вход
≈750 мА / 3.5 Вт и ≈400 мА идёт в батарею — планшет заряжается (10 → 32 %),
`t1100-power-guard` больше не гасит.


## 13.11 (23): M34 — REG_READ по адресу патча не обслуживается (ret -3); чип замолкает после патча

- `REG_READ` (`wmt_core_reg_rw_raw`, адрес с битом31: `0x80098020`) после патча
  даёт `ret -3` («Rx REG_EVT fail») — сравнить с телом файла
  (`0x00002144 …`) невозможно. До патча тот же вызов работает (`hwcode 0x788`).
- Причина частично в коде: на таймауте `wmt_core_reg_rw_raw` сам вызывает
  `wmt_core_trigger_assert()` (`wmt_core.c:650`) — этот путь не заглушён
  (в M32 глушили только `wmt_lib_trigger_assert` в `wmt_ctrl_rx`).
- `reset ack: no`, `cpupcr=0x14f0e`, `wlanAdapterStart` падает на
  `nicpmSetDriverOwn` (READY=0), `wlan0` нет. Следующий шаг — контрольный прогон
  **без патча** с тем же readback (`refs/m34-patch-readback.md`).

## 13.11 (24): M35 — до патча REG_READ отвечает, после — чип замолкает совсем

- Контроль в одной точке: **до** патча `patchmem[0x80098020] = 0` с `ret 0`,
  контроль `GEN_HCR = 0x788` (`ret 0`); **после** — `ret -3` и по адресу патча,
  и по контрольному адресу, через 2 с тоже (assert заглушён — не он).
- `nicpmSetDriverOwn`: лог `status=0` — это `FALSE` (`TRUE=1/FALSE=0`,
  `gl_typedef.h:56`), т.е. функция верно сообщает об ошибке: чип не выставляет
  `WHLPCR_FW_OWN_REQ_SET` (`BIT(8)` `MCR_WHLPCR`) за 512 мс. Правка проверки не
  нужна.
- `cpupcr=0x14ee4`, READY=0, `wlan0` нет. Патч не применён (область читалась
  нулями), передача переводит ROM в необслуживаемое состояние. Следующий шаг —
  проверить восстановление после power-cycle CONSYS (`refs/m35-control-readback.md`).

## 13.11 (25): M36 — вендор домен после патча не сбрасывает; наш power-cycle STP не оживил

- По коду вендора (`wmt_ic_soc.c:1283-1330`) после `mtk_wcn_soc_patch_dwn()`
  идут только `WMT_STEP`-хук (пуст в продукте) и `init_table_3`
  (`WMT_RESET_CMD`); `consys_hw_reset_bit_set`/`consys_hw_pwr_ctrl`/
  `wmt_lib_hw_rst` **не вызываются**.
- Наш `t1100_pwr_cycle_after_patch` реально погасил и поднял домен
  (`CONSYS-HW-PWR-OFF/ON`, `cpupcr` 0 после сброса), но `REG_READ` всё равно
  `ret -3` — и по адресу патча, и по контролю `GEN_HCR`.
- Причина по коду: после сброса чипа STP-состояние хоста не переинициализировано
  (`txseq`/`stp_en`, заморожены через `t1100_patch_active`). Следующий шаг —
  пройти `wmt_core_stp_init()` после power-cycle и повторить `hw_check`
  (`refs/m36-power-cycle-after-patch.md`).

## 13.11 (26): M37 — STP-reinit оживляет чип (hwcode 0x788), power-cycle стирает патч

- После power-cycle пройдена STP-инициализация как в `wmt_core_stp_init()`
  (`close/open/mode/en` — все rc=0), снята заморозка `t1100_patch_active`:
  `hwcode after stp reinit = 0x00000788 (ret 0)` ⇒ чип снова обслуживает
  команды, «молчание» было рассинхронизацией STP.
- Readback после перезапуска: `patchmem[0x80098020/24/28] = 0` с `ret 0` (чтение
  работает) ⇒ power-cycle **стирает** патч; перекладывать надо без перезапуска
  домена.
- `cpupcr=0x1170` (ROM), READY=0, `wlan0` нет. Следующий шаг — STP-reinit сразу
  после доставки патча (без power-cycle), затем `hw_check`+readback и «старт»
  (`refs/m37-stp-reinit.md`).

## 13.11 (27): M38 — STP-reinit без power-cycle не оживляет чип; сброс стирает патч

- По плану: `patch_dwn` → STP `close/open/mode/en` (все rc=0) без power-cycle →
  `hwcode = ret -3` (чип молчит), затем таймаут снимает STP (`-2`).
- С power-cycle (M37): `hwcode 0x788`, но `patchmem = 0` — патч стёрт ⇒
  доставка патча сама приводит MCU в нерабочее состояние, а сброс её уничтожает.
- Заголовки: `1_0` addr `0x98022` type `0x0fe3ffff` (наш выбор верен), `1_1` —
  addr `0xf0078021` type 0 (другой механизм). `cpupcr` ROM, READY=0, `wlan0` нет.
  Следующий шаг — проверка хвоста тела (срез CRC для ROMv4, как
  `BCNT_PATCH_BUF_CHECKSUM` у mt6765/6761) — `refs/m38-stp-reinit-no-cycle.md`.

## 13.11 (28): M39 — хвостового CRC в ROMv4-патче нет, вендор для 0x0788 ничего не срезает

- Посчитаны суммы тела без последних N=0/2/4/8/16 байт (crc32, crc16-ccitt/
  xmodem/arc, sum32) — совпадений с хвостом и с `u4CRC[4]` нет; `u4CRC[4]`
  (`0xffff/0x5a10/0x121a4/0x205c`) — не контрольные суммы.
- Вендор срезает `BCNT_PATCH_BUF_CHECKSUM` только для `0x6765/0x3967/0x6761`
  (`wmt_ic_soc.c`), для `0x0788` такой ветки нет; `u4CRC`/`u4PatchType` в пути
  загрузки не читаются.
- Гипотеза закрыта. Следующий шаг — сверить смещение тела (у нас 48, у generic-
  пути вендора 28): возможно, у вендора тело начинается с 28 и `patchSize`
  другой (`refs/m39-crc-check.md`).

## 13.11 (29): M40 — смещение заголовка патча (48 vs 28) не влияет на поведение

- По коду вендор режет `sizeof(WMT_PATCH)` = 28 байт (`wmt_ic_soc.c:3393`), наш
  загрузчик резал 48 (`sizeof(struct wmt_rom_patch)`); добавлен параметр
  `t1100_patch_hdr_len`.
- Оба варианта: `patchSize` 229 336/229 356, `fragNum` 230, 229/230 ack,
  `hwcode` после патча `ret -3`, `patchmem` `ret -3` — **идентично**.
- `cpupcr` в ROM, READY=0, `wlan0` нет. Следующий шаг — прогнать штатный
  вендорский путь с минимальным `srh_rom_patch`-ответчиком (GET_PATCH_INFO,
  patch_num, FREE_PATCH) — `refs/m40-hdr-offset-test.md`.

## 13.11 (30): M41 — карта пути патча; правки M33–M41 в work/ потеряны при пересборке

- Составлена карта вендорского пути патча (`refs/m41-patch-path-map.md`):
  `srh_patch` → SET_PATCH_* → GET_PATCH_INFO/GET_PATCH (файл читает ядро) →
  резка 28 Б → ADDRESS/P_ADDRESS → 230 фрагментов → FREE_PATCH →
  `init_table_3`. Наши отклонения перечислены (обход поиска, адрес из заголовка,
  нет FREE_PATCH; резка 48/28 — без разницы).
- Итог железа: BTIF-гейт инвертирован и починен, `hwcode 0x788`, патч уходит
  целиком, но после последнего фрагмента MCU перестаёт обслуживать STP; STP-reinit
  без сброса не помогает, power-cycle оживляет и стирает патч.
- **Важно:** `build-wifi-remote.sh` пересоздаёт `work/`, поэтому правки M33–M41
  в work/ потеряны; воспроизводится только `patches/wifi/0013`. Модули на плате
  (M40): `wmt_drv` `1e10a898…`, `mtk_btif_drv` `e29eaecb…`, `wlan_drv_gen3`
  `80dafe3d…`. Ждём вывод `reverse-engineer` по стоковому `wmt_drv.ko`.

## 13.11 (31): M42 — патчи консолидированы в `patches/wifi/`, сборка воспроизводится

- `patches/wifi/README.md` описывает все 18 патчей (common/wlan/BTIF), порядок и
  пересборку с нуля. Проверено: `build-wifi-remote.sh --prepare` создаёт `work/`
  из чистого `vendor/`, и наши маркеры на месте (`t1100_rom_patch`/`last
  fragment` ×18, `t1100_pwr_on_done` ×4).
- Сборка (out `$WIFI_DIR/out`): common rc=0/errors=0, wlan rc=0/errors=0;
  `wmt_drv.ko` `e7a3c40d…`, `wlan_drv_gen3.ko` `627f9ab2…`.
- Сценарии утраченных правок M33–M41 сохранены в
  `scripts/remote/m23-btif/worktree-edits/` (кандидаты в `0014-…`), чтобы не
  терялись снова. Деплой-сборка под `merge2-out` прервана из-за параллельного
  прогона, который пересоздаёт `work/`; устройство не трогали (модули M40).
## 13.11 (21): M34 — прошивки combo-чипа добыты, стек грузится, RX от чипа нет

Блокер «нет `WIFI_RAM_CODE_6759` / `soc3_0_ram_mcu_e1_hdr.bin`» снят: они
лежат в vendor-разделе, который Аврора ставит пакетом
`droid-system-vendor-mashtab_t1-*.noarch.rpm` (147 МБ) из офлайн-репозитория
`offline-repos/5.2.1.200/adaptation/mashtab_t1/`, путь внутри пакета —
`./vendor/firmware/`. Прошивки в git не кладутся, вместо них добавлен
`tools/host/extract-aurora-firmware.sh` (достаёт из RPM в
`build/firmware-aurora`, `--deploy HOST` копирует в `/lib/firmware` платы).

Вендорский `WMT_SOC.cfg` — 119 байт без комментариев, важные отличия от нашего:
`coex_wmt_ant_mode=1`, `co_clock_flag=1`, `bt_tssi_from_wifi=3`,
`bt_tssi_target=3815`. Наш файл с `#`-комментариями вызывал в dmesg
`mal-format cfg string` / `unknown field '#'`, поэтому заменён на стоковые
значения без комментариев.

Попутно две ловушки сборки: (1) прошитое ядро `6.12.114-g92c5e7cc89-dirty`,
а модули собирались как `-g92c5e7cc89` → `Exec format error`, нужен
`LOCALVERSION='-g92c5e7cc89-dirty'`; (2) в `work/{common,wlan}` остаются чужие
артефакты (`.module-common.o`, `.*.o.d`) от сборок против других деревьев — из-за
них `.ko` сохранял старый vermagic даже при `rc=0`, а `wlan` падал на
`fixdep: … nic/.nic_tx.o.d`. Лечится `rm -rf work/{common,wlan}`; результат
проверять `modinfo -F vermagic`.

**Результат на железе:** BTIF и WMT грузятся, `wmt-loader` проходит
(`chip id 0x6771`, `/dev/stpwmt`), `CONSYS-HW-PWR-ON finish(0)`,
`polling_consys_chipid: chipId 0x00000788`, `CPUPCR 0x1170` (ROM живой).
Но STP не получает ответа: `Tx:pT<WMT> n(0..4)` уходят, затем
`wmt_dev_rx_timeout` → `Rx REG_EVT fail` → `get hwcode fail (-3)` →
`wmt_core_stp_init fail` → `pwr_off`. Регистры BTIF: `IER=0`, `IIR=1`,
`LSR=0x60` (RX-данных нет), `hal_btif_hw_init: IER readback 0x00000000`;
в `/proc/interrupts` нет ни virq 394 (BTIF), ни 395 (CONSYS).
До `consys_dl_rom_patch()` дело не доходит — он идёт после `wmt_core_hw_check`.

Следующий шаг: RX BTIF — почему `IER` не держит биты и почему `LSR` пуст при
живом ROM (гейт записи IER / другой первый кадр handshake / скорость UART).

## 13.11 (32): M43 — сток тянет **два** ROMv4-патча (`patch_num = 2`), мы — один

- RE по стоковому `wmt_drv.ko` (`c2c70b9b…`) и `wmt_launcher` (`cce022d0…`) из
  `aurora_root.img`: последовательность для `0x0788` восстановлена (адреса и
  выдержки — `refs/m43-stock-romv4-sequence.md`). Команды совпадают с нашими:
  DLM (3), `set_mcuclk_table_3` (4), ROMv4-база `18 05`/`7c 0b`, резка 28 Б,
  1000-Б фрагменты с флагами 1/2/3, `FREE_PATCH`, `WMT_RESET {01 07 01 00 04}`,
  затем `set_mcuclk_table_4` (3). Сток — более новая ревизия (маска `options =
  0x008436b5` вместо `icId ==`, `consys_ic_get_options` `0x5364`), но для
  `0x0788` результат тот же.
- **Расхождение одно и оно ключевое:** `patch_num` берётся из младшего байта
  `u4PatchVer` заголовка патча (`num = b>>4`, `seq = b&0xf`, `wmt_launcher`
  `0x5c90`–`0x5d84`). В `/vendor/firmware` два файла: `ROMv4_be_patch_1_1_hdr.bin`
  (`u4PatchVer=0xf0078021` → seq **1**, 315 фрагментов) и
  `ROMv4_be_patch_1_0_hdr.bin` (`0x00098022` → seq **2**, 230 фрагментов).
  Сток качает оба: `1_1` → reset → `1_0` → reset; наш порт (`t1100_rom_patch`)
  качает только `1_0` без первого патча.
- Поэтому M39/M40 (CRC и смещение 48/28) закрыты верно, но причина «229 из 230»
  другая: MCU ждёт первым seq 1, а наш `1_0` идёт без него. Дальше (по возрастанию
  цены): два патча в порядке seq с reset между ними; контроль `patchmem`/
  EMI-региона `0xf0078000` после первого reset; только потом таймауты/STP-reinit.

## 13.11 (32): M43 — набор патчей (1_1 seq1 → reset → 1_0 seq2 → reset): дизайн готов, применить не удалось

- По выводу `reverse-engineer`: патчей **два**; `num/seq` — в младшем байте поля
  по смещению 24 (`num = b>>4`, `seq = b&0xf`), адрес — те же 4 байта
  (`1_1`: `21 80 07 f0`, seq 1, 315 фрагментов; `1_0`: `22 80 09 00`, seq 2,
  230 фрагментов); резка заголовка — **28** байт.
- Реализация (`m43-multi-patch.py`, три хука: `patch_num`, `patch_dwn(index)`,
  `patch_info_prepare`) написана, но **не применена**: `work/` в это время правит
  параллельный агент (`0001–0013` уже содержат `t1100_no_rom_patch`, якоря
  разъехались), поэтому `0014-…` пока не сгенерирован и на железе не проверялся.
- Следующий шаг: перебазировать скрипт на текущий `work/` (или чистый
  `vendor/` + `0001–0013`), собрать `patches/wifi/0014-common-rom-patch-delivery.patch`,
  прогнать `1_1 → reset → 1_0 → reset` без power-cycle, readback `0xf0078000`,
  затем `stage=3` → `WLAN_READY` → `wlan0`.

## 13.11 (33): M44 — набор патчей работает: 1_1 (seq1) доставлен, чип жив; 1_0 не пошёл из-за жёсткого init_table_3

- Изолированное дерево `/home/l/t1100-wifi-build-m44` (свой `vendor/`+`0001–0013`),
  оформлен `patches/wifi/0014-common-rom-patch-delivery.patch`: сканирование
  списка из `t1100_rom_patch`, `num=b>>4`/`seq=b&0xf` из байтов 24..27,
  сортировка по seq, резка **28**, штатный цикл `for (patch_index…)`.
- Прогон: `1_1` num=2 seq=1 addr=218007f0 size=314120 (315 фрагментов, 314092 Б)
  → **`download -> 0`**; сразу после — `hw_check: get hwcode (chip id) (0x788)`
  ⇒ **чип остаётся на связи после первого патча** (в отличие от M29–M40, где
  шёл один `1_0` с резкой 48).
- Дальше цикл не идёт: вендорский `init_table_3` возвращает ошибку и
  `sw_init` отдаёт `-8` → весь power-on повторяется, `1_0` (seq 2) не
  запускается. Best-effort-правка попала в **некомпилируемую** `#else`-ветку
  (sha `.ko` не изменился) — это и есть следующий шаг.
- `wlan0` нет; модули на плате: `wmt_drv` `9e3ed929…`, `wlan_drv_gen3`
  `f4723c04…`, `mtk_btif_drv` `e29eaecb…`.
