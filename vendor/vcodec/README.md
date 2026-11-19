# Vendor AP-side Vcodec driver (MT6771)

Порт vendor-драйвера `/dev/Vcodec` с Android-дерева OPPO MT6771 на mainline
6.12.114. Это **инфраструктурный** драйвер: он создаёт character device,
отображает регистры VDEC в user space и обслуживает ioctl для питания,
клоков, ISR, блокировок и DVFS. Сами алгоритмы H.264/HEVC/VP9 в нём
отсутствуют — на T800 их реализует 32-битная `libvcodecdrv.so`.

## Откуда

- Репозиторий: `oppo-source/android_kernel_oppo_mt6771`
- Ветка: `oppo/mt6771_r_11`
- Путь: `drivers/misc/mediatek/videocodec/mt6771/`
- Лицензия исходников: GPL-2.0 (см. заголовки файлов и `LICENSE` в корне репозитория).

## Что внутри

- `mt6771/videocodec_kernel_driver.c` — основной драйвер (порт).
- `mt6771/videocodec_kernel_driver.h` — ioctl ABI (magic `'M'`, команды
  `MFV_*`, `VCODEC_*`).
- `mt6771/Makefile` — сборка модуля `vcodec_kernel_driver.ko`.
- `include/` — заголовки VAL/HAL, нужные драйверу.
- `compat/` — stubs для MTK 4.14 API, которых нет в mainline:
  `smi_public.h`, `mmdvfs_pmqos.h`, `mt-plat/dma.h`, `mach/mt_clkmgr.h` и др.
- `Makefile.live` — сборка тестового модуля `vcodec_port.ko` (driver
  `VcodecPort`), чтобы не занимать production-имя и major 160.
- `PORT-NOTES.md` — журнал порта, ошибки сборки и решения.
- `PORT-DIFF.txt` — полный diff относительно vendor-исходника.
- `vcodec_test.c`, `vcodec_lock_test.c` — smoke-тесты ioctl.

## Сборка

На планшете (kernel tree и gcc уже есть):

```sh
make -C /root/kbuild/linux-6.12.114 M=$PWD \
     KBUILD_MODPOST_WARN=1 modules -j8
```

`KBUILD_MODPOST_WARN=1` нужен потому, что в дереве нет `Module.symvers` /
`vmlinux`; символы разрешаются при `insmod` (`CONFIG_MODVERSIONS` выключен).

## Загрузка и проверка

```sh
insmod /root/vcodec-port/vcodec_kernel_driver.ko
ls -l /dev/Vcodec /dev/Vcodec2
grep -i vcodec /proc/devices          # ожидается major 160
/root/vcodec-port/tests/vcodec_verify
dmesg | grep -E "Oops|WARNING|BUG|Call trace"
```

Ожидаемо: `probe ... returned 0`, `/dev/Vcodec` major 160, классы
`Vcodec`/`Vcodec2`, `/dev/video0` и `/dev/media0` (mainline
`mtk-vcodec-dec`) не затронуты.

## Инструменты

- `tools/ionshim.c` — 32-битный bionic `LD_PRELOAD`-шим `/dev/ion` поверх
  `memfd`; проверены alloc/free/map/share/custom.
- `tools/ion_test.c` — тест `libion_mtk`/`libion` как в decoder HAL.
- `tools/v4l2_expbuf.c` — тест `VIDIOC_EXPBUF` на `/dev/video0`.

Подробности и команды сборки — `tools/README.md`.

## Ограничения

- IRQ VDEC 250 сейчас занят `mtk-vcodec-dec` без `IRQF_SHARED`; драйвер
  логирует это и продолжает без ISR. Для реального HAL нужно либо снять
  `mtk-vcodec-dec` с узла, либо сделать IRQ shared.
- VENC-узел в live DT отсутствует; VENC пока не проверялся.
- Драйвер не выделяет память под декодирование: `MFV_ALLOC_MEM_CMD` и
  `VCODEC_ALLOC_NON_CACHE_BUFFER` — no-op. HAL использует `/dev/ion`
  (`libion_mtk`); в mainline нужен ION/DMA-BUF shim.
- 32-битный bionic-рантайм на T1100 проверен отдельно; сам HAL ещё не
  запускался без `/dev/Vcodec` и `/dev/ion`.

## Статус

- Порт собирается под `6.12.114-wifi1`, модуль загружается, `/dev/Vcodec`
  создаётся; ioctl `INIT`/`SET_PWR`/`INITHWLOCK`/`LOCKHW`/`INC_PWR_USER`
  возвращают 0.
- Production-модуль с исправленным ABI (`success = 0`) подготовлен на
  планшете; после physical power-cycle нужно проверить major 160.
- Планшет был перезагружен и не вернулся в Wi-Fi; нужен физический цикл
  питания. Прошивка/p29 не менялись.
