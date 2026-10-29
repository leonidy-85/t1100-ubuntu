# DRM/KMS-порт MT6771: инвентаризация mainline-компонентов

Дата: 29.10.2026. Основано на сверке `refs/stock-mt6771.dts` /
`refs/device/fdt-live.dts.gz` с mainline `arch/arm64/boot/dts/mediatek/mt8183.dtsi`
и `drivers/soc/mediatek/mt8183-mmsys.h` (ветка 6.12.114).

## Вывод

MT6771 и MT8183 — родственные SoC с **одинаковой раскладкой DISPSYS**.
Почти весь дисплейный стек mainline применим к MT6771 через новые `compatible`
и (возможно, идентичную) mmsys-route-таблицу. Новая работа — clock/pinctrl и
панель.

## Инвентарь

| Блок | Адрес MT6771 | mainline-драйвер | Что делать |
|---|---|---|---|
| `mmsys` | `0x14000000` | `drivers/soc/mediatek/mtk-mmsys.c` + `mt8183-mmsys.h` | добавить `mediatek,mt6771-mmsys` c route-таблицей MT8183 (регистры `0xf00…0xf54`, `0x140`) после сверки с downstream |
| OVL (4L) | `0x14008000` | `mtk_disp_ovl.c` (`mt8183-disp-ovl`) | `mediatek,mt6771-disp-ovl` → fallback `mt8183-disp-ovl` |
| OVL 2L ×2 | `0x14009000`, `0x1400a000` | `mtk_disp_ovl.c` (`mt8183-disp-ovl-2l`) | то же для 2L |
| RDMA ×2 | `0x1400b000`, `0x1400c000` | `mtk_disp_rdma.c` | `…-disp-rdma` |
| WDMA | `0x1400d000` | `mtk_disp_wdma.c`? (проверить наличие) | `…-disp-wdma` |
| COLOR / CCORR | `0x1400e000` / `0x1400f000` | `mtk_disp_color.c`, `mtk_disp_ccorr.c` | `…-disp-color/-ccorr` |
| AAL / GAMMA / DITHER | `0x14010000` / `0x14011000` / `0x14012000` | `mtk_disp_aal/gamma/dither.c` | `…-disp-aal/-gamma/-dither` |
| **DSI0** | `0x14014000` | `mtk_dsi.c` (`mt8183-dsi`) | `…-dsi`; IRQ SPI 236 (0xec) |
| DPI0 | `0x14015000` | `mtk_dpi.c` (`mt8183-dpi`) | не нужен для панели (задел) |
| MUTEX | `0x14016000` | `mtk_disp_mutex.c` | `…-disp-mutex` |
| SMI LARB0 | `0x14017000` | `mtk-smi` (`mt8183-smi-larb`) | `…-smi-larb` |
| SMI common | `0x14019000` | `mtk-smi` (`mt8183-smi-common`) | `…-smi-common` |
| **MIPI TX (DSI PHY)** | `0x11e50000` | `phy/mediatek/phy-mtk-mipi-dsi` (`mt8183-mipi-tx`) | `…-mipi-tx`; сверить PHY-тайминги |
| DISP_PWM | из stock DTB | `pwm/mediatek/pwm-mtk-disp.c` (`mt8183-disp-pwm`) | `…-disp-pwm` |
| **GCE (CMDQ)** | `0x10238000` | `mailbox/…/mtk-cmdq-mailbox.c` (`mt8183-gce`) | `mediatek,mt6771-gce` (сверить число потоков) |
| **M4U (IOMMU)** | `0x10205000` | `iommu/mediatek` (`mt8183-m4u`) | `…-m4u`; **номера портов M4U_PORT_* перепроверить** по downstream |
| MFG (GPU) | `0x13000000`, GPU `0x13040000` | panfrost + `mtk-pm-domains` | `mediatek,mt6771-mali` → `arm,mali-bifrost`; IRQ 278/279/280 (как MT8183) |

## Чего в mainline нет и что придётся писать

1. **`clk-mt6771`** — topckgen, infracfg_ao, pericfg, apmixedsys, mfgcfg, mmsys
   (mm). Основа — `drivers/clk/mediatek/clk-mt8183*.c`; gate-биты сверять с
   downstream `clk-mt6771.c` (Hadenix 4.4 / Realme 4.14). **Главный объём работы
   фазы 1–2.**
2. **`pinctrl-mt6771`** — свои IO-конфиг/EINT (основа `pinctrl-mt8183.c`).
3. **Панель BOE TV110XUM-LB0-1SP0** (1600×2176, 4 lane, video mode) —
   `panel-boe-tv110xum.c`: тайминги + init-последовательность. Исходника LCM
   (`tv110xum_lb2_incell`) в публичных репо нет → кандидат на RE
   (`reverse-engineer`), fallback — минимальный init + проверка на железе.
4. **Backlight**: `pwm-backlight`/`mtk-pwm` + GPIO 56 (из dtbo).

## Первые шаги фазы 2 (после DTS фазы 1)

1. mmsys: `mediatek,mt6771-mmsys` = route-таблица MT8183, но **сначала сверить
   смещения `0xf00…0xf54`, `0x140`** с downstream (`mt6771/mt6771_drm` или
   `disp_lcm`-заголовки). Если совпадают — переиспользуем заголовок как есть.
2. Проверить в mainline наличие `mtk_disp_wdma.c` (если нет — WDMA не нужен для
   DIRECT_LINK пути: `OVL → … → DSI` без промежуточного буфера).
3. Собрать минимальный KMS-путь: `OVL0 → RDMA0 → COLOR → CCORR → AAL → GAMMA →
   DITHER → DSI0` (как в стоке, DIRECT_LINK) либо простейший `OVL0 → DSI0`.
4. Панель: сначала «зажечь» DSI видео-режим с фиксированными таймингами и
   тестовым паттерном (`modetest -s`), потом init панели.
5. Проверка: `modetest -M mediatek`, `kmscube`.

## Риски

- **Регистровые отличия** MT6771↔MT8183 в OVL/MUTEX/DSI (адреса совпадают, но
  версии IP могут отличаться) — проверять по downstream-заголовкам и на железе.
- **Панель**: без init-последовательности экран останется тёмным даже при
  рабочем DSI — это отдельный риск, возможен RE.
- **Clock-драйвер**: без него не поднимутся ни DSI-клоки, ни шина MMSYS.
- **Отладка**: нет UART, логи только `pstore` (`docs/boot-test.md`).
