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
