# VDEC на MT6771: драйвер поднялся, `/dev/video0` есть

Дата: 20.11.2026. Статус: **драйвер `mtk-vcodec-dec` пробуется, VDEC-устройство
зарегистрировано**, формат H.264 stateless виден. Реальный декод кадра ещё не
проверен — для него нужен userspace с V4L2 request API.

## Что сделано

1. В DTB добавлен узел `video-codec@16020000` (наследие `mt8183.dtsi`, но с
   правками под MT6771):

```
video-codec@16020000 {
    compatible = "mediatek,mt8183-vcodec-dec";
    reg = <0 0x16020000 0 0x1000>, ... 11 диапазонов ...;
    reg-names = "misc", "ld", "top", "cm", "ad", "av", "pp",
                "hwd", "hwq", "hwb", "hwg";
    interrupts = <GIC_SPI 250 IRQ_TYPE_LEVEL_LOW>;
    clocks = <&vdecsys CLK_VDEC_VDEC>;
    clock-names = "vdec";
    power-domains = <&spm MT8183_POWER_DOMAIN_VDEC>;  /* 10 */
    mediatek,scp = <&scp>;
    mediatek,vdecsys = <&vdecsys>;
    status = "okay";
};
```

`iommus` пока **не добавлены** — для probe и проверки IPI они не нужны; для
реального декода их, скорее всего, придётся вернуть (7 портов VDEC).

2. Установлены модули (из дерева `/root/kbuild/linux-6.12.114`):

- `mtk-vcodec-dec`, `mtk-vcodec-common`, `mtk-vcodec-dbgfs`;
- `videobuf2-*`, `v4l2-mem2mem`, `v4l2-h264`, `v4l2-vp9`, `videodev`, `mc`;
- автозагрузка: `/etc/modules-load.d/vcodec.conf` → `mtk-vcodec-dec`.

Без `mc` и `v4l2-h264`/`v4l2-vp9` модуль не грузился:
`Unknown symbol media_request_object_init`, `v4l2_h264_init_reflist_builder`.

3. Перепакован boot.img (`build/scp/boot_vcodec2.img`, md5
   `bc48aedf5cee38cab0c8fb11cdd11e5a`, sha256 `afd35d86…`), прошит p29.

## Результат

```
probe of 16020000.video-codec returned 0 after 847 usecs
/sys/bus/platform/devices/16020000.video-codec/driver -> mtk-vcodec-dec
/dev/video0
```

`VIDIOC_QUERYCAP`: `driver=mtk-vcodec-dec`, `card=MT8183 video decoder`.
`VIDIOC_ENUM_FMT` (OUTPUT_MPLANE): **H.264 Parsed Slice Data**,
`V4L2_PIX_FMT_H264_SLICE` = `0x34363253`.

То есть SCP-прошивка приняла VDEC-сервис, драйвер зарегистрировал stateless
H.264-декодер.

## Грабли: `fdtput -t x` и десятичные числа

`fdtput -t x` парсит значения как **hex**. В первой попытке:

- `interrupts = <0 250 8>` превратилось в `<0 0x250 8>` (592 вместо 250);
- `power-domains = <0x47 10>` превратилось в `<0x47 0x10>` (16 вместо 10).

В dmesg: `PM: genpd_xlate_onecell: invalid domain index 16`; probe падал.
Правильно: `interrupts 0 0xfa 8`, `power-domains 0x47 0xa`.

Это та же ловушка, что была с SCP IRQ `0x174` вместо `0xae` (см.
`docs/scp-bringup.md`).

## Ограничения / следующий шаг

- Реальный декод не проверен. Нужен userspace: GStreamer `v4l2codecs`
  (`v4l2slh264dec`), `v4l2-request-test` или mpv с `--hwdec=v4l2request`.
- В rootfs нет `v4l2-ctl`, `gst-launch-1.0`, `ffmpeg`; сначала нужно поставить
  или собрать тестовый клиент.
- Для DMA, скорее всего, понадобятся `iommus` (7 портов VDEC) и проверка
  IOMMU-группы larb1; сейчас VDEC-устройство без `iommus`.
- HEVC/VP9 stateless в mainline для MT8183 нет (HEVC — только LAT); проверяем
  H.264.

## Откат

- Текущий p29: `build/scp/boot_vcodec2.img` (md5 `bc48aedf…`).
- Предыдущий рабочий: `build/scp/boot_scp2.img` (md5 `57ac8b08…`).
- До SCP: `/root/boot_a_before_scp.img` (md5 `efaeaacc…`).

## 21.11.2026: userspace-проверка stateless H.264

Клиент поставлен на планшет:

```sh
apt-get install -y --no-install-recommends \
  gstreamer1.0-tools gstreamer1.0-plugins-bad \
  gstreamer1.0-plugins-ugly v4l-utils
```

Что видно:

- `v4l2-ctl --list-devices` → `MT8183 video decoder (platform:16020000.video-codec): /dev/video0, /dev/media0`.
- `v4l2-ctl -d /dev/video0 --list-formats-out` → только `S264` (H.264 Parsed Slice Data).
- `gst-inspect-1.0 v4l2slh264dec` → plugin `v4l2codecs` 1.28.2.

Тест:

```sh
gst-launch-1.0 -q videotestsrc num-buffers=30 ! \
  video/x-raw,format=I420,width=640,height=480,framerate=30/1 ! \
  x264enc tune=zerolatency speed-preset=ultrafast ! \
  h264parse config-interval=1 ! v4l2slh264dec ! fakesink sync=false
```

Пайплайн доходит до EOS, caps на выходе `NV12_16L32S`, но **каждый кадр**
отвергается firmware:

```
[MTK_VCODEC][ERROR][13]: - NALU[n] err=196738 -
[MTK_V4L2][ERROR] [13] decode src_buf[x] sz=... ret=196738 res_chg=0
```

`196738 = 0x30082`, `DEC_ERR_RET(ret) = 3` — ошибка `H264_ERR_NOT_VALID`
со стороны firmware.

То же с `openh264enc` и с реальным Big Buck Bunny MP4
(`qtdemux ! h264parse ! v4l2slh264dec`).

### Что исключено диагностикой

- **Питание/клоки**: в драйвер временно добавлены `dev_info`; видно
  `hw_id=0`, `enable hw_idx=0 bitmap=1`, `child_on ... bit=1 pm=...`.
  `subdev_bitmap` содержит CORE, `mtk_vcodec_dec_pw_on()` и
  `clock_on()` вызываются. `runtime_status=suspended` между кадрами —
  норма после `disable_hardware`.
- **Start code**: буфер начинается с `00 00 01 65 ...` (Annex B,
  3-байтовый start code, IDR). Принудительная замена на
  `00 00 00 01 65 ...` с обновлением `data[0]` (size 8307) не меняет
  ошибку.
- **Энкодер**: x264, openh264 и готовый MP4 дают одну и ту же ошибку.
- **Длина/формат буфера**: `data[0]` совпадает с `bs->size`, `data[1]` =
  NAL header; драйвер получает валидный Annex B.

### Вывод

AP-сторона (драйвер, power, clock, V4L2) работает. Ошибку возвращает
**VDEC-сервис mt8183-прошивки SCP**: для потока MT6771 он отвечает
`not valid`. Наиболее вероятно — firmware mt8183 несовместим с VDEC
MT6771 (другая ревизия/ABI), либо stateless-контролы (SPS/PPS/decode mode)
не те, что ждёт firmware. Это уже не «включить узел», а вопрос
прошивки/реверса.

Следующие направления:

1. Посмотреть, как декодирует эталонный T800 на Aurora: `/dev/Vcodec`
   (AP-side `libvcodec_oal`), `/dev/vpu`/`vpu_core*` или SCP; снять
   `dmesg`/`strace` во время playback. Это ответит, есть ли вообще у
   MT6771 VPU/AP-side путь, который можно повторить в mainline.
2. Если у MT6771 есть VPU-прошивка (в `vpu_core0/1`), попробовать
   mainline `mediatek,vpu`-путь mt8173.
3. Если только AP-side `libvcodec_oal` — это отдельный драйвер VDEC без
   SCP, месяцы работы/реверса.
4. Пока — софт-декод (H.264 720p/1080p) как рабочий вариант.

Состояние p29: `build/scp/boot_vcodec2.img` (md5 `bc48aedf…`), SCP
`running`, vcodec-модуль чистый, декод не работает.
