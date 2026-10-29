# Публичные источники и оценка

## Ключевой факт

**MT8788 = MT6771 = Helio P60/P70 — один и тот же кристалл.** Подтверждено в
публичном research-репо `ax12-research` (раздел MT8788 Platform Research).
Поэтому применимы наработки по MT6771 / Helio P60.

## Исходники downstream-ядра MT6771 (драйвер дисплея, DTS, панель)

| Репозиторий | Качество | Комментарий |
|---|---|---|
| `github.com/Hadenix/android_kernel_alps-4.4` | **точное** | 4.4.146, `mt6771`, есть `drivers/misc/mediatek/video/mt6771/dispsys/` |
| `github.com/nokia-dev/android_kernel_nokia_mt6771` | хорошее | Nokia 3.1 Plus, тот же SoC; дисплей/ISP |
| OrangePi 4G-IOT BSP | хорошее | общий MTK-фреймворк драйверов |
| `github.com/deadman96385/android_kernel_zte_mt6761` | справочное | `video/mt6765/videox/mtkfb.c`, `primary_display.c` |

> Наше ядро — 4.14.186, а Hadenix — 4.4.146. Фреймворк `dispsys`/`mtkfb` тот же;
> регистровые последовательности переносимы, специфику 4.14 (DTS/clk) берём из
> DTS планшета и near-mainline репо.

## Mainline / near-mainline

- **`drivers/gpu/drm/mediatek`** (mainline): MT6771 нет — но это каркас порта.
- **panfrost** (kernel `CONFIG_DRM_PANFROST` + Mesa): поддерживает Bifrost,
  включая **Mali-G72** (GLES 3.1 с Mesa 21.2+).

### Главное открытие (28.10.2026): MT6771 ≈ MT8183

Проверено по стоковому DTB устройства (`refs/stock-mt6771.dts`) и mainline
`arch/arm64/boot/dts/mediatek/mt8183.dtsi`:

| Что | MT6771 (сток) | MT8183 (mainline) | Совпадает |
|---|---|---|---|
| DISPSYS OVL0 / OVL_2L0 / OVL_2L1 | 0x14008000 / 9000 / a000 | то же | ✅ |
| RDMA0 / RDMA1 / WDMA0 | 0x1400b000 / c000 / d000 | то же | ✅ |
| COLOR0 / CCORR0 / AAL0 / GAMMA0 / DITHER0 | 0x1400e000…14012000 | то же | ✅ |
| DSI0 / DPI0 / MUTEX / LARB0 / SMI | 0x14014000 / 15000 / 16000 / 17000 / 19000 | то же | ✅ |
| `mmsys` | 0x14000000 | 0x14000000 | ✅ |
| GPU | 0x13040000, IRQ 278/279/280 | 0x13040000, IRQ 278/279/280 | ✅ |
| PMIC | MT6358 | MT6358 | ✅ |
| topckgen / infracfg_ao / pericfg | 0x10000000 / 10001000 / 10003000 | то же | ✅ |
| GPU | Mali-G72 MP3 | Mali-G72 MP3 | ✅ |

Вывод: **MT6771 — это «MT8183 без части IPU/ISP»** (или наоборот, MT8183 —
tablet-версия MT6771). Значит:
- `mtk_disp_ovl/rdma/color/ccorr/aal/gamma/dither/dsi/mutex/smi` из mainline
  применимы к MT6771 через новые `compatible`/mmsys-route-таблицу;
- panfrost для G72 MP3 уже работает на MT8183;
- MT6358-регуляторы/RTC можно переиспользовать;
- главная новая работа — **clock-драйвер MT6771** (`clk-mt6771-top/infra/peri/
  apmixed/mfg/mm`), **pinctrl-mt6771** и DTS/панель.

### WIP-порт MT6771/FPlus T1100 в linux-mediatek (29.10.2026)

В `github.com/linux-mediatek/linux` есть ветка **`adomerle/mt6771-next`**
(Arseniy Velikanov, base 6.16.0) — существующий WIP-порт **нашего планшета**.
Скопировано в `refs/mt6771-next/`:

- `mt6771.dtsi` — 41 строка: `#include "mt8183.dtsi"` + `compatible =
  "mediatek,mt6771"` + удаление `cpu-idle-states`/`operating-points-v2`
  («cpuidle & cpufreq are broken with android firmware»).
- `mt8788-fplus-t1100.dts` — 868 строк полного board DTS: тач `himax,hx83102e`
  (i2c0 0x48), HDMI `ite,it66121` (i2c3 0x4c, от DPI0), панель `boe,tv110xum-lb2-it6112`
  (i2c3 0x56), PMIC `mt6370` (i2c5 0x34), eMMC HS400/SD, USB peripheral,
  `simple-framebuffer` @ `0x7cb80000`, `&iommu disabled`.
- `drivers/gpu/drm/panel/panel-it6112-boe-tv110xum-lb2.c` — драйвер панели
  (коммит `935fe30`, WIP) → `refs/it6112/`.

**Нет** `clk-mt6771`, `pinctrl-mt6771`, `mt6771-mmsys`: вся инфраструктура
берётся из MT8183. Это подтверждает план «MT8183 как шаблон» и снижает риск
clock-драйвера: возможно, отдельный `clk-mt6771` на первом этапе не нужен.

Второй референс — **MT8365 (Genio 350)** в mainline: полный набор
`mt8365-disp-*`, `mt8365-mmsys`, `mt8365-mali` (Bifrost) — полезен там, где
у MT6771 отличия от MT8183 (MMSYS-раскладка у MT8365 другая: OVL0 @ 0x1400b000).

> **Поправка к прежней версии документа:** ссылка на
> `gitlab.com/Helio-P22/linux-mainline` (bring-up MT6765) **не подтвердилась** —
> публичного проекта с таким именем нет (проверено через GitLab API 28.10.2026).
> MT6765/MT6771 в mainline отсутствуют (`arch/arm64/boot/dts/mediatek` содержит
> только mt6755/6779/6795/6797 из этого поколения). База — mainline + MT8183.
- `ax12-research` → `docs/hardware/mt8788-research.md`: описание конвейера
  дисплея (OVL/COLOR/CCORR/AAL/GAMMA/DITHER/DSI, DIRECT_LINK vs DECOUPLE).

## Что НЕ публично

- **TRM (регистровая документация) MT6771** — phone-SKU, не публикуется.
  **Не блокер:** все смещения регистров есть в исходниках ядра (драйвер +
  MMSYS-заголовки). Ядро — референс.
- **Datasheet LCD-панели** — не публичен, но init-последовательность больше не
  секрет: она есть в WIP-драйвере `refs/it6112/` (linux-mediatek, `935fe30`).

## Дизассемблирование

- Как правило **не нужно**: драйвер дисплея и панель есть в исходниках.
- Нужно только если:
  1. понадобится сверять I2C/регистровую инициализацию моста IT6112 там, где
     WIP-драйвер не покрывает (например, LK-инициализация, `RCLK/MCLK`);
  2. понадобится Android-ный `libmali` — но **panfrost заменяет его**, так что
     и это не требуется.
- Вывод: RE — fallback, не основной путь.

## Оценка

- Всё для **написания** DRM-драйвера публично.
- Узкое место — **инженерная работа** (порт MT6771-дисплея в `mediatek-drm` +
  mainline DTS), а не отсутствие документации.
- GPU (Mali-G72) — самая простая часть (panfrost). Дисплей (KMS) — самая сложная.
