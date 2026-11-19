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
