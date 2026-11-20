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

## Вендорский путь: `/dev/Vcodec` + 32-битный `libvcodecdrv` (21.11.2026)

После проверки T800 стало ясно, что mt8183-прошивка SCP — тупик для MT6771:
на T800 VDEC управляется AP-side драйвером `Vcodec` (`/dev/Vcodec`, char
160:0), а не SCP. SCP там обслуживает сенсоры, VPU — камеру.

- Драйвер `Vcodec` найден в публичном дереве OPPO MT6771:
  `drivers/misc/mediatek/videocodec/mt6771/videocodec_kernel_driver.c`
  (3682 строки), `compatible = "mediatek,vdec_gcon"`, ioctl magic `'M'`.
- Драйвер — инфраструктура: `vcodec_open/release/mmap/unlocked_ioctl`,
  `vdec_power_on/off`, `mt_vdec_runtime_*`, `mt_vdec_base_get`, DVFS/PMQoS,
  IRQ 250/247. Кодак-алгоритмов в нём нет.
- H.264/HEVC/VP9 считает 32-битная `libvcodecdrv.so` (Android bionic),
  она использует `/dev/ion` через `libion_mtk.so`; `libMtkOmxVdecEx.so` —
  OMX-обёртка.
- 32-битный bionic на T1100 уже проверен: `CONFIG_COMPAT` работает,
  chroot с Aurora `/system/bin/linker` + `/system/lib` + `/vendor/lib`
  запускает 32-битные бинарники; нужны `/proc` и `/dev`.
- Блокеры: нет `/dev/Vcodec`, нет `/dev/ion`, нет `/dev/dma_heap`
  (`CONFIG_ION`/`CONFIG_DMABUF_HEAPS` не включены). Драйвер `Vcodec`
  декод-память не выделяет (`MFV_ALLOC_MEM_CMD` без case,
  `VCODEC_ALLOC_NON_CACHE_BUFFER` пустой), поэтому нужен ION/DMA-BUF шим.

Текущая p29: `build/scp/boot_vcodec2.img` (md5 `bc48aedf…`); откат —
`build/scp/boot_scp2.img` (`57ac8b08…`) и `/root/boot_a_before_scp.img`
(`efaeaacc…`). Ничего не прошивалось.

## 20.11.2026 (вечер): PA для CMA-буферов, compat-ioctl и non-cache alloc

Задача: разблокировать 32-битный vendor-HAL — отдать физический адрес
dma-buf из `/dev/dma_heap` и довести compat-ioctl `Vcodec`.

### Kernel: `DMA_HEAP_IOCTL_PHYS` (патч 0079)

`/proc/self/pagemap` не отдаёт PFN для dma-buf (`VM_PFNMAP`), поэтому PA
пришлось экспортировать из ядра. Добавлен heap-private ioctl:

```c
struct dma_heap_phys_data { __u32 fd; __u32 flags; __u64 pa; __u64 size; };
#define DMA_HEAP_IOCTL_PHYS _IOWR('H', 0x1, struct dma_heap_phys_data)
```

- реализован только в **CMA-хеапе** (`/dev/dma_heap/reserved`, он же
  `cma`): буфер — один `cma_alloc()`, поэтому диапазон физически
  непрерывен; проверяется первый/последний PFN, иначе `-ENOTSUPP`;
- `CAP_SYS_ADMIN` обязателен (PA обходит IOMMU); чужой dma-buf
  (`dmabuf->ops != cma_heap_buf_ops`) → `-EINVAL`; system-хеап → `-ENOTTY`;
- в `dma_heap_ops` добавлен опциональный `->ioctl()`, generic dma-buf не
  трогали.

Факты: `Image` #2 (`6.12.114-wifi1`, сборка 20.11 09:56), p29 =
`build/boot_pa.img` (md5 `d7c12647f9ca68dc2e37e31d5cba0f30`, sha256
`0e265c9a…1877ff`). Бэкап p29 до прошивки —
`build/recovery/boot_a_heaps_2026-11-20.img` (md5 `6bc3c35e…`).
Прошито через `dd` с чтением обратно (sha256 совпал), до/после — `sync`.

Проверка на 64-битном тесте:

```
/dev/dma_heap/reserved: alloc fd=4 phys rc=0 pa=0xfe190000 size=65536 flags=3
/dev/dma_heap/system:   phys rc=-1 ENOTTY
```

### Shim: PA через ioctl, fallback остаётся

`vendor/vcodec/tools/ionshim.c`:

- при `GET_PHYS` сначала `DMA_HEAP_IOCTL_PHYS` на heap-fd, который выдал
  буфер (fd хранится per-handle); в лог пишется `cma-ioctl`;
- если ioctl недоступен (system heap / memfd / старое ядро) — прежний
  pagemap-fallback, затем PA=0;
- добавлен fallback `/dev/dma_heap/cma` → `/dev/dma_heap/reserved`
  (симлинк `cma` живёт только до перезагрузки).

### Vcodec: compat и `VCODEC_ALLOC_NON_CACHE_BUFFER`

- compat-whitelist: `0x22` ALLOC_NON_CACHE, `0x23` FREE_NON_CACHE,
  `0x27/0x28` INC/DEC_PWR_USER (трансляция 32-битного `VAL_POWER_T`),
  `0x17/0x18` EMI-счётчики, `0x13/0x14` SYSRAM, `0x31` GET_CORE_NUMBER,
  `0x35` SET_LOG_COUNT. Проверено `vcodec_compat32`: ни один не даёт
  `ENOTTY`; `0x17/0x18` возвращают 0xFF (как vendor) и декрементируют
  счётчик.
- `VCODEC_ALLOC_NON_CACHE_BUFFER` больше не пустой: драйвер выделяет
  `dma_alloc_coherent()` на VDEC-устройстве (32-битная DMA-маска, общая
  CMA-область), кладёт запись в `grNCMemoryList` (иначе `vcodec_mmap()`
  отвергает PA), отдаёт HAL'у `pvMemPa`, а `FREE` освобождает. Список
  `grNCMemoryList` теперь явно инициализируется `-1` — без этого
  `Add_NonCacheMemoryList()` не находил слот (vendor-баг).
- `vcodec_mmap()` принимает PA как offset (HAL зовёт `mmap64`).

Проверка `nc_test32` (32-бит bionic): `ioctl(0x22, size=64K)` → PA
`0xfe190000`, `mmap64(fd, offset=PA)` → VA, запись/чтение OK, `ioctl(0x23)`
освобождает. `VERDICT: PASS`.

`pa_probe32` (тот же allocator, что у HAL): три типа (SW, HW cacheable,
MCI) → `PA=0xfe19…`, запись по VA, `VERDICT: PASS`.

### HAL: Create/Init H.264 проходят

Прежний SIGSEGV в `eVDecDrvInit` был не платформенным: harness передавал
`eVDecDrvCreate(..., 0)` (codec format 0), HAL отвечал
`CodecFormat is not support => 0` и падал в error-path. С корректным
форматом (`0x40` H.264, `0x80`, `0x40000`) в `hal32`:

```
Create=0 handle=0x...   Init=1
ion-shim: GET_PHYS h=2..4 pa=0xfe18… cma-ioctl
```

То есть 32-битный vendor-HAL создаёт и инициализирует декодер через наш
`/dev/Vcodec` + ION-шим с реальными PA. Полный декод не запускался.

### 21.11 (2): 32-битный compat портирован и проверен

- `compat_alloc_user_space` в 6.12 нет, поэтому нативные обработчики
  переписаны на kernel-структуры (`vcodec_lockhw_kernel`,
  `vcodec_unlockhw_kernel`, `vcodec_waitisr_kernel`,
  `vcodec_set_frame_info_kernel`); user-обёртки и compat-слой делают
  `copy_from_user`/`copy_to_user` и трансляцию 32-битных `compat_uptr_t`.
- В `vcodec_unlocked_compat_ioctl` добавлены `VCODEC_LOCKHW` (0x0d),
  `VCODEC_UNLOCKHW` (0x33), `VCODEC_WAITISR` (0x0b),
  `VCODEC_SET_FRAME_INFO` (0x37).
- 32-битный тест `vcodec_compat2` (ELF32 ARM static, `H264_DEC=6`):
  `MFV_INIT`, `SET_PWR(1)`, `LOCKHW`, `SET_FRAME_INFO`, `UNLOCKHW`,
  `SET_PWR(0)`, `DEINIT` — 0; `WAITISR` без IRQ — `-1/errno=2`
  (ожидаемый таймаут). `ENOTTY` ни на одной из четырёх команд нет.
- IRQ 398 теперь у `Vcodec` (`mtk-vcodec-dec` отвязан); модуль загружен
  с `hw_power=1`, `vcodec_lockisr_test` PASS.

### Осталось

- Полный H.264 decode через 32-битный vendor HAL: `eVDecDrvDecode` или
  OMX-компонент `OMX.MTK.VIDEO.DECODER.AVC`; нужен реальный Annex B
  access unit и output-буферы.
- `/dev/MTK_SMI` и `mem_bw_ctrl` отсутствуют — HAL логирует ошибки
  профилей SMI/EMI, но продолжает.

p29: `build/boot_pa.img` (md5 `d7c12647…`); бэкап
`build/recovery/boot_a_heaps_2026-11-20.img` (`6bc3c35e…`); откат —
`build/scp/boot_vcodec2.img` (`bc48aedf…`) или бэкап.

### Артефакты и грабли перепаковки

- **DTB в p29 отличается от собранного из исходников.** В `mt6771*.dts`
  узлов `scp@10500000` и `video-codec@16020000` нет — они были добавлены в
  DTB через `fdtput` (20.11). При перепаковке `boot_pa.img` поэтому взят
  **DTB из текущего p29** (`build/recovery/dtb_p29_boot_heaps.fdt`,
  61 545 Б FDT), иначе SCP/VDEC-узлы исчезли бы. Ramdisk и DTB в новом
  образе побайтово равны прежним, отличается только `Image.gz`
  (15 600 280 → 15 600 603 Б). Это расхождение DTS↔DTB надо закрыть
  отдельным патчем.
- **32-битный chroot** (`/tmp/android32-chroot`, bionic + vendor libs с
  T800) живёт в tmpfs и пропадает при перезагрузке. Копия сохранена на
  плате: `/root/android32-chroot.tgz` (8.7 МБ, без `/proc`, `/sys`,
  `/dev`). Восстановление:
  `mkdir -p /tmp/android32-chroot && tar -C /tmp/android32-chroot -xzf
  /root/android32-chroot.tgz && mkdir -p /tmp/android32-chroot/{dev,proc,sys}
  && mount -t proc proc /tmp/android32-chroot/proc &&
  mount --bind /dev /tmp/android32-chroot/dev &&
  mount --bind /sys /tmp/android32-chroot/sys`.
  Шим и тесты пересобираются из `vendor/vcodec/tools/` на самой плате
  (`arm-linux-gnueabihf-gcc`, команды в шапках файлов).
