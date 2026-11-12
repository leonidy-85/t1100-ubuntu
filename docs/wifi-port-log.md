# Фаза 5, путь A: build-only спайк вендорского стека (журнал)

Статус: **майлстоун 2 (собираемые модули) выполнен** — `wmt_drv.ko` и
`wlan_drv_gen3.ko` линкуются под 6.12.114 (см. §14). Майлстоун 1 (каталог
API-долга) — §§1–13.

Отдельно: набор модулей пересобран под ядро второго разработчика
`6.12.114-g400cb6f-touch-rot` (планшет переведён на него 12.11) — §22; пара
«ядро + модули» готова к деплою, на устройстве ничего не выполнялось.

**Устройство не трогали** (на планшете параллельно идёт работа по тачу), ничего
не прошивали, дерево `../linux-t1100` не меняли — вся работа на build-хосте
`172.17.141.172` в `/home/l/t1100-wifi-build` и в `patches/wifi/` этого репозитория.

Основание: `docs/wifi-plan.md` §3 (путь A), решение лида от 11.11.

---

## 1. Что клонировано (точные ревизии)

Всё лежит на build-хосте в `/home/l/t1100-wifi-src/` с сохранением структуры
Android-дерева (`vendor/mediatek/kernel_modules/connectivity/{common,wlan}`).

| Репозиторий | Ветка | Коммит | Дата | Объём | На диске |
|---|---|---|---|---|---|
| `github.com/MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-common` | `Pie-9-release-POBS` | `3ff67212dcc45757c434ca5e1d35161c73ad7f55` | 2019-11-26 | 107 `.c/.h`, 75 119 строк | 3.5 МБ |
| `…-connectivity-wlan-core-gen3` | `Pie-9-release-POBS` | `249649d877d87a151525c3c5629709eba337d2bd` | 2019-09-27 | 194 `.c/.h`, 189 991 строка | 13 МБ |
| (референс, вне задачи) `github.com/haretic/android-kernel-mt6765-rabbitr1` | `main` | `382a45e1ad2a93a5ee9db9019b5b2a44f07d699a` | 2026-11-10 | 97 447 файлов, 2.1 ГБ | `refs/haretic-mt6765` |

Клоны неглубокие (`--depth 1 --single-branch`). Свободно на хосте после всего:
~24 ГБ (`df -h /home`). Референс haretic взят **только как источник недостающих
заголовков и как образец mainline-порта** (§2.3), в сборку не входит.

### 1.1 Что дал референс haretic (важно)

Это тот же вендорский код (`wmt`), уже **портированный под mainline** (ядро 7.3):
103 файла / 65 915 строк в `drivers/staging/mtk-connectivity/wmt`, плюс
`adapter/`, `btif/`. Оттуда взяты четыре заголовка, которых **нет в публичных
репозиториях Motorola**:

- `adapter/connectivity_build_in_adapter.h` — уже mainline-версия (SPDX GPL-2.0,
  `#include <linux/sched/clock.h>` и т.д.);
- `adapter/mtk_wcn_cmb_stub.h`, `adapter/wmt_build_in_adapter.h`,
  `btif/inc/mtk_btif_exp.h`.

Разница «наш common vs их wmt» по общим файлам `common_main/`: 66 файлов,
**+5036 / −2298 строк**. Это верхняя оценка объёма порта WMT (включает их
рефакторинг под gen4m, поэтому реальный API-долг меньше). Существенная деталь:
у них `mt6771` есть только как **пустая слабая заглушка**
(`__weak consys_ic_ops_mt6771 = {}`, `mtk_wcn_consys_hw.c:119`), реализован лишь
`mt6765.c`. То есть **SoC power-on для MT6771 в mainline-стиле не существует** —
его надо переносить из нашего Motorola-дерева (`platform/mt6771.c`, 1067 строк).

---

## 2. Как собирали

### 2.1 Ядро и режим сборки

| | |
|---|---|
| ядро | `6.12.114` (out-дерево `/home/l/t1100-ubuntu-build/out`, `kernel.release = 6.12.114-g95e3b41b86-dirty`) |
| src | `/home/l/t1100-ubuntu-build/src` |
| режим | **out-of-tree модуль**, `make -k -C <out> M=<spike/work/{common,wlan}> modules` |
| тулчейн | `aarch64-linux-gnu-gcc` (GCC 15), `ARCH=arm64` |

Ключевые переменные (вендорские Makefile — из Android-мира, требуют их явно):

```sh
ARGS=(ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
      CONFIG_MTK_COMBO=y 'CONFIG_MTK_COMBO_CHIP="CONSYS_6771"'
      CONFIG_MTK_WIFI_MCC_SUPPORT=n
      MTK_PLATFORM=mt6771 MTK_PROJECT=k6771v1_64
      AUTOCONF_H=<out>/include/generated/autoconf.h)
KCF="-I<spike>/compat/include -DCONFIG_NL80211_TESTMODE=1 \
     -DCONFIG_WEXT_CORE=1 -DCONFIG_WEXT_PRIV=1 -DCONFIG_WEXT_SPY=1"
```

**Грабли (стоили одного раунда):** `CONFIG_MTK_COMBO_CHIP` в вендорских Makefile
фильтруется **вместе с кавычками**: `$(filter "CONSYS_%",$(CONFIG_MTK_COMBO_CHIP))`.
Если передать `CONFIG_MTK_COMBO_CHIP=CONSYS_6771` без кавычек, фильтр не
срабатывает и молча собирается **другая конфигурация**: `WLAN_CHIP_ID=MT6630`,
HIF `sdio/` вместо `ahb_sdioLike/`, без `plat/mt6771/plat_priv.c` и без
`platform/mt6771.o` в WMT. Раунды r1–r4 в журнале — по этой причине на
неверной конфигурации; цифры в §4 — с r5 (правильная конфигурация MT6631/AHB).

### 2.2 Скрипты спайка (на build-хосте, в git проекта не добавлялись)

```
/home/l/t1100-wifi-src/spike/
  build.sh              # rsync clean->work, apply fixes, make -k, сводка
  fixes/apply.sh        # механические правки F1..F5
  compat/include/       # 12 заголовков-заглушек/совместимости
  logs/r1..r9-*.log     # логи всех раундов
  work/{common,wlan}    # рабочая копия (rsync --delete из чистых клонов)
```

Механические правки (`fixes/apply.sh`), все — не меняющие семантику:

| # | Что | Зачем |
|---|---|---|
| F1 | `ACPI_STATE_D0..D3` → `WLAN_ACPI_STATE_D*` в `wlan/include/nic/wlan_def.h` | имя enum конфликтует с макросами `<acpi/acpi.h>` (тянется через `linux/fb.h` ← `gl_os.h`) |
| F2 | `#include <stddef.h>` → `<linux/stddef.h>` (`wlan/common/wlan_oid.c`) | под `-nostdinc` stddef.h нет |
| F3 | убрать `#include <linux/wakelock.h>` (5 файлов) | заголовок удалён в 4.15 |
| F5 | убрать `ccflags-y += -Werror` из `common/Makefile` | политика Android-сборки, не зависимость кода |

F4 — не правка, а build-knob: `-DCONFIG_NL80211_TESTMODE=1` (см. §6).

### 2.3 compat-заголовки (12)

Наши (написаны здесь, минимальные): `aee.h`, `sync_write.h` (обёртки
`mt_reg_sync_writel` над `writel`, 4.14 `asm/sync_write.h`), `mt_emi_api.h`,
`upmu_common.h`, `mtk_clkbuf_ctl.h`, `mtk_hibernate_dpm.h`, `mt_sleep.h`,
`linux/mfd/mt6397/rtc_misc.h`.

Взяты из haretic (mainline-версии): `connectivity_build_in_adapter.h`,
`mtk_wcn_cmb_stub.h`, `wmt_build_in_adapter.h`, `mtk_btif_exp.h`.

Смысл: `mt_emi_api/upmu_common/clkbuf/hibernate/mt_sleep` в mainline отсутствуют
принципиально — это те самые «MTK-only подсистемы» из плана. Заглушки нужны
только чтобы компилятор дошёл до остального кода.

### 2.4 Чего в спайке ещё нет (нужно для линковки)

- в `/home/l/t1100-ubuntu-build/out` **нет `Module.symvers`** (ядро собиралось как
  `Image`+`dtbs`, модули не собирались) → даже при 0 ошибок modpost не слинкует
  `.ko`. Для следующего шага: `make modules` в этом out (или `KBUILD_MODPOST_WARN=1`);
- модули выключенных подсистем (см. §6) пока **не выключены** — спайк собирает
  полный список объектов, чтобы долг был виден целиком.

---

## 3. Раунды сборки (что менялось → что получилось)

`errors` — строки `error:` в логе; `objs` — успешно собранные `.o` из всех
объектов модуля (`cc`).

| Раунд | Что добавили | common | wlan |
|---|---|---|---|
| r0 | как есть (без правок) | падение на первом `fatal error` (нет `rtc_misc.h`), 0 объектов | — |
| r1 | F1–F3 | 52 err / 44 cc | 165 err / 75 cc *(неверная конфигурация: MT6630/SDIO)* |
| r2 | +4 заглушки (`aee`, `cmb_stub`, `build_in_adapter`, `rtc_misc`) | 175 / 44 | 130 / 75 *(то же)* |
| r3 | +`sync_write.h`, `mtk_btif_exp.h`, `wmt_build_in_adapter.h` | 629 / 44 | 130 / 75 *(то же)* |
| r4 | +настоящие заголовки из haretic (cmb_stub и др.) | 172 / 44 | 128 / 75 *(то же)* |
| **r5** | **правильный `CONFIG_MTK_COMBO_CHIP` (с кавычками) → MT6631/AHB** | 173 / 45 | 131 / 78 |
| r6 | +`upmu_common`, `mt_emi_api`, `hibernate`, `mt_sleep`, `clkbuf` | 184 / 45 | 131 / 78 |
| r7 | `CONFIG_NL80211_TESTMODE=1` | 184 / 45 | 108 / 78 |
| r8 | F5 (снят вендорский `-Werror`) | **93** / 45, objs 29 | 108 / 78, objs 64 |
| r9 | +`CONFIG_WEXT_CORE/PRIV/SPY` | 93 / 45, objs 29 | **100** / 78, objs 65 |

Итог r9 (лучшая достигнутая конфигурация): **193 «жёстких» ошибки** (93 WMT +
100 wlan) в **30 файлах**, чисто компилируются **29/45** объектов WMT и
**65/78** объектов wlan (83 %). До `.ko` дело не доходит (нет `Module.symvers`,
см. §2.4), но структура долга уже видна.

---

## 4. Каталог API-долга 4.14 → 6.12 (r9)

### 4.1 WMT (`connectivity-common`), 93 ошибки / 16 файлов

| Тема | Ошибок | Файлы | Класс |
|---|---|---|---|
| time API: `do_gettimeofday`, `struct timeval`, `rtc_time_to_tm`, `get_monotonic_boottime` | 18 | `core/psm_core.c`, `linux/osal.c`, `linux/stp_dbg.c`, `linux/stp_sdio.c`, `linux/wmt_dev.c`, `debug_utility/connsys_debug_utility.c` | механически |
| `ioremap_nocache` (удалён в 5.9) | 7 | `wmt_ic_soc.c`, `wmt_lib.c`, `wmt_dbg.c`, `wmt_step.c`, `mt6771.c`, `mtk_wcn_consys_hw.c`, `connsys_debug_utility.c` | механически (`ioremap`) |
| tty: `tty_port.low_latency`, `tty_ldisc_ops.magic`, `TTY_LDISC_MAGIC`, `tty_register_ldisc(1 arg)`, `n_tty_ioctl_helper(3 args)` | 11 | `linux/stp_uart.c` | переписать/выключить (STP-over-UART нужен только BT) |
| timer: `init_timer`, `timer_list.data`, `function(unsigned long)` | 5 | `linux/osal.c`, `connsys_debug_utility.c` | механически (`timer_setup`) |
| procfs: `proc_create` с 4 аргументами | 5 | `stp_sdio.c`, `wmt_dbg.c`, `wmt_dev.c` | механически (`proc_ops`) |
| MTK PMIC/clock-buffer: `KERNEL_upmu_set_reg_value`, `KERNEL_pmic_set_register_value`, `MT6358_LDO_VCN18/VCN33_OP_EN`, `PMIC_RG_LDO_VCN28_*`, `KERNEL_clk_buf_ctrl`, `CLK_BUF_CONN` | 6 | `platform/mt6771.c` | **переписать на mainline regulator/CCF** (см. §5) |
| несовместимые прототипы (`platform_driver.probe` → `int`, tty-колбэки, `wakelock`→`wakeup_source`) | 4 | `linux/osal.c`, `platform/mtk_wcn_consys_hw.c` | механически |
| прочее/каскады: `wakeup_source_register` (2 арг.), `class_create` (1 арг.), `rtc_gpio_enable_32k`/`RTC_GPIO_USER_GPS` (MTK RTC32k), `sizeof(struct timeval)` | 37 | 15 файлов | смешанное: 2–3 строки механически, RTC32k — выключить (GPS-ветка) |

### 4.2 WLAN (`wlan-core-gen3`), 100 ошибок / 14 файлов

| Тема | Ошибок | Файлы | Класс |
|---|---|---|---|
| cfg80211 ops: сигнатуры `net_device*` → `wireless_dev*`, `mgmt_frame_register` → `update_mgmt_frame_registrations`, `change_station`/`stop_ap`/`change_beacon` через `link_station_parameters`/`cfg80211_ap_update` | 19 | `gl_init.c`, `gl_p2p.c`, `hif/ahb_sdioLike/ahb.c` | механически, но требует понимания ролей wdev/netdev (≈60–100 строк) |
| cfg80211 поля: `wireless_dev.current_bss` → `links[0].client.current_bss`, `current_ssid/ssid_len` → `u.client.*`, `cfg80211_roam_info.bss` → `links[0].bss` | 21 | `gl_cfg80211.c`, `gl_init.c`, `gl_kal.c`, `gl_p2p_cfg80211.c` | механически (переименование доступа) |
| procfs: `proc_create` 4 арг. | 10 | `gl_kal.c`, `gl_proc.c` | механически |
| access_ok: `access_ok(type, addr, len)` → `access_ok(addr, len)`, `VERIFY_READ/WRITE` | 9 | `gl_bow.c`, `gl_wext_priv.c` | механически (7 строк) |
| `set_fs`/`get_fs`/`get_ds`/`mm_segment_t` (удалены в 5.10) | 7 | `gl_kal.c` | **переписать** (работа с user-указателями; единственное «настоящее» переписывание) |
| time API (`do_gettimeofday`, `timeval`, `sched_clock` отсутствует без `<linux/sched/clock.h>`) | 11 | `common/debug.c`, `mgmt/stats.c`, `mgmt/wmm.c`, `gl_kal.c`, `gl_proc.c`, `nic/nic_rx.c`, `ahb.c` | механически |
| IPv6: `struct inet6_ifaddr` без include | 10 (каскад в 3 системных заголовках) | `gl_kal.c` | механически (1 `#include <net/addrconf.h>`) |
| `netif_rx_ni` (удалён), `ioremap_nocache`, legacy timer | 4 | `gl_kal.c`, `common/wlan_lib.c` | механически |
| прочее (`os/version.h` build-string, `static_assert` от каскада) | 9 | — | — |

### 4.3 Сводка «механическое vs переписывание»

**Механически (≈85 % строк ошибок):** time API, `ioremap_nocache`, `proc_create`
→ `proc_ops`, `timer_setup`, `access_ok`/`VERIFY_*`, `netif_rx_ni`, `class_create`,
`sched_clock` (include), IPv6 include, переименования полей cfg80211, сигнатуры
`cfg80211_ops` (wdev вместо netdev). Оценка: **2–3 дня** на wlan + **1–2 дня** на WMT,
если делать только «чтобы собралось».

**Требует переписывания / решения:**
1. `set_fs/get_fs` в `gl_kal.c` (7 ошибок) — единственный блок, где нельзя
   обойтись переименованием: надо перейти на `copy_from_user`/`copy_to_user`
   с реальными user-указателями (сейчас вендор подменяет `addr_limit`).
2. PMIC/clock-buffer в `mt6771.c` (§5): не «портируется», а **заменяется** на
   `regulator`/CCF — нужно решение, чем именно заменить `vcn18/vcn28/clk_buf`
   (в mainline MT6358 есть `vcn18`, `vcn28`, `vcn33`).
3. WEXT-private: **не переписывание** — `struct iw_handler_def` в 6.12 содержит
   `num_private/private/private_args` под `#ifdef CONFIG_WEXT_PRIV`
   (`include/net/iw_handler.h:334`). Достаточно включить опцию; при r9
   `gl_wext.c` компилируется целиком (8 ошибок исчезли).
4. tty/STP-over-UART (`stp_uart.c`, 11 ошибок) — нужен только если BT пойдёт
   через UART; для Wi-Fi-майлстоуна выключить.

---

## 5. Отдельно: `mt6771.c` — SoC power-on (главный результат спайка)

Файл `common_main/platform/mt6771.c` (1067 строк: pinmux A-die, AP2CONN OSC, EMI
remap, AP_RGU reset, DCXO, `vcn33/vcn18/vcn28`, клоки, чтение WCIR) в r6–r9
**парсится целиком** и даёт всего **12 ошибок в 4 местах**:

| Строка | Ошибка | Что это |
|---|---|---|
| 399 | `KERNEL_clk_buf_ctrl` + `CLK_BUF_CONN` | clock buffer (32k для DCXO/BT) — MTK-only; заменить на CCF-гейт или no-op |
| 411 | `ioremap_nocache` (→ 3 каскада `UINT8* from int`) | механически `ioremap` |
| 720, 731 | `KERNEL_upmu_set_reg_value` + `MT6358_LDO_VCN18_OP_EN`, `MT6358_LDO_VCN33_OP_EN` | включение LDO через PMIC-регистры → `regulator_enable(&vcn18/vcn33)` |
| 759–760 | `KERNEL_pmic_set_register_value` + `PMIC_RG_LDO_VCN28_HW0_OP_EN/_CFG` | `vcn28` → `regulator` (в MT6358 он есть) |

Остальное в файле уже mainline-совместимо: `regulator_get/enable/set_voltage`
(5/5/5 вызовов), `clk_prepare_enable`/`devm_clk_get`, `of_iomap`,
`of_property_read_u32_array`, `readl/writel`, `msleep/udelay`.
**Вывод: power-on CONSYS для MT6771 — это ~15 строк правок + 2 заглушки
(clkbuf, EMI MPU), а не «нет TRM».** Это лучшая новость итерации.

Также компилируются без ошибок: `mtk_wcn_consys_hw.c` (3), `wmt_plat_alps.c` (2),
`common_main/core/wmt_ic_soc.c` (2) — то есть слой «WMT ↔ CONSYS» почти чист.

---

## 6. Что можно «застабить» на первом этапе (выключить конфигом/из Makefile)

Список блоков, которые для «модуль собрался и делает power-on» не нужны.
Выигрыш — оценка по спайку.

| Блок | Файлы | Что даёт | Что теряем |
|---|---|---|---|
| SDIO-ветка WMT: `linux/stp_sdio.c`, `hif_sdio.c`, `common_detect/sdio_detect.c`, `mtk_wcn_cmb_hw.c` | 4 | **≈30 ошибок** (20+4+8) | ничего: у нас AHB/WFDMA + `ahb_sdioLike` |
| `common_detect/wmt_detect_pwr.c` + GPS-ветки (`drv_init/gps_drv_init.c`) | 2 | 5 ошибок (`rtc_gpio_enable_32k`, `RTC_GPIO_USER_GPS`) | GPS (не в скоупе) |
| `linux/stp_uart.c` | 1 | 11 ошибок | BT через UART (BT позже) |
| `wmt_step.c` (`CFG_WMT_STEP`) | 1 | 4 ошибки | MTK factory-step режим |
| `debug_utility/*` (ring/EMI fw log) | 3 | 8 ошибок (`connsys_debug_utility.c`: time API, `ioremap`, timer) | fw-логи CONSYS (нужны позже для отладки!) |
| `stp_dbg*.c` (coredump → AEE) | 3 | 5 ошибок | coredump в AEE |
| BT/FM/IDC в WMT: `btm_core.c`, `hif_sdio`-зависимые, `wmt_idc.c`, `bgw_desense.c` | — | — | BT/FM |
| wlan P2P (`gl_p2p*`, `mgmt/p2p_*`, `nic/p2p_nic.c`, `wlan_p2p.c`) | ~20 | **≈10–15 ошибок** + много строк | P2P/GO (для v1 не нужно) |
| wlan WEXT (`gl_wext.c`, `gl_wext_priv.c`) | 2 | ≈10 ошибок | WEXT-интерфейс (остаётся cfg80211) |
| wlan BOW (`gl_bow.c`, `wlan_bow.c`) | 2 | 4 ошибки | Bluetooth-over-WiFi |
| QA/ATE (`gl_qa_agent.c`, `gl_ate_agent.c`, `nic/test.c`) | 3 | — | заводские тесты |
| WAPI/TDLS/PASSPOINT/NFC-beam/MET (`include/config.h`) | — | — | соответствующие фичи |

**Требуемые опции ядра** (без них код не собирается вообще — это не «долг», а
конфиг; сейчас в `.config` их нет):

```
CONFIG_CFG80211=y|m            # есть (=m)
CONFIG_NL80211_TESTMODE=y      # vendor требует (gl_cfg80211.h:285 #error)
CONFIG_WEXT_CORE=y             # WEXT-интерфейс драйвера
CONFIG_WEXT_PRIV=y             # private ioctls в struct iw_handler_def
CONFIG_WEXT_SPY=y              # get_wireless_stats/iw_statistics
```

Оговорка: в r9 эти символы поданы как `-D` в `KCFLAGS` (влияют только на
заголовки). В настоящей сборке они обязаны быть в `.config` — иначе разъедется
раскладка `struct iw_handler_def`/`cfg80211_ops` между драйвером и ядром.

---

## 7. Предлагаемый порядок работ

### Шаг 0. Инфраструктура (0.5 дня)
1. `make modules` в нашем out (появляется `Module.symvers`) — иначе `.ko` не линкуется.
2. В `configs/t1100.fragment`: `NL80211_TESTMODE`, `WEXT_CORE/PRIV/SPY`
   (+ позже `CFG80211=m` оставить).
3. Внешний Kbuild-обёртка (свой `Makefile` в `spike/`, без Android-переменных):
   списки объектов, наши `ccflags`, compat-каталог — вместо вендорских Makefile.
4. Зафиксировать выключенные блоки (§6) как «этап 1».

### Шаг 1. KAL (2–3 дня) — цель: **wlan-часть компилируется целиком**
Порядок по «цене/эффекту»: `gl_proc.c` (procfs+time) → `common/debug.c`,
`mgmt/stats.c`, `mgmt/wmm.c`, `nic/nic_rx.c` (time+`sched_clock`) →
`gl_kal.c` (set_fs — самое дорогое, timer, `netif_rx_ni`, IPv6 include) →
`gl_init.c`, `gl_cfg80211.c` (cfg80211 ops/поля) → `ahb.c` (`sched_clock`,
`platform_driver.probe` возвращает `int`, а не `void`).
Метрика: 0 ошибок в wlan, `.o` для всех 65+ файлов.

### Шаг 2. WMT core (1–2 дня) — цель: **`wmt_drv.ko` линкуется**
`osal.c` (time/timer/wakeup_source), `psm_core.c` (time), `wmt_dev.c`/`wmt_dbg.c`
(procfs), `wmt_lib.c`/`wmt_ic_soc.c` (`ioremap`), `mtk_wcn_consys_hw.c`
(`iremap`, `probe`-сигнатура).

### Шаг 3. Power-on CONSYS (2–4 дня) — цель: **`wmt: power on ok` на железе**
`mt6771.c`: `clk_buf` → CCF/no-op, LDO → `regulator` (`vcn18/vcn28/vcn33`),
`ioremap`; заглушки EMI MPU (`CFG_ENABLE_EMI_MPU=0` уже стоит для CONSYS_6771) и
SPM/DCXO. DT: `consys@18070000`, `wifi@180f0000`, `consys-reserve-memory` 2 МиБ,
`<&infracfg CLK_INFRA_CQ_DMA>`. Это первый шаг, который требует устройства.

### Шаг 4. Firmware download (3–5 дней)
`WIFI_RAM_CODE_6759` → AHB/WFDMA (`ahb_cqdma.c`), чтение WCIR (`0x788`), старт MCU.
Здесь же выясняется открытый вопрос §1.2 плана: **чем регистрируется STP-HIF**
(в стоковом логе `wmt_core_stp_init` падал с «no hif info», `hifType 0x2 = BTIF`,
а `opfunc_wlan_probe` для BTIF не реализован). Для MT6631 (AHB) ожидаемый путь —
`wmt_chrdev_wifi`/`wmt_loader`; публичных исходников `wmt_loader` нет.

Итого до «power-on ok»: **~1.5–2 недели** одного инженера при текущем темпе;
до `wlan0` — плюс 2–4 недели отладки прошивки/handshake (оценка из
`wifi-plan.md` §3.3 подтверждается).

---

## 8. «Первый работающий рубеж» (definition of done майлстоуна 1)

Считаем майлстоун закрытым, когда на build-хосте выполняется всё:

1. `make -C <out> M=<spike>/wlan modules` и `… M=<spike>/common modules`
   завершаются **с кодом 0**: получены `wlan_drv_gen3.ko` и `wmt_drv.ko`;
2. `modinfo` показывает `vermagic: 6.12.114… aarch64 SMP preempt mod_unload`
   и `depends: cfg80211` у wlan, `nm` — наличие экспортов `mtk_wcn_*`;
3. сборка идёт **без правок в `../linux-t1100`** (только `patches/` + опции
   фрагмента конфига, применяемые штатным `scripts/build-kernel-remote.sh`);
4. в репозитории зафиксирован список правок (файл → что изменено), чтобы
   каждая правка была отдельным атомарным патчем с GPL-2.0-шапкой.

Промежуточные рубежи, уже достигнутые/близкие: `mt6771.c` компилируется
(12 ошибок → 0 после §5), wlan 65/78 объектов.

---

## 9. Лицензионный аудит (для дальнейшего upstream-аудита)

| | common | wlan |
|---|---|---|
| `.c/.h` всего | 107 | 194 |
| с текстом «GNU General Public License» | 102 | 187 |
| с `SPDX-License-Identifier` | **0** | **0** |
| **без любой лицензионной шапки** | 6 | 7 |

Файлы без шапки (все — код MediaTek, по окружению GPL-2.0):

```
common/debug_utility/{connsys_debug_utility_emi.h,ring.c,ring.h,ring_emi.c,ring_emi.h}
wlan/nic/test.c
wlan/os/linux/{gl_ate_agent.c,gl_hook_api.c,gl_qa_agent.c}
wlan/os/linux/include/{gl_ate_agent.h,gl_hook_api.h,gl_qa_agent.h}
```

Вывод: порт законен (GPL-2.0, 289 файлов с классической формулировкой версии 2),
но при публикации наших производных файлов надо **добавлять SPDX-строку и
сохранять copyright MediaTek**, а по 12 файлам без шапки — не выдавать их за
наши (оставлять как есть, с пометкой происхождения). Прошивки не копировались
и в git не попадут.

---

## 10. Файлы, которые придётся модифицировать (список для аудита)

Это **объединение** по раундам r6–r9 (то есть включая файлы, дававшие только
`-Werror`-предупреждения и потому не попавшие в таблицы §4): 26 файлов WMT и
15 wlan.

**WMT (26):** `common_detect/{mtk_wcn_stub_alps.c,wmt_detect.c,wmt_detect_pwr.c}`,
`common_main/core/{btm_core.c,psm_core.c,stp_core.c,stp_exp.c,wmt_core.c,wmt_ctrl.c,wmt_exp.c,wmt_func.c,wmt_ic_soc.c,wmt_lib.c}`,
`common_main/linux/{hif_sdio.c,osal.c,stp_dbg.c,stp_sdio.c,stp_uart.c,wmt_dbg.c,wmt_dev.c,wmt_step.c}`,
`common_main/platform/{mt6771.c,mtk_wcn_consys_hw.c,wmt_plat_alps.c}`,
`debug_utility/{connsys_debug_utility.c,ring.c}`.

**wlan (15):** `common/{debug.c,wlan_lib.c}`, `mgmt/{stats.c,wmm.c}`,
`nic/nic_rx.c`, `os/linux/{gl_kal.c,gl_cfg80211.c,gl_init.c,gl_proc.c,gl_p2p.c,gl_p2p_cfg80211.c,gl_bow.c,gl_wext.c,gl_wext_priv.c}`,
`os/linux/hif/ahb_sdioLike/ahb.c`.

**Плюс новое (не вендорское):** 8 compat-заголовков (§2.3) — это наши файлы,
их надо держать отдельно (`compat/`) и озаглавить SPDX + «based on MTK 4.14
header, GPL-2.0».

---

## 11. Риски и что неизвестно

1. **STP-HIF для MT6631 (главный риск).** В стоковой 5.1.6.110 Wi-Fi не
   поднимался именно здесь: `wmt_core_stp_init` → «no hif info», затем
   `opfunc_wlan_probe: not implemented yet hifType: 0x2` (BTIF). Публичного
   `wmt_loader` нет. Пока не выяснено, кто на MT6631 обязан зарегистрировать
   HIF до power-on (BTIF? `wmt_chrdev_wifi`? наш собственный initcall?) —
   без этого шаг 3 не проверить.
2. **Порядок power-on**: DCXO/32k (clk_buf), EMI remap/MPU, AP_RGU — при ошибке
   в последовательности CONSYS молча висит; TRM нет, эталон — только этот код и
   стоковый dmesg.
3. **Прошивка**: `WIFI_RAM_CODE_6759` в нашем rootfs отсутствует (в `/lib/firmware`
   пусто); брать из RPM Aurora 5.2.1.200 (`refs/aurora-5.2.1.200.md`), в git не
   класть — проверить лицензионную допустимость распространения.
4. **WEXT/NL80211_TESTMODE как опции ядра**: включение меняет ABI заголовков;
   надо собирать ядро с ними, а не «дорисовывать `-D`» (в спайке это сделано
   только для оценки объёма).
5. `Module.symvers`/`modpost`: пока ядро собиралось без модулей, линковка `.ko`
   не проверена — возможны новые сюрпризы на этапе modpost (неизвестные символы
   из `cfg80211`-модуля).
6. Не проверено, что `-Werror`-предупреждения (91 шт., в основном
   `missing-prototypes`) — это только стиль: часть из них (`enum-int-mismatch`,
   `misleading-indentation`) может указывать на реальные баги вендора.
7. Оценки времени — по объёму правок, без учёта отладки на железе (её нет в этом
   майлстоуне).

---

## 12. Что не делали (сознательно)

- не трогали устройство, ничего не прошивали, recovery/SSH не использовали;
- не интегрировали код в `../linux-t1100`: `patches/series` не менялся, DTS не
  менялся, `scripts/` не менялся;
- не добавляли вендорский код в этот репозиторий (только этот журнал);
- не включали опции в `configs/t1100.fragment` — предложены, но не применены
  (решение за `lead`).

---

## 13. Воспроизведение

```sh
ssh l@172.17.141.172        # пароль 0
cd /home/l/t1100-wifi-src/spike
./build.sh r9               # rsync чистых клонов -> work, правки, make -k, сводка
grep -c 'error:' logs/r9-*.log
```

Чистые клоны: `/home/l/t1100-wifi-src/vendor/mediatek/kernel_modules/connectivity/{common,wlan}`
(не модифицируются; правки применяются к `spike/work/`). Логи r1…r9 сохранены
рядом.

---

# Майлстоун 2: собираемые модули (`wmt_drv.ko`, `wlan_drv_gen3.ko`)

Итог: **оба модуля линкуются под 6.12.114** (rc=0, modpost без ошибок и без
неразрешённых символов), воспроизводимо, без правок в `../linux-t1100`.
Этот рубеж **build-only**: на железе ничего не проверялось (§7 шаг 3 — power-on
CONSYS — впереди).

## 14. Готовые артефакты

| | `wmt_drv.ko` | `wlan_drv_gen3.ko` |
|---|---|---|
| sha256 | `0b4a2bfafc207a8b3639813215f02ad48110bbadbc718ab72da8efd9162924b4` | `cfd182c528133c3ea8d88f9510feae507816c491e19b4e10e7a0dd033b0638b8` |
| размер | 1 109 408 Б | 2 895 080 Б (сток 4.14: 4 083 080 Б) |
| `modinfo vermagic` | `6.12.114-g95e3b41b86-dirty SMP preempt mod_unload aarch64` | то же |
| `modinfo depends` | — | `cfg80211,wmt_drv` |
| `modinfo license` | GPL | GPL |
| экспортов `mtk_wcn_*` | 154 | (потребляет 9) |
| исходников | 39 объектов + наши stub'ы | 78 объектов + наши stub'ы |
| предупреждений компилятора | 65 | 376 |
| ошибок / неразрешённых символов | 0 / 0 | 0 / 0 |

Хеши воспроизводимы (две сборки подряд дают тот же sha256): вендорский
`DRIVER_BUILD_DATE` зафиксирован в Kbuild-обёртке (`?= 20261111`), иначе
`__DATE__`-строка меняла бы `.ko` каждую минуту.

Проверка:

```sh
modinfo build/wifi/wlan/wlan_drv_gen3.ko | grep -E 'vermagic|depends'
nm --defined-only build/wifi/common/wmt_drv.ko | grep -c ' T mtk_wcn_'   # 154
```

## 15. Что добавлено в репозиторий

| Путь | Что это |
|---|---|
| `scripts/build-wifi-remote.sh` | локальный драйвер: rsync порта на хост, при необходимости сборка ядра (за `Module.symvers`), сборка модулей, вытягивание `.ko` в `build/wifi/` |
| `scripts/remote/build-wifi-remote.sh` | хост-часть: чистая копия вендорских клонов → `wifi-patches/*.patch` → `make M=… modules`, сводка rc/ошибок/хешей |
| `scripts/remote/wifi-kbuild/{common,wlan}.Kbuild` | **свой Kbuild** вместо Android-Makefile: явные списки `obj-m`/`ccflags-y`, все `-D` (в т.ч. `MT6631`, `CONFIG_MTK_COMBO_CHIP` заменён на явные define'ы), `-include` compat-шимов, `KBUILD_EXTRA_SYMBOLS` для линковки wlan против wmt |
| `scripts/remote/wifi-compat/` | 14 заголовков: 12 из майлстоуна 1 + новые `mtk_port_414.h` (time API, `struct timeval`, `rtc_time_to_tm`, 32k/RTC) и `sdio_ops.h` (стаб MTK SDIO glue) |
| `scripts/remote/wifi-stubs/{wmt_stubs.c,wlan_stubs.c}` | заглушки с предупреждением в dmesg (см. §17) |
| `patches/wifi/0001-{common,wlan}-port-6.12.patch` | весь порт исходников: 18 файлов (+89/−74) WMT, 27 файлов (+321/−265) wlan |
| `configs/t1100-wifi.fragment` | опции ядра для сборки стека (`NL80211_TESTMODE`, `CFG80211_WEXT`, `IPW2200=m` — см. §16) |

Пайплайн целиком:

```sh
scripts/build-wifi-remote.sh                # ядро (если нет Module.symvers) + оба модуля
scripts/build-wifi-remote.sh --kernel       # принудительно пересобрать ядро
scripts/build-wifi-remote.sh wlan           # только один модуль
scripts/build-wifi-remote.sh --clean        # снести out/ и work/ на хосте
```

`../linux-t1100` не участвует: модули собираются out-of-tree против
out-дерева `/home/l/t1100-wifi-build/out`, которое собирается из снапшота
`/home/l/t1100-ubuntu-build/src` (тот же, что у `scripts/build-kernel-remote.sh`).

## 16. Конфиг ядра: почему понадобился отдельный фрагмент

`configs/t1100-wifi.fragment` (не влит в `configs/t1100.fragment`, потому что
меняет ABI заголовков):

| Опция | Зачем |
|---|---|
| `CONFIG_MODULES=y`, `CONFIG_CFG80211=m`, `CONFIG_MAC80211=m` | внешние модули; `depends: cfg80211` |
| `CONFIG_CFG80211_WEXT=y` | `net_device.wireless_handlers` (иначе `wext_handler_def` некуда девать) |
| `CONFIG_NL80211_TESTMODE=y` | `gl_cfg80211.h` содержит `#error` без него |
| `CONFIG_IPW2200=m` | **хак**: `CONFIG_WEXT_PRIV`/`WEXT_SPY` — скрытые `bool` без prompt'а в `net/wireless/Kconfig`, включить их можно только `select`'ом из драйвера. Драйверу нужен `WEXT_PRIV` (`struct iw_handler_def.num_private/private/private_args` живут под `#ifdef CONFIG_WEXT_PRIV`, а `gl_wext.c` регистрирует ровно их). `ipw2200.ko` не загружается, он в сборке только ради `select`. Альтернатива — патчить `net/wireless/Kconfig`, отказались |

Отдельное out-дерево (`/home/l/t1100-wifi-build/out`) — чтобы не менять
`.config` общего `/home/l/t1100-ubuntu-build/out`: `build-kernel-remote.sh`
перегенерирует его через `defconfig + fragment`, и наши опции оттуда исчезли бы
вместе с ABI-совпадением для модулей.

В дереве появился `Module.symvers` (`make Image modules`, ~17 мин на 12 ядрах
через ccache) — без него modpost не линкует внешние модули (риск 5 из §11).

## 17. Заглушки (stub'ы): что и почему

Все — в `scripts/remote/wifi-stubs/`, каждая печатает `pr_warn_once`
(`wmt_stub:`/`wlan_stub:`) при вызове: отказ на железе не должен выглядеть как
загадка. Ни одна не вызывается на пути, который нужен для power-on.

**`wmt_stubs.c`**

| Заглушка | Почему |
|---|---|
| `aee_kernel_warning_api`, `aed_combo_exception(_api)`, `aee_kernel_dal_show` | AEE/AED — Android-«синий экран» MTK, в mainline отсутствует; вызывается только на error-path |
| `sdio_detect_init/exit/do_autok`, `mtk_wcn_hif_sdio_*`, `mtk_wcn_stp_sdio_*`, `stp_sdio_rw_retry/retry_flag_get/wake_up_ctrl/txdbg_dump`, `g_stp_sdio_host_info`, `wifi_irq`, `mtk_wcn_cmb_sdio_pm_*` | SDIO-транспорт **не собирается**: у MT6631 на MT6771 HIF = AHB/WFDMA (`ahb_sdioLike`), объекты `hif_sdio.c`/`stp_sdio.c`/`sdio_detect.c` исключены из Kbuild; ядро WMT держит на них указатели |
| `mtk_wcn_stp_uart_drv_init/exit` | STP-over-UART нужен только для BT через UART (`stp_uart.c` исключён) |
| `wmt_step_init/deinit/print_version` | MTK factory step mode (`CFG_WMT_STEP` не включали) |
| `wmt_export_platform_bridge_register/unregister`, `wmt_export_mtk_wcn_cmb_sdio_disable_eirq` | это built-in половина WMT (`wmt_build_in_adapter.c` в MTK-ядре), у нас её нет; регистрация no-op |
| `connectivity_export_show_stack/dump_thread_state` | адаптерные обёртки из `connectivity_build_in_adapter.h` (haretic). `show_stack()` не экспортируется модулям → `sched_show_task()`/`dump_stack()` |
| `gConEmiPhyBase`, `gConEmiSize` | в стоке определяются в `wmt_plat`; у нас `EXPORT_SYMBOL` и **0** (EMI remap/MPU/coredump пропускаются — безопасный дефолт). **TODO(power-on)**: заполнять из DT (`consys-reserve-memory`) |

**`wlan_stubs.c`**: Android-хуки `register_set_p2p_mode_handler` (фреймворковый
колбэк P2P), `update_driver_loaded_status` (sysfs-флаг), `wifi_reset_start/end`
(HAL-хендшейк), `register_file_buf_handler` (NVRAM через Android-сервис),
`connectivity_export_show_stack`.

## 18. Правки исходников по темам

Полный список — в `patches/wifi/`; здесь смысл. Формат: тема → файлы → что
сделано.

**Общее для обоих модулей**

| Тема | Файлы | Правка |
|---|---|---|
| `proc_create()` берёт `struct proc_ops` (с 5.6) | `gl_proc.c` (10 структур), `gl_kal.c` (2), `wmt_dev.c`, `wmt_dbg.c` | `.owner` убран, `.read/.write` → `.proc_read/.proc_write`; сигнатуры обработчиков менять не пришлось — они совпадают у `file_operations`/`proc_ops` |
| time API | `common/debug.c`, `mgmt/stats.c`, `mgmt/wmm.c`, `gl_proc.c`, `gl_kal.c`, `wmt_dev.c`, `psm_core.c`, `osal.c`, `stp_dbg.c`, `connsys_debug_utility.c` | в wlan: `struct timeval` → `timespec64`, `do_gettimeofday` → `ktime_get_real_ts64`, `get_monotonic_boottime` → `ktime_get_boottime_ts64`, `rtc_time_to_tm` → `rtc_time64_to_tm`. В WMT — через compat-шим `mtk_port_414.h` (тот же код, без правки 12 мест) |
| `sched_clock()` | `common/debug.c`, `mgmt/stats.c`, `nic/nic_rx.c`, `ahb.c`, `gl_kal.c` | `#include <linux/sched/clock.h>` (переехал в 4.15) |
| `ioremap_nocache` (удалён в 5.9) | 26 мест в common (`mt6771.c`, `wmt_lib.c`, `wmt_ic_soc.c`, `wmt_dbg.c`, `wmt_step.c`, `mtk_wcn_consys_hw.c`, `connsys_debug_utility.c`), `wlan_lib.c` | → `ioremap()` |
| `platform_driver.remove` возвращает `void` (6.11) | `mtk_wcn_consys_hw.c`, `ahb.c` | `int foo()` → `void foo()`, `return 0` убран |
| `class_create()` без `THIS_MODULE` (6.4) | `wmt_dev.c`, `wmt_detect.c`, `fw_log_wmt.c` | `class_create("name")` |
| `timer_list` без `function`/`data` (4.15) | `osal.c`, `connsys_debug_utility.c`, `gl_kal.c` | `timer_setup()` + `from_timer()`; в wlan `kalTimeoutHandler(struct timer_list *)` |
| `set_fs`/`get_fs` (удалены в 5.10) | `gl_kal.c` | `kalFirmwareOpen/Close`: `mm_segment_t`/`set_fs` убраны (файл открывается `filp_open`, читается `kernel_read`); `kalFileRead/Write` → `kernel_read/kernel_write` с `loff_t`. Учётки по-прежнему переключаются на root — **TODO**: `prepare_creds()/commit_creds()` |
| `struct timeval` в uapi скрыт под `#ifndef __KERNEL__` | — | отсюда compat-шим (см. выше) |
| `#include <linux/wakelock.h>` (удалён 4.15) | 6 файлов | include убран (API `osal_wake_lock` уже на `wakeup_source`) |
| `wakeup_source_register(dev, name)` (5.4) | `osal.c` | добавлен `NULL` первым аргументом |
| `netif_rx_ni` (удалён 5.18) | `gl_kal.c` | `netif_rx()` (контекст-безопасен) |
| `access_ok(VERIFY_*, …)` без типа (5.0) | `gl_bow.c`, `gl_wext_priv.c` | `access_ok(addr, len)` |
| IPv6 | `gl_kal.c` | `net_device.ip6_ptr` → `__in6_dev_get()` + `<net/addrconf.h>` |
| `-Werror` вендора | `common/Makefile` | не нужен: вендорские Makefile в сборке не участвуют |

**cfg80211 (главный семантический блок)** — под 6.12 поменялись сигнатуры ops и
раскладка `wireless_dev`:

| Что | Файлы | Правка |
|---|---|---|
| key-ops получили `int link_id` | `gl_cfg80211.c`, `gl_p2p_cfg80211.c`, `gl_cfg80211.h`, `gl_p2p_ioctl.h` | аргумент добавлен (не используется, single-link) |
| `set_default_key` | там же | `+ int link_id` |
| `mgmt_frame_register` → `update_mgmt_frame_registrations` | `gl_init.c`, `gl_p2p.c` (таблицы ops), `gl_cfg80211.c`, `gl_p2p_cfg80211.c` | p2p-версия переписана на битмап `struct mgmt_frame_regs.interface_stypes` (бит N = subtype N, как и было в `switch`), wlan-версия была no-op внутри `#if 0` — оставлена no-op с комментарием |
| `change_beacon` | `gl_p2p_cfg80211.c` | `struct cfg80211_beacon_data *` → `struct cfg80211_ap_update *` (внутри `&info->beacon`) |
| `stop_ap`, `set_bitrate_mask` | `gl_p2p_cfg80211.c` | добавлен `link_id` |
| `tdls_mgmt` | `gl_cfg80211.c` | добавлен `int link_id` |
| `wireless_dev.current_bss` | `gl_cfg80211.c`, `gl_init.c`, `gl_p2p_cfg80211.c` | → `links[0].client.current_bss` |
| `wireless_dev.ssid_len` | `gl_init.c` | → `u.client.ssid_len` (**не** `links[0].client` — там только `current_bss`) |
| `cfg80211_roam_info.bss` | `gl_kal.c` | → `links[0].bss` |
| `station_parameters.{supported_rates,ht_capa,vht_capa}` | `gl_cfg80211.c` | → `link_sta_params.*` (в 6.12 переехали; TDLS оставлен включённым) |
| `ndo_select_queue` (accel_priv/fallback убраны в 5.2) | `gl_init.c`, `gl_os.h` | 3 аргумента |
| `MODULE_SUPPORTED_DEVICE` (удалён в 5.13) | `gl_init.c` | строка убрана (замены нет) |
| `sched_setscheduler` не экспортируется (5.9) | `gl_init.c` | `sched_set_fifo()`; **TODO**: `ucThreadScheduling`/`ucThreadPriority` не учитываются |

**WMT / SoC power-on (`mt6771.c`)** — из §5 остались ровно те 4 места:

| Строка | Было | Стало |
|---|---|---|
| `consys_clock_buffer_ctrl` | `KERNEL_clk_buf_ctrl(CLK_BUF_CONN, …)` | no-op + `WMT_PLAT_PR_DBG`; **TODO(power-on)**: если CONSYS не поднимается, искать гейт XO_WCN в infracfg |
| VCN18/VCN33 | `KERNEL_upmu_set_reg_value(MT6358_LDO_VCN*_OP_EN, 1)` + `regulator_*` | только `regulator_*` (регмап MT6358 в mainline сам ставит SW-режим) |
| `consys_vcn28_hw_mode_ctrl` | `KERNEL_pmic_set_register_value(PMIC_RG_LDO_VCN28_HW0_*)` | no-op + `PR_DBG`; **TODO**: `regulator_set_mode()`, если FM/co-clock потребует HW-режим |
| EMI remap | `ioremap_nocache` | `ioremap` |

Прочее в WMT: `rtc_gpio_enable_32k`/`RTC_GPIO_USER_GPS` — compat-заглушка
(CCF-гейт 32k у MT6771 в mainline отсутствует; **TODO(power-on)**).

## 19. Что не собирается и почему (осознанно)

| Объект | Причина | Как закрыто |
|---|---|---|
| `common_main/linux/hif_sdio.c`, `stp_sdio.c`, `common_detect/sdio_detect.c`, `common_main/platform/mtk_wcn_cmb_hw.c` | SDIO-транспорт (не наш HIF) | исключены из Kbuild, символы — в `wmt_stubs.c` |
| `common_main/linux/stp_uart.c` | tty API 6.12 (`tty_register_ldisc`, `tty_ldisc_ops`, `n_tty_ioctl_helper`, `low_latency`) — переписывать ради BT рано | исключён, стабы `mtk_wcn_stp_uart_drv_*` |
| `common_main/linux/wmt_step.c` | MTK factory step | исключён, стабы `wmt_step_*` |
| `common_main/platform/{mt6739,mt6755,mt6761,mt6763,mt6765}.c` | другие SoC (в патче только механические `ioremap`) | не входят в `wmt_drv-y` |
| `wlan/os/linux/hif/ahb_sdioLike/ahb_pdma.c` | MT6797-ветка PDMA (у нас CQDMA) | не входит; `ahb_cqdma.o` собирается |

## 20. Что осталось (следующий шаг)

1. **Power-on CONSYS в kernel-режиме** (§7 шаг 3): DT-узлы `consys@18070000` +
   `wifi@180f0000` + `consys-reserve-memory` 2 МиБ + `<&infracfg CLK_INFRA_CQ_DMA>`;
   заполнить `gConEmiPhyBase` из DT; проверить `clk_buf`/32k; ожидаемый первый
   признак — `wmt: power on ok` и чтение WCIR (`0x788`).
2. **STP-HIF для MT6631** (главный риск §11.1): кто регистрирует HIF до
   power-on — BTIF, `wmt_chrdev_wifi` или собственный initcall. Публичного
   `wmt_loader` нет; вероятно, нужна минимальная реализация ioctl поверх
   `/dev/stpwmt`.
3. `wlan_drv_gen3` **не собирается в `=y`** и не грузится автоматически: нужен
   rootfs с `cfg80211.ko`, `mac80211.ko`, `wmt_drv.ko`, `wlan_drv_gen3.ko` и
   прошивкой `WIFI_RAM_CODE_6759` в `/lib/firmware` (её ещё нет, см. §11.3).
4. Причесать предупреждения до `-Werror`-чистоты (243 `missing-prototypes`,
   108 `empty-body`, 15 `implicit-fallthrough`; цифры — по обоим модулям) — сейчас не блокирует; отдельно
   посмотреть `enum-int-mismatch` ×2 в `stp_core.c`/`wmt_plat_alps.c` и
   `misleading-indentation` в `nic_rx.c` (потенциально реальные баги вендора).
5. Оформить правки как upstream-серию (по одному патчу на тему, GPL-2.0-шапки
   уже есть в вендорских файлах) — сейчас это два крупных патча по компонентам.

## 21. M3 подготовка (build-only, 11.11)

Цель M3 — **первый power-on CONSYS** (`wmt: power on ok` + чтение WCIR `0x788`).
Всё ниже собрано и проверено офлайн; **на планшет ничего не прошивалось и не
загружалось** (там в это время шла работа по тачу, лид решил не менять два
фактора одновременно). Артефакты готовы к передаче.

### 21.1 Device Tree (патч ядра **0049**, узлы `status = "disabled"`)

Источник каждого числа — стоковый DTB этой платы; TRM MT6771 не публичен.

| Узел / свойство | Значение | Откуда |
|---|---|---|
| `consys@18070000` compatible | `mediatek,mt6771-consys` | `refs/stock-mt6771.dts:2206` |
| `reg` (0..3) | `0x18070000` (mcu), `0x10007000` (ap_rgu), `0x10001000` (topckgen), `0x10006000` (spm) | там же; порядок = `of_iomap()` в `common_main/platform/mt6771.c` |
| `interrupts` | `GIC_SPI 289` (AP), `GIC_SPI 291` (MD), обе `IRQ_TYPE_LEVEL_LOW` | сток `<0 0x121 8>`, `<0 0x123 8>`; флаги уходят в `request_irq()` как есть |
| `memory-region` | `&consys_reserve_memory` | наш `reserved-memory` (ниже) |
| `vcn18/vcn28/vcn33_bt/vcn33_wifi-supply` | MT6358 `vcn18`, `vcn28`, `vcn33` (последние два — один rail) | сток `:1244-1258`; в mainline `mt6358_sync_vcn33_setting()` синхронизирует биты WIFI/BT |
| `consys-reserve-memory` | 2 МиБ, `no-map`, `alignment` 2 МиБ, `alloc-ranges = <0 0x40000000 0 0x80000000>` | сток `:460-466` (там тоже без `reg`: адрес выбирал аллокатор, в стоке вышло `0xbfc00000`) |
| `wifi@180f0000` compatible | `mediatek,wifi` | сток `:1687` |
| `reg` (0..3) | `0x180f0000` (WFDMA), `0x10212180` (CQDMA ch2), `0x10001000` (infra), `0x180e0000` (CONN_CFG) | там же; порядок = `of_iomap()` в `os/linux/hif/ahb_sdioLike/ahb.c` |
| `interrupts` | `GIC_SPI 290` (HIF), `GIC_SPI 118` (HIF DMA), level-low | сток `<0 0x122 8>`, `<0 0x76 8>` |
| `clocks` | `<&infracfg CLK_INFRA_CQ_DMA>`, `clock-names = "wifi-dma"` | гейт `INFRA2[27]` (`clk-mt8183.c:782`); см. ниже |
| `hardware-values` | `<0x788 0xa5800 0xa5800>` | сток; [0] — ожидаемый WCIR chip id (`nic/nic.c:655-676`), [1]/[2] — адреса загрузки/старта прошивки (`wlan_lib.c:550-560`) |

Четыре решения, которые отличаются от механического копирования стока:

1. **У `consys` нет `clocks`.** В стоке `clocks = <&scpsys 2>` (имя `conn`), но это
   вендорский clock-provider `mediatek,scpsys`, которого в mainline нет. При этом
   `CONSYS_PWR_ON_OFF_API_AVAILABLE` для MT6771 не определён → в
   `consys_hw_power_ctrl()` работает ветка `#else`, которая поднимает домен
   **регистрами SPM** (`0x1000632c`), а `clk_prepare_enable(clk_scp_conn_main)` не
   вызывается вообще. Перекрёстная проверка: `0x32c` — это ровно `ctl_offs`
   у `MT8183_POWER_DOMAIN_CONN` в `drivers/pmdomain/mediatek/mt8183-pm-domains.h`.
   Поэтому: clock-провайдера не выдумываем, `power-domains` не ставим (genpd писал
   бы тот же регистр за спиной драйвера), а драйвер правим так, чтобы отсутствие
   клока не валило probe (см. 21.2).
2. **`consys-reserve-memory` — с `alloc-ranges`, без `reg`.** Фиксированный `reg`
   проверяется LK по его собственным mblock-блокам (`reserved_memory_conflict_check`,
   `docs/lk-dtb-rules.md`) и может подвесить загрузку. С `alloc-ranges` ядро само
   выбирает свободное окно (в стоке вышло `0xbfc00000`), а драйвер читает результат
   через `memory-region` (21.2). Отдельная проверка на это — LK-валидатор, см. 21.4.
3. **`wifi-dma` = `CLK_INFRA_CQ_DMA`**, а не числовой ID `0x4e` из стока: `0x4e`
   (78) — это ID **таблицы topckgen MT6771**, и привязывать его к биндингам mt8183
   нельзя (там 78 = `CLK_TOP_APLL2_D4`). Гейт того же блока в mainline —
   `infra_cqdma`, `INFRA2[27]`; соседний `cq_dma@10212000` в стоке тактируется тем
   же `<0x15 0x4e>`, т.е. это один и тот же клок.
4. **`vcn33_bt` и `vcn33_wifi` — один и тот же rail** `&mt6358_vcn33_reg`:
   `regulator_get()` зовётся по именам свойств, а mainline-драйвер MT6358 держит
   биты WIFI/BT синхронно.

### 21.2 Драйверная часть (патч вендора `patches/wifi/0002-common-consys-power-on-dt.patch`)

| Что | Файл | Правка |
|---|---|---|
| `gConEmiPhyBase/gConEmiSize` из DT | `common_main/platform/mtk_wcn_consys_hw.c` | новая `mtk_wmt_consys_emi_from_dt(pdev)`, зовётся в `mtk_wmt_probe()` перед `if (gConEmiPhyBase)`: `of_parse_phandle(...,"memory-region",0)` → `of_reserved_mem_lookup()` (работает и для `alloc-ranges`-регионов) → fallback `of_address_to_resource()`; пишет `WMT_PLAT_PR_INFO("CONNSYS EMI from DT: phys 0x%pa size 0x%pa")`. При неудаче — `PR_ERR` и EMI remap/MPU/coredump остаются выключенными (безопасный дефолт) |
| клок `conn` больше не валит probe | `common_main/platform/mt6771.c` | `devm_clk_get()` → `devm_clk_get_optional()`; `NULL` = норма (power-on идёт через SPM), ошибка логируется и тоже не фатальна |
| рельсы не роняют power-on | там же | `regulator_get()` в `consys_pmic_get_from_dts()`: `ERR_PTR` нормализуется в `NULL` (вендор проверял только `!reg`, а `regulator_enable(ERR_PTR)` — падение), отсутствующий rail пропускается с `PR_ERR` |
| `CONFIG_MTK_COMBO_CHIP="CONSYS_6771"` | `scripts/remote/build-wifi-remote.sh` | переменная передаётся в `make` и печатается в лог (как в вендорском Makefile, **в кавычках**). Реальный выбор чипа у нас — в Kbuild-обёртках (`mt6771.o` в списке объектов + `-DMT6631` для wlan); в C-коде эта переменная не читается (проверено grep’ом) |

Kbuild-врапперы уже интегрированы в `scripts/build-wifi-remote.sh` →
`scripts/remote/build-wifi-remote.sh`: на хосте `patches/wifi/` целиком
раскладывается в `wifi-patches/` и применяется по маске `*common*`/`*wlan*`
(`patch -p1`), затем `make -C <kernel-out> M=<work>/<m> modules` с
`KBUILD_EXTRA_SYMBOLS` на `Module.symvers` соседа. Новый патч подхватывается этой
же маской, отдельной проводки не требует.

### 21.3 Артефакты (собрано на build-хосте, 11.11)

База: `../linux-t1100` @ **`675178729`** (`arm64: dts: t1100: finish the touch
wiring`) + патч 0049 поверх, рабочее дерево dirty -> `vermagic`
`-g675178729a-dirty`. Образ сознательно собран на текущем HEAD, а не на более
раннем: иначе прошивка M3-образа откатила бы тач-патчи 0047/0048 (оба узла
`consys`/`wifi` при этом `disabled`, т.е. поведение образа равно обычной сборке
HEAD, кроме наличия Wi-Fi-узлов и модулей в конфиге).

| Файл | Размер | sha256 |
|---|---|---|
| `build/boot_ubuntu41.img` | 33 554 432 | `0c21c2f3261bae95456923fb9b79ff9780d73e196929ea89e2b6274997a9589e` |
| `build/remote/Image` | 39 873 024 | `696ce20e1bb51038cda80a2be13a5a76b6f2b8761eb8d1a5b2442480d03da9d7` |
| `build/remote/dtbs/mt6771-fplus-t1100.dtb` | 53 774 | `bebd312f62e5f7089d4d6715ab90d8da1eb72796486b348cb78acf12c665fa33` |
| `build/wifi/common/wmt_drv.ko` | 1 111 976 | `cc2f061d59824e25677837a751166c516be58cd1cf6016f6811a16f87031176a` |
| `build/wifi/wlan/wlan_drv_gen3.ko` | 2 895 080 | `ba69c10fddc6377104d81e7f11054ae2aff858701f87426560c49ce8ee6c413c` |
| `build/remote/modules/cfg80211.ko` | 614 888 | `e30338f8deca783e7dc05bc5089d33e7b30303ef62830686f023240f6e531eb2` |
| `build/remote/modules/mac80211.ko` | 812 160 | `c8acef164e762f1696416b35581b646cc04d7985a1ee9a6aeec149fab8088732` |
| `build/remote/modules/rfkill.ko` | 48 272 | `d765f5662bdcb8e2c481223ecf214178dc70468d11e45fa726bcb788901c67ee` |

`vermagic` у всех пяти модулей и у `Image` один и тот же:

```
6.12.114-g675178729a-dirty SMP preempt mod_unload aarch64
```

Детали, которые важны для воспроизведения:

- Ядро образа собрано **с тем же конфигом, что и вендорские модули**:
  `defconfig + configs/t1100.fragment + configs/t1100-wifi.fragment`. Parity
  доказывается побайтово: `cfg80211.ko`/`mac80211.ko`, собранные в
  `/home/l/t1100-ubuntu-build/out`, совпали по sha256 с версиями из
  `/home/l/t1100-wifi-build/out`. Это принципиально: `CONFIG_WEXT_PRIV`
  (его включает `ipw2200`) меняет раскладку `struct iw_handler_def`, а
  `WEXT_CORE/WEXT_SPY` — built-in, поэтому `cfg80211.ko` из «чужого» out-дерева
  либо не слинкуется по символам, либо разъедется по ABI (§16).
- Для этого в `scripts/build-kernel-remote.sh` добавлены `EXTRA_FRAGMENTS`
  (доп. фрагменты) и `--modules` (собрать и забрать `cfg80211/mac80211/rfkill`).
- `wmt_drv.ko` изменился из-за патча 0002: `0b4a2bfa…` (1 109 408 Б, M2) →
  `cc2f061d…` (1 111 976 Б, +2 568 Б). `wlan_drv_gen3.ko` меняется только
  встроенным `vermagic` (сборка воспроизводима: `DRIVER_BUILD_DATE`
  зафиксирован — на одном и том же base-коммите он побайтово равен версии M2,
  `cfd182c5…`).
- Warnings: common 65 / wlan 376, ошибок 0, undefined 0 — как в M2.
- `EXTRA_FRAGMENTS`/`--modules` — единственное изменение конфига образа
  относительно `boot_ubuntu40`; дисплей/GPU/тач-опции не менялись.
- Образ перепакован из `boot_ubuntu40.img` как шаблона заголовка
  (`kernel_addr 0x40080000`, `ramdisk_addr 0x55000000`, `tags 0x54000000`,
  `dtb_addr 0x54000000`, page 0x800), ramdisk — `build/initramfs_root_usb.cpio.gz`
  (тот же, что в 40). **Имя:** `boot_ubuntu35.img` уже занят рабочим
  откатным образом (11.11 17:29), поэтому M3-образ назван `boot_ubuntu41.img`;
  в `docs/STATUS.md`/`handover.md` имя надо поправить.
- Воспроизведение одной командой (порядок важен: второй скрипт берёт src-snapshot
  первого):

  ```sh
  KERNEL_SRC=<worktree с 0049> EXTRA_FRAGMENTS=configs/t1100-wifi.fragment \
      scripts/build-kernel-remote.sh --modules
  KERNEL_SRC=<тот же worktree> scripts/build-wifi-remote.sh --kernel
  gzip -9 -c build/remote/Image > /tmp/Image.gz
  python3 scripts/repack_boot.py --ref build/boot_ubuntu40.img \
      --kernel /tmp/Image.gz --ramdisk build/initramfs_root_usb.cpio.gz \
      --dtb build/remote/dtbs/mt6771-fplus-t1100.dtb --out build/boot_ubuntu41.img
  ```

  Любое движение дерева (новый коммит/патч) меняет `vermagic`, поэтому ядро и
  модули пересобираются **только парой** — иначе `insmod` откажет.

### 21.4 Проверки до прошивки

- `make dtbs` — DTB собирается, `dtc` без ошибок (53 774 Б с тач-патчами).
- `tools/lk/verify-dtb.sh` на DTB из дерева и на DTB, вынутом из
  `boot_ubuntu41.img` (`scripts/bootimg_extract.py`; sha256 совпал —
  `bebd312f…`): `RESULT: LK should accept
  this DTB`, оверлей `dtbo_a` применяется, размер 88 713 ≤ 524 288,
  `/reserved-memory/ramoops@70000000` чист по mblock’ам. У `consys-reserve-memory`
  `reg` нет вообще, поэтому LK-конфликт-чек его не рассматривает (в этом и смысл
  `alloc-ranges`).
- Патчи 0047+0048 (тач) + 0049 применяются в этом порядке чисто
  (`git apply --check` в worktree на `95e3b41b8`).

### 21.5 Деплой модулей (не выполнен)

```sh
tools/host/wifi-deploy.sh              # план, ничего не делает
tools/host/wifi-deploy.sh --apply      # .ko в /lib/modules/<release>/updates/wifi,
                                       # depmod -a, unit в /etc/systemd/system, daemon-reload
tools/host/wifi-deploy.sh --apply --enable   # + systemctl enable (не start)
tools/host/wifi-deploy.sh --status     # что лежит/загружено
```

Скрипт берёт `release` из `vermagic` самого `wmt_drv.ko`, сравнивает с
`uname -r` на планшете и при расхождении отказывается работать (`--force` —
только чтобы разложить файлы). Юнит
`rootfs-overlay/etc/systemd/system/t1100-wifi.service`: `modprobe wmt_drv` →
пауза 2 с + `dmesg`-хвост → `modprobe wlan_drv_gen3`, `ConditionPathExistsGlob`
по `.../updates/wifi/wmt_drv.ko`, `WantedBy=multi-user.target` (по умолчанию
**не включён**). `cfg80211` подтягивается как зависимость (`depends=cfg80211,wmt_drv`).

### 21.6 План первой проверки на железе (M3)

Предусловие: прошит `build/boot_ubuntu41.img` (бэкап `boot_a` сделан, откат —
`boot_ubuntu40`/`boot_ubuntu33`), панель/тач/GPU проверены, питание не ниже 3.8 В
(`t1100-power-guard`).

1. `uname -r` → `6.12.114-g675178729a-dirty`; `tools/host/wifi-deploy.sh --apply`.
2. `insmod`-эквивалент: `tools/host/wifi-deploy.sh --load wmt` (или
   `modprobe wmt_drv` вручную).
3. **Ожидаемый dmesg (порядок):**
   - `[CCF]no "conn" clock in DT, power-on uses the SPM sequence` — норма;
   - `CONNSYS EMI from DT: phys 0x… size 0x200000` (адрес выберет аллокатор;
     в стоке было `0xbfc00000`);
   - `Clearing Connsys EMI (virtual(0x…) physical(0x…)) 2097152 bytes`;
   - `[WMT-CORE]`/`[WMT-PLAT]` power-on: **`wmt: power on ok`**;
   - чтение WCIR: chip id **`0x788`** (`polling_consys_chipid`), без
     `consys emi memory address gConEmiPhyBase invalid`.
4. Признак успеха M3 = `wmt: power on ok` + chip id `0x788`, `/proc/wmt`-узлы
   живы, панель/тач не пострадали. Загрузка прошивки Wi-Fi-части в M3 не
   требуется.
5. Затем `--load wlan` (`modprobe wlan_drv_gen3`): ожидаемо — HIF init
   (`HifRegBaseAddr`, `WIFI-HIF irq 290`, `HIF DMA irq 118`), попытка скачать
   `WIFI_RAM_CODE_6759` и **отказ, если прошивки нет** в `/lib/firmware`
   (её в rootfs пока нет: взять из Aurora RPM-репозитория, см.
   `refs/aurora-5.2.1.200.md`). `wlan0` в M3 не обязателен.

Типичные отказы и что это значит:

| Симптом | Причина | Что делать |
|---|---|---|
| `wmt_core_stp_init: no hif info!`, затем `opfunc_pwr_on ... fail (-8)` | не зарегистрирован STP-HIF (`WMT_OP_HIF_BIT`) — тот самый риск §11.1: публичного `wmt_loader` нет | это не power-on CONSYS, а слой выше: минимальный STP-init ioctl поверх `/dev/stpwmt` (или разбор, кто в стоке зовёт `mtk_wcn_stp_*_drv_init`) |
| нет `power on ok`, `polling_consys_chipid` висит/таймаут | SPM-последовательность (`0x1000632c`) не подняла домен или VCN33 не включён | `regulator_summary` (vcn33/VCN18), `cat /proc/wmt` (если успел создать), проверить, что `of_iomap`-окна 0..3 замапились (dmesg `Get … register base`) |
| `-110` (`ETIMEDOUT`) на STP/HIF | handshake не прошёл: нет IRQ, не скачана прошивка или HIF не в AHB-режиме | сначала убедиться, что power-on был; `/proc/interrupts` (290/118 должны считать), затем firmware в `/lib/firmware` |
| `version magic … should be 6.12.114-…` при `insmod` | образ и модули из разных сборок | пересобрать пару (`--modules`/`--kernel`) и перепаковать образ |
| `Unknown symbol rfkill_*` / `wext` при `insmod cfg80211` | в `/lib/modules` попал `cfg80211.ko` из «чужого» out-дерева | класть только из `build/remote/modules/` (этого же out-дерева) |
| `Regulator_get VCN33_WIFI fail` | нет supply в DT / mt6358 ещё не поднялся | проверить `regulator_summary`, порядок probe (mt6358 раньше, чем wmt_drv) |

Риски, которые это не снимает: (а) STP-HIF для MT6631 (главный, §11.1);
(б) прошивки `WIFI_RAM_CODE_6759`/`WMT_SOC.cfg` в rootfs нет — до неё `wlan0` не
появится; (в) `clk_buf`/32k (`rtc_gpio_enable_32k` — заглушка) может понадобиться
для стабильного XO_WCN; (г) `power on ok` — это про WMT-слой, а не про рабочий
Wi-Fi.

## 22. M3: модули под `-touch-rot` (12.11)

Планшет перевели на **ядро второго разработчика**: `uname -r` =
`6.12.114-g400cb6f-touch-rot`, `Image` внутри прошитого
`build/boot_merged12.img` (sha256 самого boot-образа `651ab53c…`). Наши модули
от 11.11 собраны под `-g675178729a-dirty` и на этом ядре не загрузятся, поэтому
набор `ядро + модули` пересобран **против того же out-дерева**, что и ядро.
Устройство не трогали: всё на build-хосте, `../linux-t1100` не менялось.

### 22.1 Что с чем сверяли

| | |
|---|---|
| src (чужое дерево, без `.git`) | `/home/l/t1100-ubuntu-build/src` |
| out-дерево второго разработчика | `/home/l/t1100-ubuntu-build/out-normal` (`kernel.release` = `6.12.114-g400cb6f-touch-rot`, `Image` 39 873 024 Б) |
| vermagic ядра (из `Image`) | `6.12.114-g400cb6f-touch-rot SMP preempt mod_unload aarch64` |
| наша рабочая копия out-дерева | `/home/l/t1100-wifi-build/out-norm` (rsync-копия, чужое дерево **не** модифицировали) |

`CONFIG_MODVERSIONS` в конфиге **не выставлен**, поэтому CRC символов не
сверяются — совпасть должны только vermagic и наличие экспортов. Это упрощает
задачу, но не отменяет её: `include/config/kernel.release` перегенерируется
**на каждом** запуске `make` (filechk + FORCE), и без `LOCALVERSION` релиз
схлопывается в голый `6.12.114`, а модули получают чужой vermagic:

```
$ make -s -C src O=out-norm kernelrelease                        -> 6.12.114
$ make -s -C src O=out-norm LOCALVERSION=-g400cb6f-touch-rot kernelrelease
                                                                 -> 6.12.114-g400cb6f-touch-rot
```

Поэтому `scripts/build-wifi-remote.sh` теперь принимает `KERNEL_OUT` и
`LOCALVERSION` и передаёт суффикс в **каждый** `make` (включая сборку внешних
модулей), а host-скрипт после сборки сверяет `kernel.release` до/после и падает,
если он изменился.

### 22.2 Чего в чужом конфиге не хватало (и почему это не косметика)

`out-normal/.config` собран **без** `configs/t1100-wifi.fragment`, поэтому
`wlan_drv_gen3.ko` сначала не компилировался вовсе:

```
gl_p2p_ioctl.h:447:2: error: #error "Please ENABLE kernel config (CONFIG_NL80211_TESTMODE)"
gl_cfg80211.h:60:9: error: unknown type name ‘NL80211_DRIVER_TEST_MODE_PARAMS’
```

Разбор по опциям (что реально влияет на ABI, а что только на компиляцию):

| Опция | Где | Влияние |
|---|---|---|
| `CONFIG_NL80211_TESTMODE` | `struct cfg80211_ops` (`include/net/cfg80211.h:4855`) | **ABI**: добавляет `testmode_cmd/testmode_dump`. Драйвер заполняет эту структуру, `cfg80211.ko` её обходит по смещениям -> модуль и `cfg80211.ko` обязаны совпадать |
| `CONFIG_CFG80211_WEXT` | `struct wiphy` (`:5889`), `struct wireless_dev` (`:6509`) | **ABI**, но `wiphy` аллоцирует `cfg80211.ko` -> включать только если `cfg80211.ko` собран так же. Мы **не** включали (см. ниже) |
| `CONFIG_WEXT_PRIV` | `struct iw_handler_def` (`include/net/iw_handler.h:334`) | только компиляция `gl_wext.c` (`.num_private/.private/.private_args`); на ядре без wext эту структуру никто не читает |
| `CONFIG_WEXT_CORE` | `net/socket.c` -> `wext_handle_ioctl` | built-in bool, живёт в **vmlinux**; в чужом ядре отсутствует |

Рецепт, который не трогает чужое дерево и не ломает ABI:

- в копии out-дерева включена **одна** опция — `CONFIG_NL80211_TESTMODE=y`
  (`diff` конфига = 1 строка), после чего из этого же дерева пересобраны
  `cfg80211.ko`, `mac80211.ko`, `rfkill.ko`, `libarc4.ko` (в чужом конфиге они
  `=m`, значит на планшете их взять неоткуда — их тоже надо класть);
- `wlan.Kbuild` при отсутствии этих опций в конфиге ядра добавляет
  `-DCONFIG_NL80211_TESTMODE=1` и `-DCONFIG_WEXT_PRIV=1` (в нашем собственном
  ядре условия не срабатывают — там опции уже есть);
- `CONFIG_CFG80211_WEXT` **не** включался: он меняет раскладку `struct wiphy`/
  `wireless_dev`, а `cfg80211.ko` с `wext-compat.o` потянул бы символы
  `wext-core.o`, которые в чужом vmlinux отсутствуют (это built-in в vmlinux,
  модулем их не поставить). Итог: у вендорского драйвера `wiphy->wext` не
  заполняется (`#ifdef` в `gl_init.c:1665`), приватные ioctl (`iwconfig`/`iwpriv`)
  на этом ядре недоступны, всё остальное идёт через nl80211;
- `wireless_send_event()` — единственный неразрешённый символ (он тоже из
  `wext-core.o`). Добавлена заглушка `scripts/remote/wifi-stubs/wext_stub.c`
  (`pr_warn_once` + дроп события), подключается только при
  `CONFIG_WEXT_CORE` != y.

### 22.3 Артефакты

База: чужое дерево `/home/l/t1100-ubuntu-build/src` + `out-normal`,
`LOCALVERSION=-g400cb6f-touch-rot`, копия out-дерева
`/home/l/t1100-wifi-build/out-norm` (+1 опция `NL80211_TESTMODE=y`),
`DRIVER_BUILD_DATE=20261111` (сборка воспроизводима: повторный прогон даёт те же
sha256).

| Файл | Размер | sha256 |
|---|---|---|
| `build/wifi/common/wmt_drv.ko` | 1 111 976 | `8228dd5c28700eea37cf8c8bb4ad833ef30ce406b75c4b381879a9ef849bbead` |
| `build/wifi/wlan/wlan_drv_gen3.ko` | 2 895 440 | `4bbdb1d51f2c4dc6277bc1c5117a0af4317b03aa1c8d36d93bcd302a4e5f2b91` |
| `build/wifi/kernel/cfg80211.ko` | 576 448 | `ae891d542036dd436b539c7837e268725dc563b4669566437a7b07935c2ef2e0` |
| `build/wifi/kernel/mac80211.ko` | 811 792 | `b4ad9b62349fdebf2fc9917437a8d628221ad3751b986f3d86c8691777caee38` |
| `build/wifi/kernel/rfkill.ko` | 48 272 | `e6bbcb7b510314457aea0b946aed862ae490ee25a7a33b19ee3a37e8a1308ab1` |
| `build/wifi/kernel/libarc4.ko` | 5 192 | `a38b5be1648431f86a5ed406004837b3ced668f6f49a0b9d5de190af922e9ef3` |

`vermagic` у всех шести — ровно как у прошитого ядра:

```
6.12.114-g400cb6f-touch-rot SMP preempt mod_unload aarch64
```

`wmt_drv.ko` побайтово совпал с версией 11.11 (`8228dd5c…`, 1 111 976 Б) — его
код от конфига не зависит, меняется только встроенный vermagic, но он же и
собран из того же исходника; `wlan_drv_gen3.ko` = `4bbdb1d5…` (2 895 440 Б,
+360 Б к версии 11.11 за счёт stub'а `wext_stub.o` и флагов).

### 22.4 Проверки (build-хост, без устройства)

- `vermagic` всех `.ko` сравнён **с ядром** (`strings Image | grep -m1 "6.12.114"`),
  а не только с `kernel.release`: совпадение посимвольное.
- Замыкание символов: для каждого `.ko` множество `nm -u` покрывается
  `out-normal/vmlinux.symvers` (15 271 экспорт ядра) + экспортами остальных
  модулей набора. Неразрешённых — **0** у всех шести.
- `depmod -b <root> 6.12.114-g400cb6f-touch-rot` + `modprobe --show-depends`
  дают ожидаемый граф (собран из реальных ссылок, `depends=` в `.modinfo` при
  одноцелевой in-tree сборке пустой — см. 22.5):

  ```
  wlan_drv_gen3 -> rfkill, cfg80211, wmt_drv, wlan_drv_gen3
  mac80211      -> rfkill, cfg80211, libarc4, mac80211
  ```
- Обе сборки вендорских модулей: `errors=0 undefined=0` (warnings 65/376 — как в
  M2), `release` до/после не изменился.

### 22.5 Как воспроизвести

```sh
# 1. копия чужого out-дерева (чужое не трогаем) + один прогон ядерных модулей
rsync -a /home/l/t1100-ubuntu-build/out-normal/ /home/l/t1100-wifi-build/out-norm/
KERNEL_OUT=/home/l/t1100-wifi-build/out-norm LOCALVERSION=-g400cb6f-touch-rot \
    scripts/build-wifi-remote.sh --kernel-mods     # +Module.symvers, cfg80211/mac80211/rfkill/libarc4

# 2. вендорские модули против того же out-дерева (достаточно KERNEL_OUT)
KERNEL_OUT=/home/l/t1100-wifi-build/out-norm LOCALVERSION=-g400cb6f-touch-rot \
    scripts/build-wifi-remote.sh
```

`--kernel-mods` (`scripts/remote/build-kmods-remote.sh`) делает три вещи, без
которых внешние модули не собрать:

1. `make Image` не создаёт `Module.symvers` вовсе (в 6.12 есть только
   `vmlinux.symvers`) — таблица собирается как `vmlinux.symvers` + экспорты
   собранных модулей;
2. в 6.12 in-tree `modpost` берёт вход из `vmlinux.o` и **не** читает
   `Module.symvers`, поэтому одноцелевая сборка (`make net/wireless/cfg80211.ko`)
   видит межмодульные символы как undefined -> `KBUILD_MODPOST_WARN=1`
   (с `MODVERSIONS=n` на код это не влияет; граф зависимостей всё равно
   пересчитывает `depmod` на планшете);
3. `--enable-testmode` включает `CONFIG_NL80211_TESTMODE` (wrapper включает его
   сам, если в целевом конфиге опции нет).

### 22.6 Ограничения и риски

- **Нет WEXT**: `CONFIG_CFG80211_WEXT`/`WEXT_*` в этом ядре не включить без
  пересборки самого ядра, а `wext-core.o` — built-in. `iwconfig`/`iwpriv` и
  приватные ioctl MTK на этом ядре работать не будут; `wpa_supplicant`/
  NetworkManager (nl80211) — будут. Полный паритет с нашим ядром = пересобрать
  ядро второго разработчика с `configs/t1100-wifi.fragment` (тогда
  `wext_stub.c` и `-D`-флаги автоматически выключаются).
- **Прошитый `Image` ≠ `out-normal/Image`**: в `boot_merged12.img` лежит gzip
  от 07:44 (`Image` после распаковки — sha256 `4ae0061f…`), а в `out-normal` —
  от 08:45 (`58af9c93…`). Релиз/vermagic одинаковые, `MODVERSIONS` выключен,
  но набор экспортов у этих двух сборок мы сверить не можем (symvers 07:44 не
  сохранился). Если на планшете `insmod` скажет `Unknown symbol` — ядро и
  модули надо пересобрать парой из одного состояния дерева.
- **`cfg80211.ko` обязателен свой**: пара `wlan_drv_gen3.ko` + `cfg80211.ko`
  связана раскладкой `struct cfg80211_ops` (testmode). Чужой/системный
  `cfg80211.ko` (без `NL80211_TESTMODE`) с этим `wlan_drv_gen3.ko` использовать
  нельзя — рассинхрон layout.
- Прошивки `WIFI_RAM_CODE_6759`/`WMT_SOC.cfg` в rootfs по-прежнему нет (см.
  §21.6), так что `wlan0` после загрузки модулей не появится.

### 22.7 Деплой (не выполнялся — устройство у лида)

`tools/host/wifi-deploy.sh` обновлён под этот релиз:

- `cfg80211/mac80211/rfkill/libarc4` берутся из `build/wifi/kernel/` (а не из
  `build/remote/modules/`, где лежали модули старого ядра);
- release извлекается из `vermagic` `wmt_drv.ko` (`strings`, без зависимости от
  kmod — его нет на локальной машине), суффикс `-touch-rot` сохраняется целиком;
- **проверяется vermagic каждого `.ko` набора**, а не только `wmt_drv.ko`:
  разнопрошивочный набор отбрасывается с кодом 4 до всякой сети;
- сверка с `uname -r` планшета осталась прежней (сравнение полной строки релиза).

```sh
tools/host/wifi-deploy.sh              # план
tools/host/wifi-deploy.sh --apply      # .ko -> /lib/modules/6.12.114-g400cb6f-touch-rot/updates/wifi, depmod, unit
tools/host/wifi-deploy.sh --status
tools/host/wifi-deploy.sh --load wmt   # modprobe wmt_drv + dmesg (M3)
```

Ядро менять не нужно: на планшете уже `6.12.114-g400cb6f-touch-rot`; нужны
только модули из таблицы 22.3.

## 23. M4: объединённое дерево, включённые consys/wifi (12–13.11)

Цель M4 — пара «ядро + модули», в которой DTB уже описывает CONSYS и HIF
MT6631 **включёнными**, чтобы `wmt_drv` при загрузке начинал power-on. Всё
сделано на build-хосте; устройство не трогали, `boot_a` не писали,
`../linux-t1100` и `t1100-ubuntu-build/src` не менялись.

### 23.1 Из чего собрано дерево

Источник — наш git, а не чужой каталог на хосте:

- `../linux-t1100`, HEAD `675178729` («arm64: dts: t1100: finish the touch
  wiring», 51 коммит = патчи 0001–0048), rsync **без `.git`** в **новый**
  каталог `/home/l/t1100-merge-src` (старый `t1100-ubuntu-build/src`
  не использовался и не изменялся);
- поверх — `patch -p1` для 0046 и 0049–0052, плюс новый 0056 (включение
  узлов; номера 0054/0055 к моменту коммита занял upstream под iio, поэтому
  наш патч идёт последним).

| патч | sha256 | как легло |
|---|---|---|
| 0046 `drm/panel: it6112: fix the frame shift…` | `d2a012e2437b9ba2100473743e4a7ccfd389371312ee5217c08c47274f35e4eb` | чисто (offset −1) |
| 0049 `arm64: dts: t1100: describe CONSYS…` | `ed239c71202e815ce1da69a6ee5aeeef198f97d29a1210459b94118b7333cf96` | чисто (offset 26) |
| 0050 `…swap the touch axes for the landscape panel` | `efdd25d29c02de9322f7809153c7794763399ec8db5818c2b384f054edfe1068` | чисто |
| 0051 `…use native portrait touch coordinates` | `f288534fac75a720ea988dfa426535eb7e57dc4222d044d95127ce881bc6e443` | чисто, fuzz 1 (offset 10) |
| 0052 `drm/panel: it6112: move 44 more vblank lines…` | `67507045b8c16b61a5e47c8f85a482cdf199a297b8e775d27f7997512f99d4fd` | чисто, после перебазирования (см. ниже) |
| 0056 `arm64: dts: t1100: enable CONSYS and the MT6631 Wi-Fi HIF` | `469282c010e96104cdb3e8a99022f2e8e21ce7ba7af32cd2ade9d786775faa93` | чисто (новый) |

Три вещи, которые пришлось решать по ходу (и почему):

1. **0046 в дереве отсутствовал.** `patches/series` опережает `../linux-t1100`
   на 0046–0056: в HEAD есть 0001–0048, но сдвига кадра (0046) в
   `panel-it6112-*.c` нет — там vendor-пори (`vbp 28 / vfp 220`). Без 0046
   патч 0052 не накладывается, а панель получила бы сдвинутый на 212 строк
   кадр. Поэтому 0046 применён как часть merge (проверено: после него в файле
   `vsync_end = 2176 + 8 + 240`, `vtotal = … + 240 + 8`).
2. **0052 перебазирован.** В дереве второго разработчика 0046 писал другой
   текст комментария («EXPERIMENT: the image comes out shifted…»), у нас —
   свой («The panel shows the frame ~212 lines early…»); `patch` не находил
   контекст (изменяемая часть хунка — как раз комментарий). Функциональная
   часть (vbp 240→284, refresh 58.93 Гц) не менялась, переписаны только
   `-`-строки комментария. sha256 файла поэтому новый: `d27ddcb7…` →
   `67507045…`; патч после правки проверен отдельным прогоном на состоянии
   «после 0046» — накладывается чисто и даёт тот же файл.
3. **0051 применился с fuzz 1** (у нас между 0050 и 0051 чуть иные
   комментарии). Результат сверен: `touchscreen-inverted-x` и
   `touchscreen-swapped-x-y` удалены, координаты native portrait 1600×2176 —
   ровно то, что 0051 и делает.

Включение узлов (0056): `consys@18070000` и `wifi@180f0000` →
`status = "okay"`; больше ничего в них не менялось. `consys-reserve-memory`
осталась в форме `alloc-ranges` (2 МиБ, выравнивание 2 МиБ,
0x40000000–0xc0000000), т.е. фиксированного `reg` нет и
`reserved_memory_conflict_check()` LK эту запись не проверяет. В mblock-ах
этого устройства окно 0xbfc00000–0xbfe00000 (то, что выбрал сток) свободно,
сосед — `mblock-5-atf-log` 0xbfe00000–0xbfe40000, так что аллокатор ядра
повторит выбор стока или возьмёт другое свободное окно.

### 23.2 Конфиг и сборка

- `/home/l/t1100-merge-out/.config` = копия `out-normal/.config` (проверенный
  конфиг второго разработчика) + `configs/t1100-wifi.fragment` через
  `scripts/kconfig/merge_config.sh` + `olddefconfig`;
- **каждый** `make` — с `LOCALVERSION=-g400cb6f-touch-rot`
  (`make -s kernelrelease` → `6.12.114-g400cb6f-touch-rot`);
- собиралось полностью: `make -j12 Image dtbs modules` (rc=0, `error:` 0),
  поэтому `Module.symvers` полный (20 274 символа) и трюк `--kernel-mods`
  из 22.5 не понадобился;
- в конфиге появились `CONFIG_NL80211_TESTMODE=y`, `CONFIG_CFG80211_WEXT=y`,
  `CONFIG_WEXT_{CORE,PRIV,SPY}=y`, `CONFIG_IPW2200=m`: это уже «полный
  паритет» из 22.6, поэтому `CONFIG_WEXT_CORE=y` есть в `vmlinux`,
  `wireless_send_event` резолвится из ядра, а `stubs/wext_stub.o` в
  `wlan_drv_gen3.ko` **не** попал (ветка `ifeq ($(CONFIG_WEXT_CORE),)` в
  `wlan.Kbuild` не сработала).

### 23.3 Артефакты

| файл | размер, Б | sha256 |
|---|---|---|
| `build/merge/Image` | 40 083 968 | `a4a1fe09990118f1e74c1d9769ff271e4de6d85763a1b8c173b8a2b867f42e40` |
| `build/merge/Image.gz` | 14 602 227 | `05650764a27894422d9df9accf9e218724ec533f8e5566263263254ae03c75ee` |
| `build/merge/mt6771-fplus-t1100.dtb` | 53 667 | `0dd7e5ae498e5a0dd413d42c15bfeee5690cb55e7dfb774b6139e23c16025faa` |
| `build/wifi/common/wmt_drv.ko` | 1 111 976 | `8228dd5c28700eea37cf8c8bb4ad833ef30ce406b75c4b381879a9ef849bbead` |
| `build/wifi/wlan/wlan_drv_gen3.ko` | 2 895 080 | `be1df2ac0c263f5c30cd75c3b49e01f45540224cd6aa18ad890eb1fd1540da98` |
| `build/wifi/kernel/cfg80211.ko` | 614 888 | `76a90f08e8c0bb023bf0ff7c5ab9778edb888554016835649be22793880bd44b` |
| `build/wifi/kernel/mac80211.ko` | 812 160 | `050602fe7398c7b9a4a78e6ed550e02d2a497dd151919dbc47264755025e46f8` |
| `build/wifi/kernel/rfkill.ko` | 48 272 | `e6bbcb7b510314457aea0b946aed862ae490ee25a7a33b19ee3a37e8a1308ab1` |
| `build/wifi/kernel/libarc4.ko` | 5 192 | `a38b5be1648431f86a5ed406004837b3ced668f6f49a0b9d5de190af922e9ef3` |

`vermagic` у всех шести — `6.12.114-g400cb6f-touch-rot SMP preempt mod_unload
aarch64`, сверен не только с `kernel.release`, но и с `strings` **ядра внутри
готового boot-образа**. `wmt_drv.ko` побайтово совпал с M3 (`8228dd5c…`);
`cfg80211.ko`/`mac80211.ko` от M3 отличаются — теперь они собраны с
`CFG80211_WEXT=y` + `NL80211_TESTMODE=y` из полного `make modules`, а не
одноцелевой сборкой в чужом конфиге.

### 23.4 `build/boot_merge_wifi.img`

- **ref — `build/boot_merged12.img`, а не `build/xfer/cur_boot_2026-11-12.img`.**
  В `cur_boot…` лежит ядро `6.12.114-g95e3b41b86-dirty` (наша сборка от 11.11
  16:26), cmdline **без** `maxcpus=8` и `kernel_addr = 0x40080000` (не 2 МиБ) —
  это образ *до* merge12, он не описывает текущую конфигурацию. В
  `boot_merged12` — `kernel_addr = 0x40200000`, cmdline с `maxcpus=8`, а
  ramdisk (1 033 291 Б) в обоих образах один и тот же (`rsize` совпал),
  поэтому ramdisk берётся из ref;
- сборка: `gzip -9 -n` + `scripts/repack_boot.py --ref build/boot_merged12.img
  --kernel build/merge/Image.gz --dtb build/merge/mt6771-fplus-t1100.dtb --out
  build/boot_merge_wifi.img`;
- результат: 33 554 432 Б, sha256
  `a99be59b1676029d06a47b603fa058f5e640c5ce52b8b578fb638fe9ed7ff703`,
  md5 `a85f2d848ea9840feb93ff7ecf99705f` (рядом `.sha256` и `.md5`);
- обратная распаковка (`scripts/bootimg_extract.py`): kernel и DTB внутри
  побайтово совпали с исходными, cmdline — с `maxcpus=8`.

### 23.5 Проверки (build-хост, без устройства)

- `tools/lk/verify-dtb.sh` на DTB из дерева **и** на DTB, вынутом из готового
  образа: `RESULT: validator passed -> LK should accept this DTB`
  (18 mblock-ов, overlay применяется, `merged size 88 841 <= 524 288`);
- `dtc -I dtb -O dts`: у `consys@18070000` и `wifi@180f0000` `status = "okay"`,
  `consys-reserve-memory` — `alloc-ranges`, фиксированного `reg` нет;
- символьное замыкание: для каждого из шести `.ko` множество `nm -u`
  покрывается `Module.symvers` (20 274) + экспортами самих модулей →
  **неразрешённых 0**;
- `kernel.release` до/после сборки вендорских модулей не изменился
  (`6.12.114-g400cb6f-touch-rot`), rc=0, `undefined=0` у common и wlan.

### 23.6 Деплой (после прошивки; устройство у лида)

```sh
tools/host/wifi-deploy.sh --apply     # 6 .ko -> /lib/modules/6.12.114-g400cb6f-touch-rot/updates/wifi + depmod + unit
tools/host/wifi-deploy.sh --load wmt  # modprobe wmt_drv + dmesg
dmesg | grep -i wmt
```

Признак M4: `wmt: power on ok` и chip id `0x788` в dmesg, `/proc/wmt*` жив,
панель/тач не пострадали. Прошивки Wi-Fi (`WIFI_RAM_CODE_6759`, `WMT_SOC.cfg`)
в rootfs по-прежнему нет, `wlan0` в M4 не ожидается.

Откат: `build/boot_merged12.img` (sha256 `651ab53c…`, проверен на устройстве);
модули M3/M4 взаимозаменяемы только вместе с ядром своей сборки — vermagic
одинаков, но `cfg80211.ko` M3 и M4 собраны с разным конфигом.

## 24. M5: `wlan_drv_gen3` не вставлялся — дублирующий экспорт из заглушки (13.11)

Первая загрузка объединённого ядра (аудио + наш Wi-Fi DT, `consys@18070000` и
`wifi@180f0000` = `okay`): `wmt_drv.ko` грузится, а следом

```
wlan_drv_gen3: exports duplicate symbol connectivity_export_show_stack (owned by wmt_drv)
modprobe: ERROR: could not insert 'wlan_drv_gen3': Exec format error
```

**Причина.** `show_stack()` не экспортируется модулям, поэтому наша заглушка
подменяет его своей обёрткой `connectivity_export_show_stack()` (её зовёт
watchdog-путь через `KERNEL_show_stack` в
`scripts/remote/wifi-compat/connectivity_build_in_adapter.h`). Обёртка лежала
**в двух** stub-файлах — `wifi-stubs/wmt_stubs.c` и `wifi-stubs/wlan_stubs.c`, —
и каждый модуль её определял и экспортировал:

```
wmt_drv.ko        : __ksymtab_connectivity_export_show_stack
wlan_drv_gen3.ko  : __ksymtab_connectivity_export_show_stack   <- дубль
```

Ядро при `init_module()` отвергает второй модуль, который экспортирует символ
уже загруженного: наружу это выглядит как `Exec format error` (а не как
«duplicate symbol» в `dmesg`, из-за чего ошибка сначала читается как «битый
ELF/чужой vermagic»). В вендорском дереве обёртка определена один раз — в
built-in `drivers/misc/mediatek/connectivity/wmt_plat`, то есть «владелец» —
WMT, а `wlan` только использует её. Так и сделано.

**Правка.** В `scripts/remote/wifi-stubs/wlan_stubs.c` удалены определение и
`EXPORT_SYMBOL(connectivity_export_show_stack)` (оставлен комментарий,
почему нельзя); объявление берётся из `connectivity_build_in_adapter.h`.
Экспорт остался ровно один — в `wmt_stubs.c`, т.е. в `wmt_drv.ko`, который
грузится первым. `wlan` теперь имеет символ **undefined** и получает его от
`wmt`: modpost резолвит его через `Module.symvers` common (`KBUILD_EXTRA_SYMBOLS`
уже передавался в `scripts/remote/build-wifi-remote.sh`), поэтому в `.modinfo`
появилось `depends=wmt_drv` — `modprobe wlan_drv_gen3` сам поднимет `wmt_drv`.

**Сборка.** Оба модуля собраны одним прогоном (иначе `--prepare` сносит
`work/` соседнего модуля и второй `.ko` не попадает в `build/wifi/`):

```sh
KERNEL_OUT=/home/l/t1100-merge2-out LOCALVERSION=-g400cb6f-touch-rot \
  scripts/build-wifi-remote.sh common wlan
# common rc=0 errors=0 undefined=0; wlan rc=0 errors=0 undefined=0
# release after build: 6.12.114-g400cb6f-touch-rot (не изменился)
```

| модуль | размер, Б | sha256 |
|---|---|---|
| `wmt_drv.ko` | 1 111 976 | `8228dd5c28700eea37cf8c8bb4ad833ef30ce406b75c4b381879a9ef849bbead` (не изменился) |
| `wlan_drv_gen3.ko` | 2 894 616 | `796b4a3283ea5969fd257a15ac57ddd74bc33058ddb105d91c42110440ba53d2` |

**Проверки (офлайн).**

- `nm --defined-only | grep __ksymtab_`: 80 экспортов у `wmt_drv`, 2 у
  `wlan_drv_gen3` (`register_set_p2p_mode_handler`, `wlanGetFwIDVersion`),
  пересечение множеств — **пусто**; `connectivity_export_show_stack`
  экспортируется только `wmt_drv`;
- `nm -u wlan_drv_gen3.ko`: символ в undefined, вместе с ещё 11 экспортами
  `wmt_drv` (`mtk_wcn_wmt_*`, `gConEmiPhyBase`, `wmt_plat_read_cpupcr`, …);
  замыкание по `Module.symvers` ядра + экспортам обоих модулей —
  **неразрешённых 0**;
- `vermagic` у всех шести `.ko` — `6.12.114-g400cb6f-touch-rot SMP preempt
  mod_unload aarch64`;
- `depmod`/`modprobe --show-depends` в изолированном root:
  `modules.dep` → `wlan_drv_gen3.ko: wmt_drv.ko cfg80211.ko rfkill.ko`,
  порядок загрузки `rfkill → cfg80211 → wmt_drv → wlan_drv_gen3`.

**Деплой** (устройство уже с объединённым ядром; `wmt_drv` до этого грузили
вручную, поэтому сначала выгрузить его — иначе `modprobe` подхватит старый
экземпляр, а `depmod` обновит только файлы):

```sh
rmmod wmt_drv 2>/dev/null || true      # старый экземпляр держал бы дубль экспорта
tools/host/wifi-deploy.sh --apply --load all
dmesg | grep -iE "wmt|wlan|connectivity_export"
```

## 25. M5: `wiphy_register` WARN на `vendor_commands[].policy` (13.11)

После снятия дубля экспорта `wlan_drv_gen3.ko` грузится и доходит до
`initWlan`, но `wiphy_register()` падает:

```
WARNING: CPU: 2 PID: 926 at net/wireless/core.c:999 wiphy_register+0x524/0x860 [cfg80211]
[wlan]createWirelessDevice:(INIT ERROR) wiphy_register error
initcall initWlan ... returned -1
```

`net/wireless/core.c:999` — обязательная проверка 6.12:

```c
for (i = 0; i < rdev->wiphy.n_vendor_commands; i++) {
	if (WARN_ON(!rdev->wiphy.vendor_commands[i].policy))
		return -EINVAL;
	if (WARN_ON(!rdev->wiphy.vendor_commands[i].doit &&
		    !rdev->wiphy.vendor_commands[i].dumpit))
		return -EINVAL;
}
```

**Причина.** Вендорский `mtk_wlan_vendor_ops[]` (`os/linux/gl_init.c:310`)
писался под 4.14, где `policy == NULL` допускался: у записей есть
`.vendor_id/.subcmd/.flags/.doit`, но `.policy` нет. В 6.12 NULL‑policy —
`WARN_ON` + `-EINVAL`, т.е. не грузится вообще ни один wiphy (AIS‑интерфейс).

**Правка.** `patches/wifi/0002-wlan-port-6.12-vendor-commands.patch`
(накладывается после `0001-wlan-port-6.12.patch`): регистрация vendor‑команд
выключена в обоих wiphy — AIS (`os/linux/gl_init.c`, ~1655) и P2P
(`os/linux/gl_p2p.c`, ~880):

```c
-	prWiphy->vendor_commands = mtk_wlan_vendor_ops;
-	prWiphy->n_vendor_commands = sizeof(mtk_wlan_vendor_ops) / sizeof(struct wiphy_vendor_command);
+	prWiphy->vendor_commands = NULL;
+	prWiphy->n_vendor_commands = 0;
```

Почему не `.policy = VENDOR_CMD_RAW_DATA`: эти команды — MTK‑приватные
`iwpriv`‑ioctl'ы (Google OUI subcmd'ы вендорского HAL); nl80211 и
`wpa_supplicant` их не используют, а `VENDOR_CMD_RAW_DATA` открывал бы
пользовательскому пространству произвольные атрибуты в драйвер. Если
когда‑нибудь понадобится `iwpriv` — проще вернуть команды с явными
`nla_policy` на каждую.

**Сборка** (только `wlan`, ядро не трогалось; одним прогоном, чтобы не снести
`work/common`, см. §24):

```sh
KERNEL_OUT=/home/l/t1100-merge2-out LOCALVERSION=-g400cb6f-touch-rot \
  scripts/build-wifi-remote.sh common wlan
# -- apply 0002-wlan-port-6.12-vendor-commands.patch
# common rc=0 undefined=0; wlan rc=0 undefined=0
```

| модуль | размер, Б | sha256 |
|---|---|---|
| `wlan_drv_gen3.ko` | 2 893 304 | `20e64fc06f9260fac0aec6b60390459d8c2e2961d73a65e91cda288e89dc0c93` |
| `wmt_drv.ko` | 1 111 976 | `8228dd5c28700eea37cf8c8bb4ad833ef30ce406b75c4b381879a9ef849bbead` (не менялся) |

**Офлайн‑проверки.**

- `static const` массивы `mtk_wlan_vendor_ops` / `mtk_p2p_vendor_ops` после
  правки не используются, и компилятор их выбросил: в `nm` их нет вовсе
  (остался только `mtk_wlan_vendor_events`), `readelf -rW` — **0** релокаций
  на них. То есть в бинарнике больше нет ни массива, ни присваивания
  `vendor_commands`; присваивания NULL/0 в `kzalloc`‑нутую структуру компилятор
  тоже схлопнул;
- экспорты: 80 у `wmt_drv`, 2 у `wlan_drv_gen3`, пересечений нет;
- `nm -u`: неразрешённых 0 (замыкание по `Module.symvers` ядра + экспортам
  модулей), `depends=cfg80211,wmt_drv`, vermagic `6.12.114-g400cb6f-touch-rot`.

**Что ещё может выстрелить в `wiphy_register` (порядок проверок в 6.12).**
До строки 999 уже пройдены (и на устройстве прошли): wowlan
`WIPHY_WOWLAN_GTK_REKEY_FAILURE`/`!flags && !n_patterns && !tcp` (у MTK есть
`flags = DISCONNECT|ANY`), TDLS_CHANNEL_SWITCH, NAN, WDS, pmsr, regulatory,
coalesce, `ap_sme_capa`, `addresses`, и главное — `have_band` (bands[2/5GHz]
заполнены). После цикла vendor‑команд остаются только
`wowlan->pattern_min_len/max_len` (при `n_patterns == 0` не проверяется),
`max_num_akm_suites` (0 → дефолт) и `device_add(&wiphy->dev)` — то есть
`wiphy_register` должен пройти.

Быстрая проверка на устройстве:

```sh
dmesg | grep -iE "wiphy|wlan0|initWlan|WARNING" | tail -30
iw phy                      # должен появиться phy0, без WARN в dmesg
ip -br link | grep wlan0    # интерфейс создаётся при ifconfig up/iw dev
```

## 26. M6: nl80211 не создаёт интерфейс; `wlanProbe` запускается, но CONSYS не отвечает (12.11)

Рубеж M6 = «есть `wlan0` и скан». Итог: **не взят**, но путь выяснен до
конкретного места. Ниже — фактический вывод, чтобы следующая сессия не
переоткрывала.

### 26.1 Инструмент nl80211: собран статический `iw` 6.9

```sh
scripts/build-iw-aarch64.sh          # libnl 3.11.0 + iw 6.9, --host=aarch64-linux-gnu
# build/tools-aarch64/iw  1 267 888 Б
sha256 c4d68b70f8c529d94e637a59a20e02cc24d51dc3443f7e5fb274aec441b81374
file: ELF 64-bit LSB executable, ARM aarch64, statically linked, stripped
```

На планшете: `/usr/local/bin/iw`, `iw version 6.9` работает. Логика сборки:
libnl `--disable-shared --enable-static` в `/home/l/t1100-tools/iw-src/libnl-aarch64`,
затем `make CC=aarch64-linux-gnu-gcc LDFLAGS=-static PKG_CONFIG_LIBDIR=<prefix>/lib/pkgconfig`
(`NEEDED` в `readelf -d` — 0).

### 26.2 `wlan0` через nl80211 НЕ создаётся — и не может

```
# iw phy phy0 interface add wlan0 type managed
command failed: Operation not supported (-95)
```

Причина в самом драйвере, а не в инструменте: в `mtk_wlan_ops`
(`os/linux/gl_init.c:261`) **нет** `.add_virtual_intf` (есть
`change_virtual_intf`, `scan`, `connect`, …), а у P2P он закомментирован
(`gl_p2p.c:78`). `cfg80211` без `rdev_add_virtual_intf` возвращает
`-EOPNOTSUPP`. То есть в gen3 интерфейс создаёт НЕ userspace через nl80211, а
`wlanProbe()` при «WMT func on (WIFI)»; вывод в `docs/STATUS.md` 12.11 (15)
про nl80211-путь был неверен.

### 26.3 Как вендор поднимает WLAN (по исходникам)

```
mtk_wcn_wmt_func_on(WIFI)                       [wmt_exp.c:126]
  → отдельный op WMT_OPID_PWR_ON → opfunc_pwr_on [wmt_core.c]
      → WMT_CTRL_HW_PWR_ON → wmt_plat_pwr_ctrl(FUNC_ON) → mtk_wcn_consys_hw_pwr_on()
      → wmt_core_stp_init()                     ← упирается здесь у нас
  → op WMT_OPID_FUNC_ON → opfunc_func_on(WIFI)
      → для WIFI: ставит в очередь WMT_OPID_WLAN_PROBE и выходит
  → wmtd worker: opfunc_wlan_probe → gpWmtFuncOps[WIFI]->func_on = wmt_func_wifi_on()
      → (chip type SOC) mtk_wcn_wlan_probe() = HifAhbProbe()
          → mtk_wcn_consys_hw_wifi_paldo_ctrl(1)
          → wlanProbe()  →  wlanNetCreate() (переиспользует gprWdev) + register_netdev
```

`wmt_core_stp_init()` первым делом требует `wmtInfoBit & WMT_OP_HIF_BIT`
(его ставит `opfunc_hif_conf`, т.е. `WMT_IOCTL_SET_STP_MODE` от `wmt_loader`)
и открывает STP-транспорт (UART/SDIO/BTIF). В нашем порте все транспорты —
заглушки (`stubs/wmt_stubs.c`: `mtk_wcn_stp_{uart,sdio}_drv_init → -ENOSYS`),
поэтому `opfunc_pwr_on` всегда падает с `-3` и до колбэка дело не доходит.
Это ровно тот же лог, что в стоке при `wmt_core_stp_init: no hif info!`.

### 26.4 Обходной путь (патчи 0003/0004) и где он упирается

`patches/wifi/0003-wlan-t1100-probe-param.patch` — модульный параметр
`t1100_probe=1`: после `glRegisterBus()` вызывается `t1100_wlan_probe()`,
которая (а) питает чип `wmt_plat_pwr_ctrl(FUNC_ON)` (тот же шаг, что первый
в `opfunc_pwr_on`, без STP), (б) делает `paldo_ctrl(1)` + `pfWlanProbe()`
без `pfWlanRemove()` при ошибке. `patches/wifi/0004-…` экспортирует
`wmt_plat_pwr_ctrl` из `wmt_drv`.

Порядок на железе (`modprobe wmt_drv` → `wmtctl detect/setid 0x6771/init` →
`modprobe wlan_drv_gen3 t1100_probe=1`):

```
[wlan]createWirelessDevice:(INIT INFO) Create wireless device success
[wlan]t1100_wlan_probe: chip power on
[WMT-CONSYS-HW][I]mtk_wcn_consys_hw_pwr_on:CONSYS-HW-PWR-ON, start
[WMT-CONSYS-HW][E]polling_consys_chipid(611):Maybe has a consys power on issue,(0x00000000)
[WMT-CONSYS-HW][I]update_consys_rom_desel:Update consys rom desel value(0x0)
[WMT-CONSYS-HW][I]mtk_wcn_consys_hw_pwr_on:CONSYS-HW-PWR-ON, finish(0)
[wlan]t1100_wlan_probe: wmt_plat_pwr_ctrl(FUNC_ON) = 0
[wlan]t1100_wlan_probe: paldo on + wlanProbe
[wlan]wlanNetCreate:(INIT INFO) net_device prDev(0x...) allocated
[wlan]sdio_open:(HAL ERROR) Enable function failed, error -62      ← -ETIME: IORx не встал
[wlan]glLoadNvram:(INIT WARN) Nvram not available
[wlan]nicpmSetDriverOwn:(NIC ERROR) LP fail, Timeout(516ms) Bus Error[0] …
[wlan]wlanPollingCpupcr:(INIT ERROR) i:0..3, cpupcr:00000000
[wlan]wlanAdapterStart:(INIT ERROR) nicpmSetDriverOwn() failed!
[wlan]wlanProbe:(INIT ERROR) wlanProbe failed
[wlan]t1100_probe: t1100_wlan_probe() = -5
initcall initWlan ... returned 0                              ← модуль загружен, phy0/phy1 есть
```

Читается так: netdev создан, но регистр-обмена с HIF нет — все чтения из окна
CONNSYS (`0x180f0000` WFDMA и `0x18070000`) возвращают 0 (`cpupcr:00000000`,
`IORx` не выставляется). «PWR-ON, finish(0)» и ненулевые ACK-регистры SPM —
это AP-сторона (`0x1000632c`, `0x10006180`), они не доказывают, что домен
CONN реально поднялся.

**Чего в порте заведомо нет** (по исходникам, не по догадкам):

- `consys_hw_wifi_vcn33_ctrl()` (paldo WIFI) целиком в `#if 0`;
- `CONSYS_PWR_ON_OFF_API_AVAILABLE = 0` для mt6771 → `clk_scp_conn_main`
  («conn») никогда не включается, питание домена идёт только ручными записями
  в SPM (0x1000632c), а в DT узла consys клока нет вовсе;
- ROM-patch CONSYS (`soc3_0_ram_*.bin`) в стоке грузит `wmt_loader` по STP —
  у нас этого пути нет.

### 26.5 Опасность: неудачный probe через `HifAhbProbe()` вешает ядро

Первая версия патча вызывала `HifAhbProbe()` прямо в `glRegisterBus()`.
`HifAhbProbe()` при ошибке probe делает `pfWlanRemove()` = `wlanRemove()` на
полуинициализированном glue → **kernel hang**: ping/TCP отвечают, но sshd не
отдаёт баннер (`dmesg` тоже виснет на printk-lock), лечится только
долгим нажатием Power. Поэтому в итоговой версии rollback убран: ошибка probe
только пишется в лог, модуль остаётся загруженным, система жива.

### 26.6 Что проверено и что нет

Проверено на железе: `iw` статический работает; nl80211 add_iface → `-EOPNOTSUPP`
(объяснено исходником); CONSYS power-on по SPM возвращает 0; probe доходит до
`nicpmSetDriverOwn` и падает на пустом HIF-окне; `devmem`/`mempeek` через
`pread(/dev/mem)` на 0x180f0000/0x1000632c дают `EFAULT` (нужен `mmap`).
Не проверено: реальные значения регистров окна CONN (нет инструмента),
поведение `wmt func on` при живом STP, скан эфира.

### 26.7 Следующий шаг (по порядку)

1. Дать регистровую видимость: статический `regpeek` (mmap `/dev/mem`) и снять
   `0x18070008` (chip id), `0x180f0000…+0x40`, `0x1000632c/0x10006180` до и
   после `wmt_plat_pwr_ctrl(FUNC_ON)` — один прогон, без пересборки ядра.
2. Сверить SPM-последовательность `mt6771.c:consys_hw_power_ctrl()` с
   вендорским mt6771 (вопрос к `bringup`): биты `CONN_TOP1_PWR_ON[_S]`,
   `conn_clk_dis`, `conn_top1_iso_en`, и нужен ли для WFDMA отдельный клок
   (`CLK_INFRA_CQ_DMA` включается только в `ahb_pdma.c` при DMA).
3. Только после живого окна CONN имеет смысл `ip link set wlan0 up` (загрузка
   `WIFI_RAM_CODE_6759`) и `iw dev wlan0 scan`.

## 27. M7: окно CONNSYS ожило — причина найдена, патч 0005; probe при живом домене вешает ядро (12.11)

Рубеж M7 = «окно CONN отвечает». Диагноз **доказан** (сырые дампы —
`refs/consys-regs-2026-11-12.md`), но `wlan0` не появился: при реально
включённом домене вендорский probe вешает ядро.

### 27.1 Инструмент: `mempeek` с `mmap` и записью

`tools/mempeek/mempeek.c` переписан: `pread()` на MMIO даёт `EFAULT`, поэтому
основной путь — `mmap(/dev/mem)`, добавлены `--write` и `--poke` (RMW).
Сборка статически на build-хосте (`aarch64-linux-gnu-gcc -static`), на планшете
`/usr/local/bin/mempeek`.

### 27.2 Главная причина: power-on ничего не делал

В вендорском `common_main/platform/include/mt6771.h:32`:

```c
#define CONSYS_PWR_ON_OFF_API_AVAILABLE	1
```

(в §26.4 было записано «0 для mt6771» — **это неверно**). Значит
`consys_hw_power_ctrl()` — это ровно одна строка:

```c
iRet = clk_prepare_enable(clk_scp_conn_main);      /* + clk_disable_unprepare() */
```

`clk_scp_conn_main` берётся из вендорского clock provider'а
`mediatek,scpsys` (`clocks = <&scpsys 2>`); в mainline его нет, наш патч 0002
сделал lookup необязательным → указатель NULL, а `clk_enable(NULL)` в 6.12 —
**успешный no-op**. Отсюда `CONSYS-HW-PWR-ON, finish(0)` при полностью мёртвом
домене: SPM-последовательность (`0x1000632c`) не выполнялась вообще.

Дамп до вмешательства: `0x1000632c = 0x112` (iso=1, clk_dis=1, sram_pd=1,
pwr_on=0), `0x10006180 = 0x008fff4c` (ack=0) — то есть ни одного шага power-on
не было.

### 27.3 Вторая причина: даже «ручная» SPM-ветка вендора не сняла бы protect

В той же функции под `#else` AXI-protect снимается так:

```c
CONSYS_REG_WRITE(conn_reg.topckgen_base + CONSYS_TOPAXI_PROT_EN_OFFSET,
                 CONSYS_REG_READ(...) & ~CONSYS_PROT_MASK);
```

при `CONSYS_TOPAXI_PROT_EN_OFFSET = 0x2a4`. Измерено: `0x100012a0` — это
`PROT_EN` (обычный RW), а `0x100012a4` — его **write-1-to-clear** зеркало.
Запись «read & ~mask» не снимает ничего (биты 13/14 остаются), окно читается
нулями, а первая же запись в него **встаёт намертво** (проверено: `--write
0x18070600` не вернулся за 60 с).

Правильно — записать маску в `0x100012a4`; после этого:

```
0x100012a0 = 0x00600000          (protect снят)
0x18070008 = 0x00000788          chip id CONNSYS — как ждёт polling_consys_chipid()
0x18070600 = 0x001702a4          ROM deselect: запись проходит и читается обратно
0x180f0004 = 0x00000043, 0x180f000c = 0xa07f0000    WFDMA отвечает
0x1000632c = 0x0000010d, 0x10006180 = 0x408fff4e    (bit30 = conn_top2 ack)
```

Третья мелочь: `conn_top2_pwr_on_ack` (bit30) вендор читает из
`0x1000632c`, а он приходит в `0x10006180`; плюс оба опроса — без таймаута
(на полуописанном SoC это lock-up).

### 27.4 Патч 0005 и прогон

`patches/wifi/0005-common-consys-spm-power-on.patch` (`common`):

- `consys_hw_power_ctrl()`: если клока `conn` нет — идём в новую
  `consys_hw_power_ctrl_spm()` (вендорская SPM-последовательность с
  таймаутами и правильным снятием protect);
- `mt6771.h`: `CONSYS_TOPAXI_PROT_EN_OFFSET = 0x2a0`, новый
  `CONSYS_TOPAXI_PROT_CLR_OFFSET = 0x2a4`.

Собрано: `wmt_drv.ko` sha256 `de80dcce…b3817` (1 113 816 Б),
`wlan_drv_gen3.ko` `2a6d8c5b…fed67` (2 896 256 Б), vermagic
`6.12.114-g400cb6f-touch-rot`. На планшете модуль грузится, в логе появилось
`[CCF]no "conn" clock in DT, power-on uses the SPM sequence`.

**Инцидент.** `modprobe wlan_drv_gen3 t1100_probe=1` при живом домене CONN
повесил ядро наглухо (нет ping, sshd, USB-gadget; авторебута нет — это не
panic). Лечится Power 10 с.`/root/wifi-test.log` с последними строками остался
на устройстве.

### 27.5 Что дальше (порядок)

1. После Power 10 с снять `/root/wifi-test.log` — там видно, на каком шаге
   `wlanProbe` умер (последняя строка перед зависанием).
2. Не запускать probe «вслепую». Мелиорация: параметр `t1100_probe_stage=N`
   (или пошаговый `wmtctl`-ioctl), чтобы останавливаться перед подозрительным
   шагом; ожидаемые подозреваемые по коду: первый доступ к WFDMA
   (`0x180f0000`, клок `wifi-dma` — в DTS это mt8183-гейт `CLK_INFRA_CQ_DMA`,
   соответствие MT6771 не проверено), AFE `0x180b6000`, EMI-MPU
   `0x10212xxx`.
3. Проверить `regulator_summary` (vcn33/vcn18) — при мёртвом окне снять не
   успели.
4. До живого HIF остаётся тот же вопрос, что и в §26: STP-транспорта нет,
   поэтому `wlanProbe` зовём сами; но перед ним клок/гейт WFDMA должен быть
   включён явно.

## 28. M7 взят: окно CONNSYS отвечает, драйвер доходит до загрузки прошивки (12.11, продолжение §27)

Лог прошлого прогона (§27.6) снят: `/root/wifi-test.log`. Он оказался **не**
логом смерти — наоборот, в нём видно, что после патча 0005 стек доходит до
конца инициализации:

```
[CCF]no "conn" clock in DT, power-on uses the SPM sequence
consys_hw_power_ctrl_spm: CONN SPM power on: 0x10d/0x408fff4e/0x18600098
polling_consys_chipid: retry(8) consys chipId(0x00000788)     <- окно живое
update_consys_rom_desel: Update consys rom desel value(0x1702a4)
nicpmSetDriverOwn: DRIVER OWN, status=1 count=25               <- HIF-хендшейк ОК
nicInitializeAdapter: Chip ID[6771] Version[E1]
kalFirmwareOpen: Open FW image /lib/firmware/WIFI_RAM_CODE_6759 success
wlanAdapterStart: FW download end
wlanAdapterStart: Waiting for Ready bit timeout, Device to Host MailBox 0x38
glResetTrigger: Trigger chip reset ... wlan_lib.c line 633
wlanPollingCpupcr: cpupcr:00015730                             <- MCU исполняет код
initcall initWlan ... returned 0 after 1824232 usecs
```

То есть **M7 (окно CONN отвечает) закрыт**: chip id читается, DRIVER OWN
проходит, прошивка скачивается, MCU считает (cpupcr меняется). Не хватает
только `WLAN_READY` от прошивки.

### 28.1 Почему умерло ядро: `glResetTrigger` на неинициализированном work

`wlan_lib.c:633` на таймауте ready-бита делает
`GL_RESET_TRIGGER(RST_FLAG_DO_CORE_DUMP | RST_FLAG_PREVENT_POWER_OFF)` →
`glResetTrigger()` → `schedule_work(&wifi_rst.rst_trigger_work)` →
`mtk_wifi_trigger_reset()` → `mtk_wcn_wmt_assert_timeout(...)` (core dump через
WMT, которого в порте нет).

Но `INIT_WORK(&wifi_rst.rst_trigger_work, mtk_wifi_trigger_reset)` делается в
`glResetInit()`, а `initWlan()` вызывал его **после** probe. У вендора probe на
init не бывает, поэтому порядок не мешал; у нас же `schedule_work()` получал
**неинициализированный** work (нулевой `func`) → вызов NULL в kworker. Это и
есть «смерть после `initWlan returned 0`».

Патч **`patches/wifi/0006-wlan-probe-stage-and-no-reset.patch`**:

- `glResetInit()` перенесён **до** probe (правильный порядок, вендорский путь не
  меняется);
- `t1100_no_reset=1` — не планировать whole-chip reset (нет ни STP, ни
  coredump-бэкенда);
- `t1100_probe_stage` — 1 = только питание, 2 = питание + `wlanProbe` (по
  умолчанию), чтобы останавливать прогон перед отлаживаемым шагом.

### 28.2 Прогон stage=1 (безопасный) — питание и клоки закрыты

`modprobe wlan_drv_gen3 t1100_probe=1 t1100_probe_stage=1 t1100_no_reset=1`:

```
t1100_wlan_probe: wmt_plat_pwr_ctrl(FUNC_ON) = 0
t1100_wlan_probe: stage 1, stop after power on
t1100_probe: t1100_wlan_probe() = 0            <- без wlanProbe, плата жива
```

Регистры в этом состоянии (`refs/consys-regs-2026-11-12.md` §7):

```
0x1000632c = 0x0000010d   0x10006180 = 0x408fff4e   0x100012a0 = 0x18600098
0x18070008 = 0x00000788   0x18070038 = 0x00000000 (WCIR, ready-бита нет)
0x18070078 = 0x000055aa   0x18070160 = 0x00001170 (cpupcr)
0x180f0000 = 0x00000000   0x180f000c = 0xa07f0000
```

`regulator_summary` (вопрос питания из §26 закрыт):

```
vcn18   1 use  -> 18070000.consys-vcn18     1800mV
vcn28   1 use  -> 18070000.consys-vcn28     2800mV
vcn33   1 use  -> 18070000.consys-vcn33_bt  3500mV
                 18070000.consys-vcn33_wifi  0mV   <- НЕ включён
```

То есть `vcn18`/`vcn28`/`vcn33_bt` включает сам consys-драйвер, а
`vcn33_wifi` (rail TX PA) остаётся выключенным: `consys_hw_wifi_vcn33_ctrl()`
в вендорском коде целиком под `#if 0`, поэтому `wifi_paldo_ctrl(1)` — no-op.
Для приёма/скана rail не нужен, для передачи — понадобится (вопрос следующего
рубежа, не блокер M7).

`clk_summary` (вопрос клока WFDMA):

```
infra_cqdma        enable=0  prepare=0  156000000 Hz  deviceless
infra_cqdma_fpc    enable=0
```

Гейт `CLK_INFRA_CQ_DMA` в mainline-драйвере mt8183 существует, но **никем не
взят** (`deviceless`, enable=0) — `devm_clk_get(dev, "wifi-dma")` в
`HifDmaInit()` до этого места не доходит (в логе нет `[CCF]HIF DMA clock = ...`),
и при этом WFDMA (`0x180f000c = 0xa07f0000`) отвечает. Вывод: для доступа к
окну WFDMA этот гейт не нужен, `clocks = <&infracfg CLK_INFRA_CQ_DMA>` в DTS
оставлен как есть (он про CQ-DMA канал, а не про сам блок), правка DTS не
потребовалась.

### 28.3 Новый блокер: oops в `wlanNetCreate` (stage=2)

Прогон `t1100_probe_stage=2 t1100_no_reset=1` (собран из 0005+0006):
`wlan rc=139` (SIGSEGV), ядро **не зависло**, а упало в oops и затем
перезагрузилось (журнал сохранился):

```
t1100_wlan_probe: paldo on + wlanProbe
wlanNetCreate: net_device prDev(0x...) allocated
Unable to handle kernel write to read-only memory at virtual address ffffff80d83cd008
pc : netif_tx_stop_all_queues+0x2c/0x80
lr : wlanProbe+0x138/0xeb0 [wlan_drv_gen3]
```

Это `gl_init.c:1791` (`netif_tx_stop_all_queues(prGlueInfo->prDevHandler)`) сразу
после `alloc_netdev_mq(..., ether_setup, CFG_MAX_TXQ_NUM)`: запись уходит в
read-only страницу, т.е. `dev->num_tx_queues`/`dev->_tx` — мусор. В прогоне на
сборке 0005 этот же код проходил (лог §28 доходил до FW download), поэтому это
похоже на latent-порчу памяти, чувствительную к раскладке, а не на логику.
Следующий шаг — `slub_debug=U,F` (или печать `dev`, `num_tx_queues`, `_tx` в
`wlanNetCreate`) и сверка `sizeof(GLUE_INFO_T)` с размером wiphy priv в
`createWirelessDevice()`.

### 28.4 Состояние и артефакты

- модули на планшете: `wmt_drv.ko` `de80dcce…b3817`, `wlan_drv_gen3.ko`
  `43817726…65992` (vermagic `6.12.114-g400cb6f-touch-rot`);
- ядро и boot **не менялись** (DTS-правок не потребовалось);
- безопасный прогон: `t1100_probe_stage=1` (питание без probe) — плата жива;
- шаги прогона пишутся в `/root/probe-stage.log` (`sync` после каждой строки),
  регистры — в `/root/probe-regs.txt`, oops'ы остаются в журнале
  (`journalctl -k -b -1`).

## 29. Oops в `wlanNetCreate` — причина: модуль собран против out-дерева без `CONFIG_WIRELESS_EXT` (12.11)

Рубеж M8 (регистрация `wlan0`) пока **не взят**, но причина падений найдена и
устранена; прогон теперь проходит без oops и без ребута.

### 29.1 Что происходило

`modprobe wlan_drv_gen3 t1100_probe=1 t1100_probe_stage=2` валил ядро:

```
wlanNetCreate: net_device prDev(0x…) allocated
Unable to handle kernel write to read-only memory at virtual address ffffff80d83cd008
pc : netif_tx_stop_all_queues+0x2c/0x80
lr : wlanProbe+0x138/0xeb0
```

### 29.2 Диагностика: печать полей netdev в `wlanNetCreate`

Добавленные `pr_info` (потом сняты) показали:

```
sizeof_nd=2496 sizeof_ndq=320 num_txq_off=1080 _tx_off=24 netdev_ops_off=8
after-alloc dev=… num_txq=0 real_txq=4 _tx=ffffff8012e6b000 priv_off=2496
stage3 name=wlan%d type=1 mtu=1500 num_txq=0 real=4 _tx=ffffff8012e6b000
```

`type=1`/`mtu=1500`/`real_num_tx_queues=4` верны, а **`num_tx_queues` читается
как 0**, хотя ядро в `net/core/dev.c:11393` сразу после `setup(dev)` делает

```c
	dev->num_tx_queues = txqs;        /* txqs = CFG_MAX_TXQ_NUM = 4 */
	dev->real_num_tx_queues = txqs;
```

Значит модуль читает поле не там, где его пишет ядро → `struct net_device` в
модуле и в ядре **разной длины**. Дальше ядро в своём
`netif_tx_stop_all_queues()` (`net/core/dev.c:10518`) крутит цикл по своему
`num_tx_queues` (мусор), берёт `netdev_get_tx_queue(dev, i)` = `_tx + i*320` и
пишет в rodata — ровно то, что в oops.

### 29.3 Причина

Сравнение конфигов:

```
out-normal (против него собирались модули):  CONFIG_WIRELESS_EXT — отсутствует
merge2-out (это ядро и запущено на плате):   CONFIG_WIRELESS_EXT=y
```

`CONFIG_WIRELESS_EXT` добавляет в `struct net_device` два указателя
(`wireless_handlers`, `wireless_data`), т.е. сдвигает **все** последующие поля
на 16 байт. Модули собирались против `out-normal`, ядро на плате — из
`merge2-out` (дерево `/home/l/t1100-merge2-src`, его board-DTS и содержит
`consys`), поэтому раскладка не совпадала: часть полей писалась/читалась по
чужим смещениям. Это же объясняет, почему oops «то есть, то нет»: мусор в
`num_tx_queues` зависел от содержимого кучи.

Всего конфиги расходятся на 23 строки, и кроме `CONFIG_WIRELESS_EXT` там
`CFG80211_WEXT`/`WEXT_*`/`NL80211_TESTMODE`/`LIB80211`/`IPW2200` — т.е.
`out-normal` вообще не пригоден для этого порта.

### 29.4 Исправление

- модули (вендорские **и** ядерные `cfg80211`/`mac80211`/`rfkill`/`libarc4`)
  пересобраны против **`/home/l/t1100-merge2-out`**:
  `KERNEL_OUT=/home/l/t1100-merge2-out LOCALVERSION=-g400cb6f-touch-rot scripts/build-wifi-remote.sh`;
- в `scripts/remote/build-wifi-remote.sh` добавлен предохранитель: сборка
  отказывается работать, если в `$KB/.config` нет `CONFIG_WIRELESS_EXT=y`.

Артефакты: `wmt_drv.ko` `de80dcce…b3817`, `wlan_drv_gen3.ko`
`4de6e1d95a857737bf219020355cd937ffd697fdc20941f50dd5773cd992ed69`
(2 897 592 Б); `cfg80211.ko` `76a90f08…`, `mac80211.ko` `050602fe…`,
`rfkill.ko` `e6bbcb7b…`, `libarc4.ko` `a38b5be1…`.

### 29.5 Прогон после исправления — чисто, без oops

```
t1100_wlan_probe: wmt_plat_pwr_ctrl(FUNC_ON) = 0
polling_consys_chipid: retry(8) consys chipId(0x00000788)
nicpmSetDriverOwn: DRIVER OWN, status=1 count=25
nicInitializeAdapter: Chip ID[6771] Version[E1]
kalFirmwareOpen: WIFI_RAM_CODE_6759 success -> FW download end
Waiting for Ready bit timeout, Device to Host MailBox 0x38   <- единственный блокер
glResetTrigger: T1100: whole-chip reset suppressed (t1100_no_reset=1)
wlanProbe failed; initcall initWlan returned 0
```

Плата жива, `wlan0` **нет** (`ip -br link` — только `lo`/`usb0`), потому что
`wlanProbe` возвращает ошибку до `register_netdev`. Регистры: `WCIR
0x18070038 = 0`, mailbox `0x18070078 = 0x55aa`, `cpupcr 0x18070160 = 0x15730`
(меняется — MCU работает), `0x180f000c = 0xa07f0000` (WFDMA отвечает).

### 29.6 Следующий шаг (M8)

Прошивка не выставляет `WLAN_READY` в `MCR_WCIR` (0x18070038). Гипотезы по
порядку: (1) не загружен ROM-patch консью (`soc3_0_ram_mcu_e1_hdr.bin` — eco E1
совпадает с `Chip ID[6771] Version[E1]`), в вендорском `mt6771.c` его нет вовсе,
а `mt6765.c`/`mt6761.c` качают через `mtk_wcn_soc_rom_patch_dwn()`; (2)
`kalSetEmiMpuProtection()` — заглушка («EMI MPU function is not defined»), без
неё прошивка может не получить доступ к своему EMI; (3) адреса загрузки/старта
из DT `hardware-values = <0x788 0xa5800 0xa5800>`.

## 30. M8: READY-бит не встаёт — MCU не уходит из ROM; MPU и ROM-patch не реализованы (12.11)

`wlan0` пока нет. Ниже — что измерено и что из этого следует, чтобы не
переоткрывать.

### 30.1 READY-бит: где он на самом деле

`include/nic/mt6630_reg.h`:

```
79:  #define MCR_WCIR          0x0000
249: #define WCIR_WLAN_READY   BIT(21)
252: #define WCIR_CHIP_ID      BITS(0, 15)
```

База для MCR-доступа — **не** окно MCU `0x18070000`, а `wifi@180f0000`:
`os/linux/hif/ahb_sdioLike/ahb.c:293` делает
`HifInfo->HifRegBaseAddr = of_iomap(dev->of_node, 0)`, а `reg[0]` этого узла —
`0x180f0000` (патч 0049). Значит `MCR_WCIR` — это **`0x180f0000`**, и опрос
ready-бита идёт туда.

Измерено на живой плате (плата с загруженным `wlan_drv_gen3`, probe уже
отработал):

```
0x180f0000 = 0x1000f004    bits[15:0] (WCIR_CHIP_ID) = 0xf004, bit21 (WLAN_READY) = 0
0x180f0004 = 0x00000038    <- вот откуда "MailBox 0x38" в сообщении драйвера
0x180f0008 = 0x00010000
0x180f000c = 0xa07f0000    (WFDMA живой)
0x180f0078 = 0x00000000    MCR_D2HRM0R
```

То есть READY действительно не выставлен, регистр читается верно. (Правка к
§29.5: `0x18070000/0x38` из более ранних дампов — это блок MCU config
`0x18070000 = 0x00008a00`, к WCIR он отношения не имеет.)

### 30.2 MCU не исполняет загруженную прошивку

```
0x18070160 = 0x0001572a / 0x0001572c / 0x00015730   (cpupcr, три выборки — tight loop)
0xbfca5800 = 0x00000000 …                          (EMI base + 0xA5800 = fw load addr из DT)
0xbfc80000 = 0x00000000 …                          (EMI + 0x80000, coredump-зона)
0x18070400/404/40c = 0x00000000                    (hang debug MCU)
```

`hardware-values = <0x788 0xa5800 0xa5800>` (load = start = 0xA5800), а PC
крутится на `0x15730` — это **не** адрес прошивки, т.е. MCU сидит в ROM/ловушке
и к загруженному коду не переходил. В EMI по адресу загрузки — нули.

При этом `FW download end` печатается без проверки: `include/config.h:561`
`CFG_ENABLE_FW_DOWNLOAD_ACK=1` отключает `wlanImageQueryStatus()`, поэтому
«скачали» драйвер не подтверждает ничем; файл — контейнер
`CFG_ENABLE_FW_DIVIDED_DOWNLOAD=1` (magic `MTK_WIFI_SIGNATURE` = `'MTKE'`,
`include/wlan_lib.h:649`), и раскладку секций задаёт его заголовок, а не DT.

### 30.3 EMI MPU действительно не настроен (но это не единственная причина)

Обе реализации выключены на этапе компиляции:

```
wlan:   os/linux/plat/mt6771/plat_priv.c:70   #ifdef CONFIG_MTK_EMI
          VOID kalSetEmiMpuProtection(...)    -> emi_mpu_set_protection(&region_info)
common: common_main/platform/mt6771.c:991     #ifdef CONFIG_MTK_EMI
          consys_emi_mpu_set_region_protection()  (region 26, apc LOCK/…/NO_PROTECTION)
```

`CONFIG_MTK_EMI` в mainline не существует, поэтому вызывается weak-заглушка
`os/linux/gl_kal.c:5534` → «EMI MPU function is not defined». Сама
`emi_mpu_set_protection()`/`SET_ACCESS_PERMISSION()` — из MTK-внутреннего
`mt_emi_api.h`, а наш compat-файл `scripts/remote/wifi-compat/mt_emi_api.h` —
**пустая заглушка**. Политика регионов при этом известна из вендорских исходников
(регион 25 в wlan, регион 26 в common), неизвестна только раскладка регистров
EMI MPU.

Логика подсказывает, что MPU сам по себе не мешает *переходу* на адрес старта
(он мешает чтению EMI уже после перехода), поэтому как первопричина «READY не
встаёт» он слабее, чем отсутствующий шаг ROM-patch/bootstrap.

### 30.4 ROM-patch: у MT6771 его нет вовсе

```
common_main/platform/mt6771.c     : 0 вхождений "rom_patch" (grep)
common_main/platform/mt6765.c:1096: consys_dl_rom_patch() -> mtk_wcn_soc_rom_patch_dwn(ip_ver)
common_main/platform/mt6761.c:1081: то же
common_main/core/wmt_ic_soc.c:3387: mtk_wcn_soc_rom_patch_dwn()
    ... osal_memcpy_toio(patchAddr, pPatchBuf, patchSize);   <- данные кладутся в EMI
```

Т.е. у соседних SoC патч ROM кладёт в EMI сам WMT-драйвер (`osal_memcpy_toio`),
а не STP; в mt6771-ветке этого шага нет. В `/lib/firmware` уже лежат
`soc3_0_ram_mcu_e1_hdr.bin` (165 344 Б, eco E1 — совпадает с
`Version[E1]`), `_1_1_`/`_1a_1_`, `soc3_0_ram_bt_*`.

### 30.5 Следующий шаг

1. Распечатать в `wlanImageDividDownload()` реальные (address, length) каждой
   секции и сверить EMI по этим адресам: если секции легли не на `0xA5800` —
   править `hardware-values`/выбор ветки загрузки; если легли, а MCU всё равно в
   ROM — включать ROM-patch.
2. Реализовать `emi_mpu_set_protection()` для MT6771 (нужна раскладка регистров
   EMI MPU; политику взять из `mt6771.c:991` и `plat_priv.c:71`) — без неё
   прошивка не имеет гарантированного доступа к своему EMI.
3. Проверить гипотезу ROM-patch: перенести вызов
   `mtk_wcn_soc_rom_patch_dwn()`-подобного шага для MT6771 с файлом
   `soc3_0_ram_mcu_e1_hdr.bin`.
