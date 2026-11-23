# Аппаратное декодирование видео на MT6771: состояние и план

Обновлено: 21.11.2026. Состояние: **SCP и VDEC-драйвер работают,
но mt8183-прошивка отвергает H.264; см. §6**.

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

## 6. Результат 21.11.2026: SCP/VDEC подняты, firmware отвергает H.264

- SCP загружается (см. `docs/scp-bringup.md`), VDEC-драйвер
  `mtk-vcodec-dec` поднимается, `/dev/video0` и `/dev/media0` есть,
  формат `S264`.
- GStreamer `v4l2slh264dec` (1.28.2) доходит до EOS, но firmware mt8183
  возвращает `err=0x30082` (`DEC_ERR_RET=3`) на каждый кадр.
- Исключены: питание/клоки (`subdev_bitmap=1`, `hw_id=0`,
  `pw_on`/`clock_on` вызываются), 3/4-байтовый start code, энкодер
  (x264/openh264/MP4), длина буфера.
- Вывод: проблема на уровне VDEC-сервиса прошивки/железа, а не
  V4L2-обвязки. Нужно понять архитектуру декода на эталонном T800
  (AP-side `/dev/Vcodec`, `/dev/vpu` или SCP) и искать
  MT6771-специфичную прошивку/путь.
- HEVC по-прежнему вне цели; софт-декод остаётся fallback.

## 7. Вендорский AP-side VDEC: `/dev/Vcodec` + 32-битный HAL (21.11.2026)

Проверка Aurora T800 (`defaultuser@192.168.2.76`, Aurora 5.2.1.210, kernel
4.14.186, MT6771V/C) показала: **декодирование там идёт не через SCP**. SCP
занят сенсорами (в dmesg — `lsm6ds3_acc`, `bmi160_acc`, `lis3dh`, `bmp280`,
`akm09915`), а `/dev/vpu` (major 506, owner `system:camera`) и ядра
`vpu_core0/1` (`0x19100000`, `0x19200000`) относятся к камере.

Реальный путь:

```
media.codec (OMX service)
  -> libMtkOmxVdecEx.so
  -> libvcodecdrv.so
  -> ioctl/mmap /dev/Vcodec (char 160:0)
```

`/sys/dev/char/160:0` указывает на `/sys/devices/virtual/Vcodec/Vcodec`;
драйвер `Vcodec` привязан к `16000000.vdec_gcon`. В kallsyms видны
`vcodec_open/release/mmap/unlocked_ioctl`, `vdec_power_on/off`,
`mt_vdec_runtime_suspend/resume`, `mt_vdec_base_get`, `VdecDvfsBegin/End/Step`,
`vcodec_venc_pmqos`. IRQ — `MT_SYSIRQ 250` и `247`.

### Исходник драйвера найден публично

В `oppo-source/android_kernel_oppo_mt6771`, ветка `oppo/mt6771_r_11`:

```
drivers/misc/mediatek/videocodec/
  mt6771/videocodec_kernel_driver.c   ~105 КБ, 3682 строки
  mt6771/videocodec_kernel_driver.h   ioctl ABI, magic 'M'
  mt6771/common/drv/{src,inc}         drv_base.c, dvfs_v2.c, drv_api.h
  mt6771/common/val/src/val.c
  include/...                         val_types_*, hal_types_*, val_api_*
```

Драйвер совпадает с Aurora по символам и ioctl: `vcodec_unlocked_ioctl`
(строка 1894), `mt_vdec_base_get` (484), `VdecDvfsBegin` (361),
`vcodec_venc_pmqos` (1039), `compatible = "mediatek,vdec_gcon"`.

### Важное ограничение: кодек не в ядре

`videocodec_kernel_driver.c` содержит только перечисления типов
H.264/HEVC/VP9, PMQoS и диспетчеризацию IRQ. В `common/val/src/val.c`,
`common/drv/src/drv_base.c`, `dvfs_v2.c`, `hal.c` **нет** кодак-алгоритмов.
`MFV_ALLOC_MEM_CMD` есть только в заголовке (case в драйвере отсутствует),
`VCODEC_ALLOC_NON_CACHE_BUFFER/FREE` — пустые тела. Драйвер делает
питание/клоки/ISR/блокировки/mmap, а H.264/HEVC/VP9 считает **32-битная
user-space `libvcodecdrv.so`**, выделяя память через `/dev/ion`
(`libion_mtk.so`).

### 32-битный runtime на T1100 проверен

T1100: `CONFIG_COMPAT=y`, `CONFIG_COMPAT_BINFMT_ELF=y`; статический ARM32
бинарник работает. Собран bionic-chroot с Aurora: `/system/bin/linker`,
`/system/lib`, `/vendor/lib`, VNDK v30; 32-битный `hello32bionic` и vendor
OMX service запускаются, `strace` подтверждает загрузку ELF32
`/system/lib/libc.so`. Closure: 107 библиотек/бинарников, 0 unresolved
`DT_NEEDED`. Для bionic обязательны `/proc` и `/dev` внутри chroot.

### Блокеры и следующий шаг

| Блокер | Состояние |
|---|---|
| `/dev/Vcodec` | нет в mainline; `bringup` портирует vendor-драйвер на 6.12 |
| `/dev/ion` | нет; `CONFIG_ION` отсутствует, `libion_mtk` ходит в `/dev/ion` |
| `/dev/dma_heap` | нет; `CONFIG_DMABUF_HEAPS` не включён |

Варианты: (1) порт `Vcodec` + 32-битный `libion`-шим над DMA-BUF/memfd;
(2) порт MTK ION; (3) переписать HAL. Пока цель — H.264; HEVC по-прежнему
вне реалистичного пути (mainline HEVC только LAT, вендор — OMX-блоб).

## 8. Legacy/stateful и VP9: прошивка MT8183 отвергает оба пути (23.11.2026)

Проверены две оставшиеся гипотезы: (а) прошивка 2022 г. понимает только
legacy VSI, а не stateless; (б) проблема H.264-специфична, и VP9 пойдёт.

### Legacy H.264

- В match-таблице `mtk_vcodec_dec_drv.c` для `mediatek,mt8183-vcodec-dec`
  временно подставлен `mtk_vdec_8173_pdata` (stateful,
  `uses_stateless_api=false`, `MTK_VDEC_PURE_SINGLE_CORE`); лог подтвердил
  `stateless=0`.
- Написан статический клиент `/tmp/v4l2_stateful_h264` (M2M MPLANE, output
  H264, capture MT21C, по одному NAL на буфер).
- Результат: SPS (`type=7`, 33 Б) и PPS (`type=8`, 9 Б) дают
  `failure=721539` (`0xB0283`), IDR (`type=5`, 4985 Б) — `196738`
  (`0x30082`, `H264_ERR_NOT_VALID`). Init/ABI — `status=0`, `abi=2`.
- Попутно найден и исправлен oops: legacy `vdec_h264_decode()` копировал PPS
  в SCP DMEM через `memcpy`, компилятор делал unaligned store на device
  memory (`FSC=0x21`). Заменено на побайтовый `writeb()`.

### VP9

- `gst-launch-1.0 ... ! vp9enc ! avmux_ivf ! filesink` → `/tmp/test.ivf`
  (7522 Б, `DKIF`/`VP90`).
- Клиент `/tmp/v4l2_stateful_vp9` (тот же M2M, `V4L2_PIX_FMT_VP9`, разбор
  IVF) на `vdec_vp9_init` получает `send fail vpu_id=3 msg_id=A000
  status=-5`: прошивка не регистрирует VP9-сервис, есть только H.264
  (IPI id=1). Строки `vp9` в `scp.img` — не сервис.

### Сверка с ChromeOS 5.10

Структуры `mtk_h264_sps_param`, `mtk_h264_pps_param`,
`mtk_h264_dec_slice_param`, `vdec_h264_vsi`, `vdec_pic_info` в 5.10
**идентичны** 6.12 (VSI 1784 Б); `codec_type` там тоже не заполняется.
Рассинхрон VSI/ABI исключён.

### Вывод

Mainline SCP-путь упирается в несовместимость mt8183-прошивки с VDEC
MT6771: H.264 отвергается и в stateless, и в legacy, VP9-сервиса нет.
IOMMU, клоки, power-domain, SPS/PPS, VSI/ABI, длина буфера исключены.
Дальше — либо MT6771-специфичная VDEC-прошивка (в стоковой SCP её нет),
либо возврат к варианту A: вендорский AP-side `/dev/Vcodec` + 32-битный
HAL, начиная с портов LARB1 (`smi_bus_prepare_enable` — заглушка).
