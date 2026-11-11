# Фаза 5: Wi-Fi/BT — идентификация, оценка путей, план

Статус: **исследование и план**. Ничего не прошивалось, на устройстве только
read-only чтения (`uname`, `regulator_summary`, список разделов, `journalctl -k`).
Итог: чип и шина идентифицированы, найден **публичный вендорский стек ровно для
MT6771** (GPL-2.0), рекомендация — сначала USB-host + mainline-донгл, затем порт
внутреннего стека отдельной веткой.

---

## 1. Что за чип и какая шина (только факты)

### 1.1 Combo = MT6631 (CONSYS_6771), Wi-Fi через AHB/WFDMA, не SDIO и не USB

| Утверждение | Доказательство |
|---|---|
| Чип — **MT6631** (семейство MT6630/6631, «CONSYS_6771») | в `/vendor/firmware` лежат `mt6631_fm_v1_patch.bin`, `mt6631_fm_v1_coeff.bin` (FM-часть того же combo), `refs/aurora-5.2.1.200.md` (список прошивок, размеры, sha256) |
| Сборка стока — именно CONSYS_6771 | `refs/device/config-stock.gz`: `CONFIG_MTK_COMBO_CHIP_CONSYS_6771=y`, `CONFIG_MTK_COMBO_WIFI=y`, `CONFIG_MTK_COMBO_BT=y`, `CONFIG_MTK_COMBO_GPS=y`, `CONFIG_BT_HCIUART_H4=y`, `CONFIG_CFG80211=y` |
| Wi-Fi-прошивка — `WIFI_RAM_CODE_6759` | файл в `/vendor/firmware` (480 752 Б); в публичном gen3-драйвере `#if defined(MT6631)` A-die id `0x6771` **переводится в `0x6759`** и подставляется в имя файла (`os/linux/gl_kal.c`, Motorola gen3 Pie-9) |
| Шина — **AHB (CONNSYS shared memory + WFDMA)**, HIF `ahb_sdioLike` | стоковый DTS `refs/stock-mt6771.dts:1687-1695`: `wifi@180f0000` = `mediatek,wifi`, окна `0x180f0000` (WFDMA), `0x180e0000` (CONN_CFG), `0x10001000` (scpsys/infra), `0x10212180` (третий канал **CQDMA**, ср. `cq_dma@10212000` в том же DTS), IRQ 290/118, клок `wifi-dma`, `hardware-values = <0x788 0xa5800 0xa5800>`; в gen3-исходниках это `os/linux/hif/ahb_sdioLike/` (`ahb.c`, `ahb_pdma.c`, `ahb_cqdma.c`) + `os/linux/plat/mt6771/plat_priv.c`, клок берётся как `devm_clk_get(dev, "wifi-dma")` (`ahb_pdma.c:177`) |
| `hardware-values[0]` — ожидаемый chip id (WCIR), [1]/[2] — адреса загрузки/старта прошивки | `nic/nic.c:655-670` (сверка `WCIR_CHIP_ID` с DT под `#if defined(MT6631)`), `common/wlan_lib.c:550-560` (fw load/start addr) |
| Это **не SDIO** | `msdc0`: `no-sdio` (`refs/stock-mt6771.dts:264`), `msdc1`: `no-mmc` — карта памяти (`:331`); `wifi-pwrseq` (`mmc-pwrseq-simple`) в стоке `status = "disabled"` (`:311-315`) |
| Питание — LDO MT6358 `vcn33_wifi`/`vcn33_bt` 3.3 В | `refs/stock-mt6771.dts:1244-1258` (0x325aa0…0x3567e0); в mainline MT6358 один rail `vcn33` с селектором 1/2/3 и синхронизацией битов WIFI/BT (`drivers/regulator/mt6358-regulator.c:644-676`) |
| Общая RAM для CONNSYS — 2 МиБ, в стоке встала на `0xbfc00000` | `refs/stock-mt6771.dts:460-466` (`consys-reserve-memory`, `no-map`, 2 МиБ, alloc-ranges 0x40000000+0x80000000); dmesg стока: `[CONNADP] reserve_memory_consys_fn … base 0xbfc00000 size 0x200000` |
| Отдельный SoC-узел CONSYS | `refs/stock-mt6771.dts:2206-2213`: `consys@18070000`, `mediatek,mt6771-consys`, окна `0x18070000/0x10007000/0x10001000/0x10006000`, IRQ 289/291, клок `conn` (phandle 0x2e = `scpsys@10001000`, #clock-cells=1) |

Оценка «MT6630 или MT6631» из старых документов уточняется: **6631** (по FM-прошивкам
и по коду `MT6631` → `6759`). MT6630 — предыдущая ревизия того же семейства, ею
в исходниках помечены лишь исторические ветки `#ifdef MT6630`.

### 1.2 Что говорит стоковый лог (важно для выбора пути)

`refs/device/dmesg-stock.txt.gz` — это Aurora **5.1.6.110** (баннер
`Linux version 4.14.186 …`, `preinit: Welcome to Aurora 5.1.6.110`), т.е. ровно та
сборка, бэкап которой у нас есть. В ней Wi-Fi **не инициализировался**:

```
[WMT-CORE][E]wmt_core_stp_init(796):WMT-CORE: no hif info!
[WMT-CORE][E]opfunc_pwr_on(1213):WMT-CORE: wmt_core_stp_init fail (-8)
[WMT-CORE][E]opfunc_hif_conf(1174):WMT-CORE: WMT HIF info added
[WMT-PLAT][E]wmt_plat_eirq_ctrl(636):enable irq wake fail,irq_no(301),iret(-6)
...
[WMT-CORE][E]opfunc_wlan_probe(3462):not implemented yet hifType: 0x2, unspecified wifi_hif
```

Расшифровка по публичным исходникам (Motorola `connectivity-common`, ветка
`Pie-9-release-POBS`, — те же строки, тот же код):

- `wmt_core_stp_init` отказывается работать, если не выставлен бит
  `WMT_OP_HIF_BIT` — «hif» здесь = **STP-транспорт** (UART/SDIO/BTIF), а не шина
  Wi-Fi. Значит, к моменту power-on в этой сборке не был зарегистрирован ни один
  STP-HIF.
- `hifType: 0x2` = `WMT_HIF_BTIF` (enum: `UART=0, SDIO=1, BTIF=2`), а
  `opfunc_wlan_probe()` умеет только UART/SDIO, для остального — «not implemented»
  (комментарий в коде: `Wi-Fi/WMT uses other interfaces. NOT IMPLEMENTED YET!`).
  Т.е. Wi-Fi power-on попал в ветку, которой в этом ядре нет.
- `enable irq wake fail, irq_no(301)` — EINT/wake для CONNSYS не взвёлся.

**ПОПРАВКА (11.11).** Вывод «в стоке Wi-Fi не поднимался» **неверен**: владелец
пользовался Wi-Fi на стоковой Aurora, жалоб не было. Наш лог — одна конкретная
**неудачная** загрузка (после security-off / с изменённой сборкой), где WMT не
получил HIF. Значит эталон рабочего поведения **существует**, и при отладке
power-on CONSYS надо опираться на рабочий сток, а не на этот лог. Причины
именно той неудачи не доказаны (порядок загрузки `wmt_loader`/модулей,
отсутствие `interrupt-names`/EINT в DTS, или сборка Aurora). Оговорка:
записанный лог снят с boot-образа после security-off
(`ima_appraise=off`, `security=diehard`), т.е. не гарантированно «чистый» сток,
но точка отказа (STP HIF до прошивки) от IMA не зависит.

### 1.3 Чем подтверждается, что прошивки/модули — наши

`refs/aurora-5.2.1.200.md` (разбор Aurora RPM) фиксирует:

- модули 4.14.186: `wlan_drv_gen3.ko` (4 083 080 Б), `wmt_drv.ko`,
  `wmt_chrdev_wifi.ko` (42 832 Б), `bt_drv.ko` (65 968 Б), зависимости
  `wlan_drv_gen3 -> wmt_chrdev_wifi, wmt_drv`, `bt_drv -> wmt_drv`;
  vermagic `4.14.186 SMP preempt mod_unload modversions aarch64` → **в 6.12 не
  загрузятся** (vermagic + modversions + отсутствующие `mtk_wcn_*`);
- в строках `wlan_drv_gen3.ko`: `mediatek,wifi`, `MT6631`, `/vendor/firmware/`,
  `WIFI_RAM_CODE_`, `wifi_fw.cfg`, `mtk_wcn_consys_hw_wifi_paldo_ctrl`;
- прошивки: `WIFI_RAM_CODE_6759`, `WMT_SOC.cfg` (119 Б: `coex_wmt_ant_mode=1`,
  `bt_tssi_from_wifi=3`, `bt_tssi_target=3815`, …), `soc3_0_ram_bt_1_1_hdr.bin`
  и `…_bt_1a_1_hdr.bin` (671 276 Б), `soc3_0_ram_mcu_{1_1,1a_1,e1}_hdr.bin`
  (165 344 Б), `ROMv4_be_patch_1_{0,1}_hdr.bin`, `mt6631_fm_v1_{patch,coeff}.bin`,
  `fm_cust.cfg`, `Himax_firmware.bin`.

Порядок вендора (init-скрипты, там же): `wmt_drv` → (power-on + firmware download
через WMT) → `wmt_chrdev_wifi` → `wlan_drv_gen3`; BT — `bt_drv` (STP-char), не
обычный `hci_uart`.

---

## 2. Что доступно локально и публично

### 2.1 Локально

| Где | Что |
|---|---|
| `refs/stock-mt6771.dts`, `refs/device/*` | карта регистров, dmesg/kmsg стока, конфиг ядра, разделы, `iomem` |
| `refs/aurora-5.2.1.200.md` | имена/размеры/sha256 всех 14 прошивок и 4.14-модулей; путь к RPM-репозиторию на `omv-share` |
| `../t1100/backup_5.1.6.110/` | только `boot_a`, `vbmeta_a`, `seccfg`, `fstab` — **прошивок и модулей там нет** |
| локальный `vendor/aurora-5.2.1.200/` | отсутствует (был gitignored; на диске нет) |
| планшет (root по SSH) | `/lib/firmware` **пуст**, `/vendor` не смонтирован; разделов `vendor`/`system` нет — Android-часть в динамическом разделе `super` (`/dev/disk/by-partlabel/super`), `vendor_boot_a` — p30; брать прошивки с платы не требуется (есть RPM-репозиторий) |

### 2.2 Публичные исходники (найдено на build-хосте `172.17.141.172`, `~/wifi-src/`)

Главная находка: **вендорский стек gen3 для MT6771 опубликован Motorola под GPL-2.0**,
ветка Pie-9 (Android 9 / 4.14 — ровно наша генерация):

| Репозиторий (github.com/MotorolaMobilityLLC/…) | Ветка | Объём | Что внутри |
|---|---|---|---|
| `vendor-mediatek-kernel_modules-connectivity-common` | `Pie-9-release-POBS` @ `3ff67212` (2019-11-26) | 75 119 строк | WMT: `common_main/core/wmt_core.c`, `…/platform/mt6771.c` (**1067 строк** — SoC-часть power-on для MT6771!), `include/mt6771.h` (`PLATFORM_SOC_CHIP 0x6771`, pinmux/DCXO/EMI/AP_RGU offsets), `wmt_plat_alps.c`, `common_detect/` |
| `vendor-mediatek-kernel_modules-connectivity-wlan-core-gen3` | `Pie-9-release-POBS` | 213 файлов (88 `.c` + 106 `.h`), **189 991 строка** | Wi-Fi gen3: `nic/`, `mgmt/`, `common/`, `os/linux/` (в т.ч. `hif/ahb_sdioLike/`, `plat/mt6771/plat_priv.c`), `#if defined(MT6631)` → fw `6759` |
| `vendor-mediatek-kernel_modules-connectivity-wlan-adaptor` | ветки Q/S | 222 КБ | адаптер (fw log, `wifi_pwr_on.c`, `wmt_cdev_wifi.c`) |
| `vendor-mediatek-kernel_modules-connectivity-bt-mt66xx`, `-gps`, `-fmradio` | ветки Q/S | — | BT/GPS/FM того же WMT |
| `vendor-mediatek-…-wlan-core-gen4m` | `android-12-release-STA32` | — | gen4m; есть `chips/soc2_1x1` (A-die 0x6631), но имена прошивок другие (`WIFI_RAM_CODE_soc2_2`) — **не наш blob** |
| `haretic/android-kernel-mt6765-rabbitr1` (`drivers/staging/mtk-connectivity`) | `main` @ `382a45e1` | 182 `.c` / 221 `.h`, 14 МБ, ядро 7.3.3 | gen4m+wmt, уже **портирован в mainline-стиль**, но `consys_ic_ops_mt6771 = {}` (weak, пустая!), реализован только `mt6765.c`, чипы — CONNAC |

Проверено и **не** подошло (в in-tree части этих деревьев только адаптер, сам
драйвер out-of-tree): `Hadenix/android_kernel_alps-4.4` (`e73397b`),
`realme-mt6771-devs/android_kernel_realme_mt6771` (`android-13.0`, 4.4.167),
`ubuntu-touch-unihertz-titan/kernel-alps-mt6771` (`0c8b1b0`),
`oppo-source/android_kernel_oppo_mt6771` (`62bb52f`). Публичного gen4m/gen3 с
реализованными `consys_ic_ops_mt6771`, кроме Motorola Pie-9 `common`, не нашлось.

Лицензии: все перечисленные vendor-файлы — GPL-2.0 (шапки «GNU General Public
License version 2»), т.е. порт законен; прошивки — проприетарные блобы, в git не
класть.

---

## 3. Путь A — порт вендорского стека (`wmt` + gen3) на 6.12

### 3.1 Что даёт

Публичный код **ровно под наш чип, нашу прошивку и наш SoC** (включая
`platform/mt6771.c` — последовательность power-on: pinmux A-die, AP2CONN OSC,
EMI mapping, AP_RGU reset, DCXO через pwrap, `vcn33` LDO, клоки). Это снимает
главный риск «нет TRM»: регистры берутся из кода, а не из головы.

### 3.2 Объём работ

1. **Сборка под 6.12** (build-host, без железа): вынести gen3+common в
   `drivers/staging/mtk-connectivity/` (или out-of-tree kbuild), добавить
   compat-слой. Метрика готовности: `wlan_drv_gen3.ko` и `wmt_drv.ko` линкуются.
   API-долг (по грепу): 56 мест `KERNEL_VERSION`/`CFG80211_VERSION_CODE`,
   `ndo_do_ioctl` (→ `ndo_siocdevprivate`), `last_rx`, `do_gettimeofday`,
   `netif_rx_ni`, `proc_create`, `cfg80211_ops`, netdev-флаги. Кода много, но
   он изолирован в `os/linux/gl_kal.c`/`gl_init.c`/`hif/*` — правится
   механически.
2. **Заглушки MTK-only подсистем**, которых в mainline нет: EMI MPU
   (`mt_emi_api.h`, `consys_emi_mpu_set_region_protection`), SPM/DCXO, `cpu_ctrl`,
   `pm_qos` (есть), `mtk_eint` (заменить на genirq), `devapc`, `mtk_wcn_consys_hw`
   (clock/CG через CCF, `vcn33`).
3. **DT**: `consys@18070000` (`mediatek,mt6771-consys`), `wifi@180f0000`
   (`mediatek,wifi`, `hardware-values`, `wifi-dma`), `consys-reserve-memory`
   2 МиБ (не пересечь с нашей `ramoops@0x70000000`), supply от MT6358 `vcn33`.
   Клок `wifi-dma` в стоке — topckgen `0x4e`, тот же, что у `cq_dma`; это гейт
   **`infra_cqdma`** (`CLK_INFRA_CQ_DMA`, INFRA2 bit 27, `clk-mt8183.c:782`) —
   в mainline он уже есть, т.е. в DT достаточно
   `<&infracfg CLK_INFRA_CQ_DMA>` (проверить на шаге 1-2). HIF-движок — CQDMA
   (собственный код вендора в `ahb_cqdma.c`, `drivers/dma/mediatek/mtk-cqdma.c`
   не переиспользуется).
4. **Userspace**: `wmt_loader`/`wmt_launcher` (в Aurora RPM `…-tools` только
   бинарники; исходников в публичных деревьях не найдено) — либо минимальная
   реализация STP-init ioctl поверх `/dev/stpwmt`, либо запуск вендорских
   бинарников (bionic, грязно).
5. **Лесенка bring-up** (каждый шаг — проверяемый лог): power-on CONSYS →
   EMI remap/MPU → скачивание `WIFI_RAM_CODE_6759` → `wlan0` → scan/assoc/WPA2.

### 3.3 Риски

- **Стоковый референс не работал** (§1.2): мы отлаживаем не только порт, но и
  сам стек на 6.12 — «должно быть как в стоке» не помогает.
- Power-on CONSYS завязан на MTK-подсистемы (EMI MPU, DCXO/SPM, pwrap) — часть
  придётся эмулировать; ошибка в последовательности = зависание или silent fail.
- Прошивка и handshake (`WMT_OP_HIF_BIT`, `opfunc_wlan_probe`) на 6.12
  не проверялись никем публично.
- BT зависит от того же WMT (`bt_drv`/`bt-mt66xx`), т.е. после Wi-Fi.
- Оценка: **2–3 недели** до «собирается и пробует power-on», **1.5–3 месяца**
  до устойчивого `wlan0` одним инженером; вероятность успеха — средняя.

---

## 4. Путь B — USB host + mainline-совместимый донгл

### 4.1 Что уже есть в 6.12/нашем дереве

- `mtu3` (gadget) + `xhci-mtk` (`&usb_host` уже `okay`, `mediatek,mt8183-xhci`),
  `phy-mtk-tphy`; сейчас `dr_mode = "peripheral"` + `mediatek,force-device-mode`
  (наш патч 0020) и sink-only TCPC (патч 0032).
- **OTG VBUS в mainline есть**: `drivers/power/supply/mt6370-charger.c` реализует
  регулятор `mt6370-usb-otg-vbus` (`of_match = "usb-otg-vbus-regulator"`, лимиты
  тока 0.5/0.7/1.1/1.3/1.8/2.1/2.4 А), а `tcpci_mt6370` умеет `set_vbus()`
  через supply `"vbus"`.
- **Переключение роли**: MT6771 T-PHY имеет сломанный hardware dual-role
  (`mediatek,force-device-mode`, патч 0020; то же в upstream-патче
  `refs/mt6771-next/patches/96fe48bed8-tphy-role-switch.patch`, 155 строк —
  `mediatek,software-role-switch` + workqueue, автор adomerle). В DTS партнёра
  (`refs/mt6771-next/patches/2aee822a91`) уже есть готовый набор узлов:
  `mt6370_otg_vbus: usb-otg-vbus-regulator`, `vbus-supply` на `tcpc`,
  connector `power-role/data-role = "dual"`, `source-pdos`, порты/endpoint к
  `&ssusb`.
- В mainline 6.12 нет драйвера Wi-Fi для MT6631 (`grep -rli mt6631
  drivers/net/wireless` пусто; `mt76` покрывает другие IP).

### 4.2 Что нужно сделать

1. Порт/адаптация `96fe48bed8` (software role switch) к 6.12 + опция
   `mediatek,software-role-switch`.
2. DT (отдельный board-файл/оверлей `…-usbhost.dts`): `dr_mode = "otg"`,
   `usb-role-switch`, `role-switch-default-mode = "host"`, connector
   dual/source-pdos, `ports`/`endpoint`, `usb-otg-vbus-regulator` в узле
   `charger`, `vbus-supply = <&mt6370_otg_vbus>` на `tcpc`; убрать
   `mediatek,force-device-mode`.
3. Конфиг: `CONFIG_MT7601U=y` (или `RTL8XXXU`, `ATH9K_HTC`), `MAC80211=y`,
   `CFG80211=y`, `RFKILL`; прошивки донгла (`mt7601u.bin`, `rtl*.bin`,
   `htc_*.fw`) — в rootfs `/lib/firmware` (сейчас пусто), т.к. в образе нет модулей.
4. Питание: MT6370 boost 5 В / до 2.4 А — донглу хватает; проверить
   `regulator_summary` (`mt6370-usb-otg-vbus`, 5 В) и нагрев.
5. Ограничения, которые надо принять: **порт один** — в host-режиме нет RNDIS
   (единственный канал отладки) и нет зарядки; откат — только через recovery
   (`recovery` — отдельный раздел с собственным ядром/DTS) или второй слот
   `boot_b`. Поэтому: держать рабочий gadget-образ на `boot_a`, host-вариант
   ставить после бэкапа и с проверенным recovery.

### 4.3 Оценка

**2–5 дней** до «донгл перечислился, `wlan0` поднялся» (из них 1 день — сборка и
перепаковка boot, 1 — роль/VBUS), риск низкий (весь код mainline). Минусы:
внешний модуль, занятый порт, нет внутренней радиочасти.

---

## 5. Рекомендация

**Первым шагом — B (USB host + донгл)**, потому что:

- это единственный путь, который даёт «сеть без кабеля» в масштабе дней, а не
  месяцев, и не зависит от неотлаженного вендорского стека;
- он проверяет и оставляет в дереве полезное: role switch T-PHY, OTG VBUS
  MT6370, host-режим `mtu3`/`xhci-mtk` — всё это понадобится и для отладки A
  (например, чтобы поднять донгл для логов, если RNDIS потерян);
- риск для устройства минимальный: только DT/ядро, откат через recovery.

**A (внутренний MT6631) — параллельно, отдельной веткой, без спешки**:
сначала «build-only» спайк (собрать gen3+common под 6.12 на build-хосте, без
прошивки), решение о продолжении — по факту: собралось + прошёл power-on CONSYS
(первый `wmt: power on ok` и попытка скачать `WIFI_RAM_CODE_6759`). Если за
2 недели спайка нет прогресса на power-on — фиксируем B как результат фазы 5,
A остаётся research-веткой.

Порядок работ на устройстве: сейчас там второй разработчик (тач) — железо не
трогаем; B начинаем с build-host и DT, прошивка — после его завершения.

---

## 6. План внедрения (по шагам)

### B. USB host + донгл

1. Build-host: ветка `wifi-usb-host`, патч tphy software-role-switch (адаптация
   `refs/mt6771-next/patches/96fe48bed8`), сборка ядра, `build/remote/`.
2. DT-оверлей host-режима (см. §4.2), отдельный образ; `boot_a` не трогать до
   бэкапа (`../t1100/backup_5.1.6.110/`), recovery проверить до прошивки.
3. Rootfs: положить прошивки донгла в `/lib/firmware`, `wpa_supplicant` +
   `iw` (уже есть в Ubuntu-base? проверить), `systemd-networkd`/`NetworkManager`.
4. Прошить, проверить: `lsusb`, `dmesg | grep -i mt7601`, `ip link`, `iw dev`,
   `wpa_supplicant -i wlan0 -c …`, DHCP, `ping 8.8.8.8`, `apt update`.
5. Зафиксировать в `docs/STATUS.md` (делает lead) и `docs/hardware.md` факты:
   роль по умолчанию, ток/напряжение VBUS, что теряется (RNDIS/зарядка).

### A. Внутренний MT6631 (spike → порт)

1. Build-host: `~/wifi-src` → перенести `connectivity-common` (Pie-9) и
   `wlan-core-gen3` (Pie-9) в отдельное дерево `drivers/staging/mtk-connectivity`,
   собрать под 6.12, вести список ошибок в `docs/mtk-connectivity-port.md`.
2. Заглушки MTK-подсистем (EMI MPU/SPM/DCXO/eint), проверка, что `wmt_drv`
   инициализируется и регистрирует платформу `mt6771`.
3. DT: `consys` + `wifi` + reserved-memory + `vcn33`; проверить `wifi-dma` клок
   (возможно, нужен clk-патч).
4. Первый power-on: лог `wmt: power on ok`, чтение WCIR (`0x788`), скачивание
   `WIFI_RAM_CODE_6759`, старт MCU.
5. `wlan0`, scan, assoc/WPA2; затем BT (`bt-mt66xx`).

---

## 7. Definition of done для фазы 5

**Обязательный минимум («Wi-Fi поднят» для платы):**

- после cold boot на mainline 6.12 есть рабочий интерфейс (внутренний `wlan0`
  или `wlan0` от USB-донгла), видимый в `iw dev`;
- подключение к WPA2-PSK точке, DHCP, `ping` внешнего адреса и DNS-резолв;
- конфигурация (DT/патчи/прошивки/скрипты) в git, образ boot с бэкапом,
  откат проверен на железе;
- в `docs/hardware.md` зафиксировано, каким путём Wi-Fi работает и что при этом
  теряется/ограничено.

**Цель (stretch, внутренний чип):**

- скачивание `WIFI_RAM_CODE_6759` и поднятие `wlan0` без вендорских `.ko`
  (только mainline-порт);
- assoc + WPA2 + `iperf3` ≥ 20 Мбит/с, устойчивость к suspend/resume;
- BT HCI через WMT (тот же CONSYS) — отдельным пунктом.

Wi-Fi/BT-часть **не блокирует** v1 (дисплей/GPU/десктоп); минимум по B —
предпочтительный результат фазы 5.

---

## 8. Открытые вопросы (для следующей итерации)

1. Почему в стоковой 5.1.6.110 WMT не получил STP-HIF: порядок
   `wmt_loader`/модулей, EINT (`irq_no 301`) или DTS (`interrupt-names`)?
   Ответ важен для A: возможно, сток всё же работал в другой сборке.
2. `hardware-values[0] = 0x788` против A-die `0x6759`: сверить с `WCIR_CHIP_ID`
   MT6631 (в gen3 `nic.c` это ожидаемое значение; вендорский DTB — истина).
3. `wifi-dma` клок: **закрыт** — это гейт `infra_cqdma` (`CLK_INFRA_CQ_DMA`),
   есть в 6.12; осталось проверить, что стоковый `0x4e` действительно этот гейт
   (по совпадению с `cq_dma@10212000`).
4. MT6358 `vcn33`: один rail с селектором 1/2/3 — какой селектор нужен Wi-Fi
   (в стоке отдельные биты `vcn33_wifi`/`vcn33_bt`, в mainline они синхронизированы).
5. Публичность `wmt_loader`: исходников не нашли — RE бинарника или своя
   реализация ioctl.

---

## 9. Источники

- `refs/stock-mt6771.dts` (строки 264, 311-315, 331, 460-466, 1244-1258,
  1687-1695, 2206-2213), `refs/device/{dmesg-stock,config-stock,partitions}.gz`,
  `refs/aurora-5.2.1.200.md`, `refs/mt6771-next/patches/{96fe48bed8,2aee822a91}`.
- `github.com/MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-common`
  @ `Pie-9-release-POBS` `3ff67212` (`common_main/platform/mt6771.c`,
  `common_main/core/wmt_core.c:780-810`, `3450-3465`).
- `…/vendor-mediatek-kernel_modules-connectivity-wlan-core-gen3`
  @ `Pie-9-release-POBS` (`os/linux/gl_kal.c:215-245`,
  `os/linux/hif/ahb_sdioLike/ahb_pdma.c:175-185`, `nic/nic.c:640-680`).
- `github.com/haretic/android-kernel-mt6765-rabbitr1` @ `382a45e1`
  (`drivers/staging/mtk-connectivity/`).
- mainline 6.12.114 (дерево сборки): `drivers/power/supply/mt6370-charger.c:641-745`,
  `drivers/usb/typec/tcpm/tcpci_mt6370.c:79-160`,
  `drivers/regulator/mt6358-regulator.c:644-709`,
  `drivers/regulator/mt6370-regulator.c`, `arch/arm64/boot/dts/mediatek/mt8183.dtsi`.
