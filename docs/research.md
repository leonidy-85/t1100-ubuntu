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

- **`drivers/gpu/drm/mediatek`** (mainline): поддерживает MT8173/8183/8186/8192/
  8195/8196/8365/8395 и др. **MT6771 нет** — но это каркас для порта.
- **`gitlab.com/Helio-P22/linux-mainline`** — mainline bring-up **MT6765
  (Helio P22)**: то же поколение MMSYS/DISPSYS, что P60/P70 — **лучший референс**.
- **panfrost** (kernel `CONFIG_DRM_PANFROST` + Mesa): поддерживает Bifrost,
  включая **Mali-G72** (GLES 3.1 с Mesa 21.2+).
- `ax12-research` → `docs/hardware/mt8788-research.md`: описание конвейера
  дисплея (OVL/COLOR/CCORR/AAL/GAMMA/DITHER/DSI, DIRECT_LINK vs DECOUPLE).

## Что НЕ публично

- **TRM (регистровая документация) MT6771** — phone-SKU, не публикуется.
  **Не блокер:** все смещения регистров есть в исходниках ядра (драйвер +
  MMSYS-заголовки). Ядро — референс.
- **Datasheet LCD-панели** — init-последовательность берётся из LCM-драйвера
  ядра / DTS.

## Дизассемблирование

- Как правило **не нужно**: драйвер дисплея и панель есть в исходниках.
- Нужно только если:
  1. init панели окажется в прекомпилированном `.o` без исходника;
  2. понадобится Android-ный `libmali` — но **panfrost заменяет его**, так что
     и это не требуется.
- Вывод: RE — fallback, не основной путь.

## Оценка

- Всё для **написания** DRM-драйвера публично.
- Узкое место — **инженерная работа** (порт MT6771-дисплея в `mediatek-drm` +
  mainline DTS), а не отсутствие документации.
- GPU (Mali-G72) — самая простая часть (panfrost). Дисплей (KMS) — самая сложная.
