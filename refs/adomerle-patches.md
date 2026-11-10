# refs/adomerle-patches.md — обзор патчей adomerle

Дата обзора: **10.11.2026**. Источник: `github.com/linux-mediatek/linux`,
автор **Arseniy Velikanov** (`adomerle`). Все ветки — WIP, в mainline не
отправлены. Это не наши патчи: страница фиксирует, что из них применимо к
FPlus T1100, а что нет.

## Как считали

- HTML-страница `commits?author=adomerle` по умолчанию открывает ветку
  `mt6789-next`.
- GitHub API с `author=adomerle&per_page>5` часто отдаёт **500**;
  `per_page=5` работает. Надёжный путь — `commits?sha=<branch>&per_page=100`
  без фильтра автора и фильтрация по `author.login` локально.
- Все коммиты adomerle укладываются в первую страницу каждой ветки.
- `github.com/.../commit/<sha>.patch` отдаёт **429**; диффы брались через API
  с `Accept: application/vnd.github.v3.diff`.

Итого: **8 веток**, **234 вхождения**, **96 уникальных коммитов** (по subject).

| Ветка | Коммитов | Тема | Применимость |
|---|---:|---|---|
| `adomerle/emerald-tcpc` | 46 | TCPC/SC6601 для другого устройства | нет: у нас MT6370 |
| `adomerle/mt6765-next` | 14 | MT6765: watchdog, GCE, IOMMU/SMI, power domains, pinctrl EINT, pwrap reset | нет: другой SoC |
| **`adomerle/mt6771-next`** | **13** | **наш SoC: DTS, TPHY role switch, cpufreq, SVS, IT6112, тач, звук** | **да, см. ниже** |
| `adomerle/mt6789-initial` | 9 | MT6789 bring-up | нет |
| `adomerle/mt6789-next` | 37 | MT6789: клоки, pinctrl, IOMMU, PMIC, DVFSRC, DRM, panfrost | нет |
| `adomerle/mt6789-sound` | 45 | MT6789 sound WIP | нет |
| `adomerle/mt6789-whar` | 15 | MT6789 WHAR | нет |
| `mt6789-next` | 55 | то же + WHAR | нет |

## Ветка `mt6771-next` (base 6.16.0)

| Коммит | Патч | Статус у нас |
|---|---|---|
| `1ef72e97b1` | arm64: dts: mediatek: Add MT6771 | база нашего DTS, лежит в `refs/mt6771-next/` |
| `2aee822a91` | arm64: dts: mediatek: Add FPlus T1100 | референс платы (886 строк), лежит в `refs/` |
| `083d4e7fa2` | [WIP] drm: panel: Add it6112 boe tv110xum lb2 | основа патча 0038, лежит в `refs/` |
| `0f649f913f` | input: hx83112b: Add support for HX83102E | вошло в 0040; remote сделал новее |
| `41dd7e6871` | input: hx83112b: Add vdd supply | вошло в 0041; remote сделал новее |
| `5aaf4f5475` | dt-bindings: hx83112b: Add hx83102e compatible | документация, лежит в `refs/` |
| `6a9a887e29` | dt-bindings: hx83112b: Add vdd-supply | документация, лежит в `refs/` |
| **`96fe48bed8`** | **phy: mediatek: tphy: Add software role switching** | **главный кандидат, лежит в `refs/`** |
| `86c0a60f75` | soc: mediatek: svs: Add MT6771 support | позже, зависит от efuse/DT |
| `4bc5483278` | cpufreq: mediatek: Add MT6771 && MT8788 compatible | позже, нужны CPU OPP в DTS |
| `ee51e22b85` | regulator-coupler: Add MT6771 and MT8788 | позже, для GPU DVFS |
| `f8bbc91fcf` | sound: mt8183: Add MT6358 ES7210 (T1100) | звук вне v1 |
| `2bca98ef53` | firmware: efi: earlycon: Use ARGB | не нужен |

12 из 13 патчей уже скопированы в `refs/mt6771-next/patches/`; нет только
`2bca98ef53`.

## `96fe48bed8` + `8e0a2656` — USB role switch

- `96fe48bed8` (248 строк) — software role switching в
  `drivers/phy/mediatek/phy-mtk-tphy.c`: workqueue опрашивает
  `usb_role_switch` каждые 100 мс, переключает U2 PHY (SESSEND-импульс 5 мс,
  затем `P2C_RG_IDDIG`), при power-on выставляет force-биты
  IDPULLUP/AVALID/VBUSVALID/SESSEND.
- `8e0a2656` (25 строк, ветка MT6789) — те же force-биты в
  `u2_phy_instance_power_on()` для mobile SoC. Отдельно не нужен: `96fe` уже
  выставляет их сам.
- На синтетическом дереве v6.12 `96fe` применяется **чисто**. С нашим
  `patches/0020-...force-device-mode` он конфликтует: оба правят один регион.
  Правильно **заменить 0020 на 96fe**, а не складывать.
- В mainline 6.12 `drivers/usb/mtu3/mtu3_dr.c` уже умеет role switch
  (`ssusb_role_sw_register()`, `allow_userspace_control = true`), менять
  контроллер не нужно.
- Для работы нужна DT-обвязка:
  - `&ssusb`: `usb-role-switch;` и `role-switch-default-mode = "peripheral";`
  - `&u2port0`: `mediatek,software-role-switch;`
  - graph endpoint между `u2port0` и `ssusb`.
- В **собственном DTS adomerle** этой обвязки нет: там `dr_mode = "peripheral"`
  с комментарием «Dual-role is broken for now», а endpoints идут только к TCPC.
  То есть патч в ветке есть, но на его плате role switch не включён.
- Ограничение: role switch **не даёт 5 В на VBUS**. Питание порта — OTG-boost
  MT6370, а наш TCPC sink-only/выключен. Для host-режима нужен либо контроль
  boost, либо self-powered hub/устройство.

## Что не поможет

- **Тач**: `0f649f`/`41dd7e` у нас уже есть; проблема «контроллер отвечает,
  кадров нет» ими не решается. Нужен RE вендорского `himax_common`
  (handshake `sense_off → flash check → reload_disable → sense_on`, формат
  кадра HX83102E). В remote-патчах 0040/0041 уже добавлен AVDD GPIO163 — это
  новее adomerle.
- **Wi-Fi/BT**: в ветках adomerle нет ничего по CONNSYS/WMT/MT6631.
- **MT6789/MT6765/emerald**: другой SoC/плата. `5761edbe` — pinctrl EINT
  MT6765, к нашему EINT1 не применим; `390ee883` — pwrap reset MT6765;
  `62de3871` — DRM routing MT6789.

## Прочие зацепки на будущее

- `ee51e22b85` (coupler MT6771/MT8788) + `047bc794` (panfrost MT6789:
  `legacy_supplies` → `default_supplies`) — идея для GPU DVFS, на MT6771 не
  проверялась.
- `4bc5483278` (cpufreq) — заработает только с CPU OPP/voltage в DTS.
- `86c0a60f75` (SVS) — питание/тепло, позже.
- `3e6c84ec` — `mtk_mutex_get()` → `-EPROBE_DEFER`, маленький generic-фикс
  mediatek-drm; актуальность для 6.12 не подтверждена.

## Где лежит

- 12 патчей: `refs/mt6771-next/patches/`; DTS — `refs/mt6771-next/`.
- Временные данные обзора: `/tmp/opencode/adomerle/` (`uniq.tsv`,
  `all_sorted.tsv`, `patches/`). В git не коммитятся.
