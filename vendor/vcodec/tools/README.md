# Vcodec / V4L2 tools

Вспомогательные инструменты для проверки vendor-стека и V4L2 на T1100.
Собираются отдельно от модуля; в репозитории только исходники.

## `ionshim.c`

32-битный bionic `LD_PRELOAD`-шим, эмулирующий `/dev/ion` для вендорного
32-битного HAL. Перехватывает `open`/`__open_2` для `/dev/ion` и `ioctl`
только на своих fd.

Бэкенды по порядку:

1. `/dev/dma_heap/cma` — физически непрерывный dma-buf (нужен
   `CONFIG_DMABUF_HEAPS` + `CONFIG_DMABUF_HEAPS_CMA`);
2. `/dev/dma_heap/system` — dma-buf, обычно не непрерывный;
3. `memfd` — прежний CPU-only fallback.

Реализованы `ION_IOC_ALLOC` (транслируется в `DMA_HEAP_IOCTL_ALLOC`
`0xc0184800`), `ION_IOC_FREE` (handle 0 — probe legacy-хеапов, отвечает 0),
`ION_IOC_MAP`, `ION_IOC_SHARE`, `ION_IOC_CUSTOM` (`cmd=0`: `sys_cmd=4`
set client name, `sys_cmd=1` GET_PHYS; `cmd=1`: mm config — no-op).

Физический адрес: dma-buf маппится, по `/proc/self/pagemap` берутся PFN
(нужен `CAP_SYS_ADMIN`), проверяется последовательность страниц, PA =
`first_pfn << 12`. Если страницы не непрерывны (system heap / memfd), PA
возвращается как 0, а не как адрес первой страницы — иначе железо читало бы
мусор. Ограничение: выравнивание выше 4 КиБ не поддерживается (пишется
предупреждение в stderr); наблюдаемый запрос HAL — 0x1000.

Сборка (32-бит, bionic chroot):

```sh
arm-linux-gnueabihf-gcc -marm -O2 -shared -fPIC -nostdlib -nostartfiles \
  -Wl,-soname,libionshim.so -Wl,--allow-shlib-undefined \
  -o <chroot>/vendor/lib/libionshim.so ionshim.c
```

Запуск:

```sh
chroot <chroot> /system/bin/sh -c \
  "LD_PRELOAD=/vendor/lib/libionshim.so /vendor/bin/ion_test32"
```

Проверено: memfd-бэкенд (alloc/share/mmap/free, `eVDecDrvCreate/Init`) и
dma-heap-бэкенд на kernel 6.12.114-wifi1 с `CONFIG_DMABUF_HEAPS`:
`/dev/dma_heap/cma` работает, `ion_test32` проходит, буфер пишется/читается.

**PA через pagemap не работает**: dma-buf маппится как `VM_PFNMAP`
(`/dmabuf:` `rw-s`), и `/proc/self/pagemap` отдаёт для него полностью нулевую
запись (бит present = 0), тогда как анонимные страницы в том же процессе
показывают PFN. Воспроизведено для heaps cma и system, из 32-битного bionic и
64-битного процесса. Поэтому `GET_PHYS` логирует `pagemap-unavailable`, а PA
остаётся 0. Нужен kernel-side источник PA (например ioctl дамап-хеапа,
возвращающий первый адрес sg_table) — точка вставки в `do_custom()`.

## `ion_test.c`

32-битный тест, который дергает `libion_mtk`/`libion` так же, как decoder HAL:
`mt_ion_open`, `ion_alloc_mm`, `ion_alloc_camera`, `ion_alloc_syscontig`,
`ion_share`, `mmap`, `ion_free`, `mt_ion_close`. Точная cross-link-команда —
в заголовке файла.

## `pa_probe.c`

32-битный тест, доказывающий, что вендорный HAL получает настоящий
физический адрес. Зовёт `eVideoMemAlloc` из `libvcodec_utility.so` (тот же
аллокатор, что импортирует `libvcodecdrv.so`) с `VAL_MEMORY_T` (96 байт,
64-битные union'ы: VA +16, PA +24), пишет по VA и печатает вердикт:

```
VERDICT: PASS (VA writable, PA != 0)
VERDICT: FAIL (PA==0 or not writable; memfd/non-contiguous backend)
```

С `/dev/dma_heap/cma` ожидается `PASS`; на memfd-бэкенде — `FAIL` с `PA=0`
(это и есть зафиксированный до dma-heap дефект).

## OMX-путь (`omx_probe.c`, `omx_decode2.c`, `logshim.c`)

32-битный bionic OMX-харнесс для вендорного компонента
`OMX.MTK.VIDEO.DECODER.AVC` (`libMtkOmxCore.so` + `libMtkOmxVdecEx.so`,
ядро OMX читает `/vendor/etc/mtk_omx_core.cfg`, он тоже нужен в chroot).

- `omx_probe.c` — `Mtk_OMX_Init`, `Mtk_OMX_ComponentNameEnum`, `GetHandle`,
  опрос портов. Важно: MTK-компонент принимает только **OMX 1.0.0.0**
  (`nVersion.nVersion = 1`, не 1.1.2) и `nSize = 96` для
  `OMX_PARAM_PORTDEFINITIONTYPE`, иначе `OMX_ErrorBadParameter`.
- `omx_decode2.c` — полный цикл: NV12 320x240, буферы, Idle/Executing,
  `EmptyThisBuffer` + `FillThisBuffer`, обработка `PortSettingsChanged`
  (disable/free/realloc/enable) и повторная отправка AU.
- `logshim.c` — `LD_PRELOAD`, уводит `__android_log_print` в stderr (в chroot
  нет logd); без него ошибки вендорного кода не видны.

Запуск:

```sh
chroot $C /system/bin/sh -c   "LD_PRELOAD=\"/vendor/lib/libionshim.so /vendor/lib/liblogshim.so\" /vendor/bin/omx_decode2_32"
```

Состояние: OMX доходит до `InitHW OK` (SPS разобран, разрешение верное),
`OMX_EventPortSettingsChanged`, реконфигурация порта проходит; буферы
получают реальные PA/MVA. Далее вендорный парсер выдаёт
`[Err] Fail to parse Slice header data structure!!` на любом валидном
потоке (x264 baseline CAVLC 176x144/320x240, High 640x640 с Aurora,
Annex B с AUD/SEI/без, CSD отдельным буфером) — кадр не выдаётся.
IRQ VDEC (398) при этом ни разу не срабатывает.

## `v4l2_expbuf.c`

Тест `VIDIOC_EXPBUF` на `/dev/video0` (`mtk-vcodec-dec`): проверяет, что
vb2-dma-contig отдаёт dma-buf fd без ION и без правок ядра.

Сборка и запуск на T1100:

```sh
gcc -O2 -o /tmp/v4l2_expbuf v4l2_expbuf.c
/tmp/v4l2_expbuf &
sleep 3
cat /sys/kernel/debug/dma_buf/bufinfo | head -30
```

Ожидается fd от `EXPBUF` и запись `vb2` в `bufinfo`. На устройстве не
прогонялся: после возврата платы декодер был переведён на vendor-путь.
