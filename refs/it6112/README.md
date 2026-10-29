# refs/it6112 — драйвер панели BOE TV110XUM-LB2 через мост ITE IT6112

## Источник

| Поле | Значение |
|---|---|
| Репозиторий | `github.com/linux-mediatek/linux` |
| Ветка | `adomerle/mt6771-next` (base 6.16.0) |
| Коммит | `935fe30b25b0e261235c838ca08f409ceff87b1a` |
| Автор | Arseniy Velikanov `<me@adomerle.pw>`, 2025 |
| Статус | **WIP**, в mainline не принят, в дереве помечен `[WIP]` |
| Лицензия | GPL-2.0 |
| Файл | `panel-it6112-boe-tv110xum-lb2.c`, 515 строк, sha256 `4d4dd33a…91fef` |

Файл скопирован без изменений. Правки — только патчем поверх, с пометкой.

## Что это значит для проекта

Раньше в `docs/hardware.md` и `docs/drm-port-plan.md` панель считалась
«только бинарником» и кандидатом на RE. Это **устарело**: init-последовательность
и весь путь включения панели есть в исходнике (пусть и WIP).

Ключевые факты из драйвера:

- Панель подключена **не напрямую к DSI**, а через мост **ITE IT6112**
  (DSI → dual-channel, «DSI-DUAL_DSI»). Драйвер — гибрид i2c-драйвера моста и
  `drm_panel`.
- I2C: сам мост (MIPI TX) — клиент по адресу **0x56** на `i2c3` (из board DTS
  adomerle); MIPI RX — dummy-клиент **0x5e** на том же адаптере.
- Product ID = `(revid << 8) | chipid`, ожидается **0x6112**.
- `compatible = "boe,tv110xum-lb2-it6112"`; DSI-устройство регистрируется как
  `boe-tv110xum-lb2`, `channel = 0`.
- DSI: **4 lane**, `MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_VIDEO_SYNC_PULSE`,
  RGB888.
- Режим: 1600×2176, `clock = (1600+109+34+10)*(2176+220+28+8)*60/1000` =
  **255798 кГц**, `width_mm=166`, `height_mm=226`.
- Питание: `regulator_bulk` из `dvdd`, `vpos`, `vneg`; reset GPIO (в board DTS —
  `&pio 45`, active high); backlight — `drm_panel_of_backlight`
  (`pwm-backlight`, PWM0 + GPIO56).
- Инициализация моста — I2C-регистры (0x05/0x06/0x10/0x11/0x24/0x3c/0x44/0x45/
  0x47/0xb0 для TX, 0x05/0x09/0x0a/0x0b/0x0c/0x11/0x18/0x19/0x20/0x21/0x27/
  0x44/0x72/0x80/0x8a/0xa0/0x94–0x9b для RX), после чего DCS-команды панели
  прокидываются через регистр **0x73** (exit sleep / display on / off / enter
  sleep).
- `it6112_mipi_rx_calc_clk()` измеряет RCLK/MCLK через регистры 0x95–0x9b.

## Что проверить перед использованием

1. Драйвер написан под 6.16: `devm_drm_panel_alloc()` (helper появился в 6.16),
   `dev_err_probe`, `drm_panel_of_backlight`. В 6.12.114 нет
   `devm_drm_panel_alloc` — при бэкпорте заменить на `devm_kzalloc` +
   `drm_panel_init` + `drm_panel_add`.
2. `it6112_bridge_remove()` вызывает `mipi_dsi_detach()` без проверки, что
   `mipi_dsi_attach()` был; и не проверяет `mipi_dsi_attach` ret в probe.
   Это WIP-качество, не эталон.
3. Питание `vpos`/`vneg` на T1100 даёт **MT6370** (dsvpos/dsvneg), `dvdd` —
   фиксированный регулятор на GPIO55. Без `mt6370`-регуляторов панель не
   включится.
4. Тайминги и init не проверены на нашем ядре/сборке — только исходник.
