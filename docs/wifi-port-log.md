# Фаза 5, путь A: build-only спайк вендорского стека (журнал)

Статус: **майлстоун 1 (build-only) выполнен**. Собрано/клонировано, снят каталог
API-долга 4.14 → 6.12, оценены «механическое» vs «переписывание», предложен
порядок работ. **Устройство не трогали** (на планшете параллельно идёт работа по
тачу), ничего не прошивали, дерево `../linux-t1100` не меняли, патчей не
добавляли — вся работа на build-хосте `172.17.141.172` в отдельных каталогах.

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
