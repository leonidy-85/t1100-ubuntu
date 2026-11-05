# STATUS — t1100-ubuntu

Обновлено: 29.10.2026.

## Фаза

**Фаза 0 — закрыта. Фаза 1 (bring-up) — ~30%: DTS/PSCI/WDT собраны, `Image`
собран, тестовый `boot_a` собран; на плату не прошивался.**

- База: mainline **6.12.114** + 3 патча (`patches/series`), дерево
  `../linux-t1100`.
- DTB: 4941 B, sha256 `66f4446d…aaf49`; `Image` 38 531 584 B, sha256
  `b4d289a0…d58ac`; 0 warnings (см. `docs/provenance.md`).
- Тестовый `boot_a_test.img` (32 МиБ) собран, sha256 `14069f47…e04f8`, **не
  прошит** — ждёт подтверждения владельца.

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
- Wi-Fi: MT6631 в mainline не поддержан; вероятно вендорный `wlan_drv_gen3` +
  `/vendor/firmware`.
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
  из IIO (канал с меткой `vbat`), пишет предупреждение ниже **3.65 В** и гасит
  систему ниже **3.5 В** после 3 замеров подряд (на зарядке — после 9: если
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
