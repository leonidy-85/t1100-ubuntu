# Аппаратное декодирование видео на MT6771: состояние и план

Обновлено: 20.11.2026. Состояние: **SCP загружен, vcodec пробуется**:
`/dev/video0` зарегистрирован, H.264 stateless виден; реальный декод кадра ещё
не проверен. Главный блокер снят: mainline `mtk_scp` поднимает SCP на MT6771 с
прошивкой MT8183 из linux-firmware.

## 0. Результат спайка A (20.11.2026)

- DTB: добавлены `scp@10500000` (`mediatek,mt8183-scp`, IRQ 174) и
  `reserved-memory/memory@50000000` (41 MiB, `no-map`).
- Прошивка: `mediatek/mt8183/scp.img` (ELF32, 1 030 776 Б, sha256
  `401e9c02…`), в ней есть строки `VDEC_SERVICE`, `h264`, `vp9`.
- Результат: `remoteproc0` → `running`, FW
  `kukui_scp_v2.0.13324-280b9fce97`, IRQ 174 приходит.
- Подробности, грабли (IRQ `0x174` вместо `0xae`) и repro —
  `docs/scp-bringup.md`, скрипт `scripts/dtb-add-scp.py`.
- vcodec: добавлен `video-codec@16020000`, `mtk-vcodec-dec` пробуется,
  `/dev/video0`, формат **H.264 Parsed Slice Data** (`0x34363253`). Детали и
  грабли (`0x250`/`0x10` вместо `0xfa`/`0xa`) — `docs/vcodec-bringup.md`.

Главная поправка к прежнему тексту: стоковая `scp_a` (p21) — **не ELF**, а
контейнер `tinysys-loader-CM4_A`; mainline `mtk_scp` её не грузит. Рабочий
путь — ELF-прошивка MT8183, а не стоковая.

## 1. Что известно точно

| Факт | Значение | Источник |
|---|---|---|
| Блок VDEC у MT6771 | регистры `0x16020000…0x16028000`, IRQ **GIC_SPI 250** | `refs/stock-mt6771.dts`: `vdec@16020000`, `vdec_pp@16025000`, `hevc_vld@16028000` |
| У MT8183 в mainline | те же адреса и **та же IRQ 250** | `arch/arm64/boot/dts/mediatek/mt8183.dtsi`: `video-codec@16020000` |
| Драйвер mainline | `mediatek,mt8183-vcodec-dec` (drivers/media/platform/mediatek/vcodec) | `mtk_vcodec_dec_drv.c` |
| Что требует драйвер | rproc-фантом `mediatek,scp` **или** `mediatek,vpu`, дальше IPI-команды `AP_IPIMSG_DEC_*` | `mtk_vcodec_dec_drv.c`, `common/mtk_vcodec_fw_*.c` |
| SCP у MT6771 | `scp@10500000`, SRAM `0x80000`, cfg `0x105c0000…0x105d9080`, IRQ **GIC_SPI 174** | `refs/stock-mt6771.dts` |
| SCP у MT8183 в mainline | `scp@10500000`, SRAM `0x80000`, cfg `0x105c0000`+`0x19080`, IRQ **GIC_SPI 174** | `mt8183.dtsi`, `drivers/remoteproc/mtk_scp.c` |
| mainline `mtk_scp` | поддерживает mt8183/8186/8188/8192/8195; MT6771-совместимого нет, но блок совпадает | `mtk_scp_of_match[]` |
| Стоковая `scp_a` (p21, 8 МиБ) | sha256 `245356a6172df48923bad51665dfe8a9b483132ddf1e2826b06775accfd34039`; контейнер `88 16 88 58` / `tinysys-loader-CM4_A`, **ELF-заголовка нет** | дамп p21, `strings` |
| Сервис видео в стоковой SCP-прошивке | **отсутствует**: строк `vdec`/`codec`/`h264`/`hevc`/`vp9` — 0 | `strings -n 4 scp_a.img \| grep -ic vdec` → 0 |
| Сервис видео в MT8183 `scp.img` | **есть** `VDEC_SERVICE`, `h264`, `vp9` | `strings` linux-firmware |

Вывод: SCP-блок MT6771 и MT8183 одинаковый (адрес, IRQ, окно cfg, `tinysys`
+ IPI), поэтому mainline-драйвер с `mediatek,mt8183-scp` работает. Стоковая
прошивка для этого не годится, а MT8183-прошивка уже содержит VDEC-сервис.

## 2. Почему это не «включить узел в DTS»

В `mt6771.dtsi` узел `vcodec_dec` был **удалён** с комментарием «нужна
SCP-прошивка» (`/delete-node/ &vcodec_dec;`). Теперь SCP есть, но одного
включения узла мало:

- `mtk-vcodec` ждёт ответа `scp_get_vdec_hw_capa()` по IPI; нужно проверить,
  что прошивка MT8183 отвечает на этот запрос на MT6771;
- нужен IOMMU: сейчас он выключен (`/* IOMMU breaks simple-framebuffer */`),
  а vdec использует 7 IOMMU-портов;
- нужен драйвер часов `vdecsys` (гейты `vdec_vdec`, `vdec_larb1`) и
  `smi_larb1`;
- нужен userspace с V4L2 stateless (GStreamer `v4l2codecs`, mpv
  `--hwdec=v4l2request`).

Вендорный путь (VAL/VPU) не публичен: в публичном дереве 4.4.146 для MT6771
нет ни `drivers/media/platform/mtk-vcodec`, ни исходников vcodec — только
дисплейный `video/mt6771`.

## 3. Варианты и их цена

| Вариант | Что нужно | Оценка |
|---|---|---|
| **A. Порт `mtk_scp` под MT6771** | DTB-узлы, `memory-region`, ELF-прошивка MT8183 | **выполнено 20.11**: SCP `running`; декод ещё не проверен |
| **B. Порт `mtk-vcodec` (stateless)** | вернуть `vcodec_dec`, IOMMU, часы `vdecsys`, larb1; проверить IPI `DEC` | 1–2 недели, риск ABI прошивки |
| **C. Свой VDEC-драйвер по вендорному VAL** | вендорный исходник (не публичен), карта регистров, формат firmware | недели/месяцы, высокий риск |
| **D. Софт-декод (как сейчас)** | ничего: VP9/AV1 на CPU | работает; 720p–1080p комфортно, 4K дорого |
| **E. GPU-декод** | Mali-G72 **не имеет** видеоблока (это отдельный IP) | невозможно |

**Решение:** продолжаем B (порт `mtk-vcodec`), C — только если B упрётся в
несовместимость прошивки. D остаётся fallback. Узел `vcodec_dec` возвращаем
только вместе с IOMMU и проверкой IPI.

## 4. Следующий этап: vcodec

1. **DT — сделано.** `video-codec@16020000` возвращён, IRQ 250 (level-low),
   VDEC-домен 10, `vdecsys`/`larb1` на месте. `iommus` пока не добавлены.
2. **Драйвер — сделано.** `mtk-vcodec-dec` грузится, probe возвращает 0,
   `/dev/video0` зарегистрирован.
3. **Осталось: userspace.** GStreamer `v4l2codecs` (`v4l2slh264dec`),
   `v4l2-request-test` или mpv `--hwdec=v4l2request`; в rootfs сейчас нет
   `v4l2-ctl`/`gst-launch-1.0`/`ffmpeg`.
4. **Осталось: IOMMU.** Для реального DMA, вероятно, нужны `iommus` (7 портов
   VDEC) и проверка IOMMU-группы larb1.
5. **HEVC** не цель: mainline HEVC-путь только для LAT (MT8192/8195), у
   MT6771 его нет; вендорный HEVC — только OMX-блоб.

## 5. Что это даёт проекту

- SCP сам по себе — шаг вперёд: в вендорной схеме через него идут сенсоры,
  аудио, камера.
- Аппаратный H.264/VP8/VP9 — реальный путь к 1080p/4K без 170 % CPU.
- HEVC и браузерное ускорение, скорее всего, останутся на софт-декоде.
