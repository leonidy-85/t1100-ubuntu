# Vcodec / V4L2 tools

Вспомогательные инструменты для проверки vendor-стека и V4L2 на T1100.
Собираются отдельно от модуля; в репозитории только исходники.

## `ionshim.c`

32-битный bionic `LD_PRELOAD`-шим, эмулирующий `/dev/ion` поверх `memfd`.
Перехватывает `open`/`__open_2` для `/dev/ion` и `ioctl` только на своих fd;
реализует `ION_IOC_ALLOC`, `ION_IOC_FREE`, `ION_IOC_MAP`, `ION_IOC_SHARE`,
`ION_IOC_CUSTOM` (включая probe с handle 0 и `ion_set_client_name`).
Проверено: `ion_alloc_mm` / `ion_alloc_camera` / `ion_alloc_syscontig`,
share, mmap, free.

Ограничение: буферы CPU-only, без физической непрерывности и без экспорта
dma-buf в устройства. Для реального декодера нужен CMA/dma-heap.

Сборка (32-бит, bionic chroot):

```sh
arm-linux-gnueabihf-gcc -marm -shared -fPIC -nostdlib \
  -Wl,--allow-shlib-undefined -o <chroot>/vendor/lib/libionshim.so ionshim.c
```

Запуск:

```sh
chroot <chroot> /system/bin/sh -c \
  "LD_PRELOAD=/vendor/lib/libionshim.so /vendor/bin/ion_test32"
```

## `ion_test.c`

32-битный тест, который дергает `libion_mtk`/`libion` так же, как decoder HAL:
`mt_ion_open`, `ion_alloc_mm`, `ion_alloc_camera`, `ion_alloc_syscontig`,
`ion_share`, `mmap`, `ion_free`, `mt_ion_close`. Точная cross-link-команда —
в заголовке файла.

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

Ожидается fd от `EXPBUF` и запись `vb2` в `bufinfo`. Тест подготовлен, но
на устройстве ещё не прогонялся (планшет ушёл в reboot и не вернулся).
