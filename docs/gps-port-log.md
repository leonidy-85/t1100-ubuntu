# GPS (GNSS MT6631) — порт вендорского драйвера

Драйвер GNSS живёт в CONSYS (MT6631), отдельной прошивки не грузит: ядро GNSS
в ROM, обмен идёт по STP-каналу `GPS_TASK_INDX = 2`, а питанием домена управляет
`mtk_wcn_wmt_func_on(WMTDRV_TYPE_GPS)`.

## Источник

`drivers/misc/mediatek/connectivity/gps_drv` из публичного дерева
`Winkmoon/android_kernel_xinran_oppo_mt6771` (ветка `android11`), 5 файлов:
`stp_chrdev_gps.c`, `fw_log_gps.c`, `gps_emi.c`, `gps.h`, `Makefile`.

## Что сделано для 6.12

- `gps/` в репозитории, out-of-tree `gps/Makefile` (`gps_drv-objs :=
  stp_chrdev_gps.o fw_log_gps.o`), `scripts/build-gps-remote.sh` собирает против
  `out-wifi` с `KBUILD_EXTRA_SYMBOLS=work/common/Module.symvers`.
- `gps/compat/` — минимальные `osal_typedef.h`, `stp_exp.h` (плюс `GPS_TASK_INDX`,
  `MTKSTP_BUFFER_SIZE`, прототип `mtk_wcn_stp_is_ready`), `wmt_exp.h`,
  `osal.h`, `wmt_core.h`, `wmt_dev.h`, `mtk_wcn_consys_hw.h` (заглушка
  `mtk_wmt_get_gps_lna_pin_num() = -1`), `connectivity_build_in_adapter.h`.
- Вендорские подсистемы не нужны: clkbuf/freqhopping/dvfsrc/LNA включаются только
  для других SoC, `gps_emi.c` целиком под `CONFIG_MTK_GPS_EMI` (исключён из сборки),
  `GPS_FWCTL_SUPPORT`/`GPS_HW_SUSPEND_SUPPORT` для MT6771 не активны.
- Правки API 6.12: `class_create(name)` (два вызова).

## Артефакт

`build/gps/gps_drv.ko` — 23 840 Б, sha256
`eba789167db84c5f8ba9b3d4f3c574c413989f85e4c0b456103c59acc6137564`,
`vermagic 6.12.114-wifi1`, зависит от `wmt_drv`.

## Проверка на планшете

- `modprobe gps_drv` → `mtk_stp_GPS_chrdev driver(major 191) installed`,
  `/dev/stpgps` (191:0), `gps_mod_init returned 0`.
- `open("/dev/stpgps")` → `GPS_open: WMT turn on GPS OK!`, `OPID(3) type(2) ok`,
  `gps_hold_wake_lock(1)`. Никакого MCU-assert (в отличие от FM).
- За 8 секунд чтения — 0 байт; `STP speed rx:0 tx:0`. Закрытие:
  `GPS_close: WMT turn off GPS OK!`.

## Блокер

Драйвер только транспортирует байты: ioctl-поверхность — служебная
(`COMBO_IOC_GPS_HWVER/IC_FW_VERSION/CO_CLOCK_FLAG/TAKE_GPS_WAKELOCK/...`),
команды инициализации GNSS в неё не входят. Поток данных начинается только после
того, как userspace запишет в `/dev/stpgps` бинарные MTK-команды (init/rate),
как это делает Android HAL `libgps`/`gps.default.so`.

Следующий шаг: реверс минимальной init-последовательности из HAL с Aurora
(`/vendor/lib64/libgps.so`, `/vendor/lib64/hw/gps.default.so`) либо поиск
открытого клиента MTK GNSS; затем проверить NMEA/бинарные фиксы и реальный приём
(антенна на T1100 есть — подтверждено на Android и Aurora).

## Откат

Не грузить `gps_drv` (или `rmmod gps_drv`); на Wi-Fi/BT это не влияет.

## Протокол MNL: снят с вендорского `mnld` (AYYA T1)

Формат кадра: `aa f0` + длина LE16 + payload + `aa 0f`.

| id | направление | смысл |
|---|---|---|
| `0x08` | host → чип | config (110 Б, `08 fe 1a 00 … 4e 4f 7b 15`) |
| `0x05` | host → чип | keepalive (`05 fe 04 00 0d 01`) |
| `0x0c` | host → чип | assistance/EPO (1406 Б), для базового фикса не нужен |
| `0x31` | чип → host | статус/версия (`31 fe 00 00 46 15 … 98 01`) |
| `0x32` | чип → host | ack с seq (`32 fe <seq16> <u16>`) |

Как получено: на AYYA T1 (Aurora 11, 192.168.2.113) root через `devel-su`,
затем `setprop ctl.stop mnld` → `mv /dev/stpgps /dev/stpgps_real` →
`mkfifo /dev/stpgps` → `cat` в файл → `setprop ctl.start mnld`. Релей на
shell (`tee` в обе стороны) дал и запросы, и ответы чипа.

На T1100: `gps_drv` + `/dev/stpgps`; при свежем включении домена
(`t1100-gps --power-cycle`) чип **немедленно отвечает `0x31`** на config —
значит протокол принят. Дальше идут keepalive; поток измерений в помещении
не появляется (нужен обзор неба) — это следующий тест.

Клиент: `rootfs-overlay/usr/local/sbin/t1100-gps`
(`--power-cycle`, `--seconds`, `--keepalive`, `--raw`).
