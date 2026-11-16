# GPS: разбор вендорского userspace MTK GNSS (mnld / libmnl)

Дата: 16.11.2026. Статус: драйвер в ядре работает, последний барьер — формат
кадров, которые вендорский демон пишет в `/dev/stpgps`.

## Что уже работает

- `gps/gps_drv.ko` (порт из `Winkmoon/android_kernel_xinran_oppo_mt6771`,
  `connectivity/gps_drv`) — `build/gps/gps_drv.ko`, sha256 `eba78916…`.
- `/dev/stpgps` (191:0), `open()` поднимает домен GPS:
  `GPS_open: WMT turn on GPS OK!`, `OPID(3) type(2) ok`. MCU-ассерта нет
  (в отличие от FM).
- Транспорт STP (type 2) принимает `write()` без ошибок.

## Чего не хватает

Чип не отвечает ни на один вариант «человеческого» протокола:

| отправлено | ответ |
|---|---|
| `$PMTK000*32`, `$PMTK605*31` | 0 байт |
| `$PMTK314,…` (GGA/RMC), `$PMTK220,1000` | 0 байт |
| `$PMTK898 1`, `$PMTK010,001` (без CRC) | 0 байт |
| 4-байтный LE-префикс длины + PMTK | 0 байт |

Значит одной отправки PMTK-строк недостаточно: нужен handshake/формат,
который формирует вендорский userspace.

## Архитектура вендорского userspace (Aurora `T800`, 192.168.2.76)

- `/vendor/bin/mnld` (234 404 Б, ELF32 ARM, Thumb, stripped) — демон, который
  единственный открывает `/dev/stpgps` и пишет в него.
- `/vendor/bin/mtk_agpsd` — AGPS (сеть, EPO, NTP), общается с `mnld` сокетами.
- `/vendor/lib64/hw/gps.default.so` (60 776 Б) — Android GNSS HAL; сам в
  `/dev/stpgps` не пишет, только `sendto`/`recvfrom` к `mnld`.
- `/vendor/lib/libmnl.so` (4 472 564 Б) — MTK Navigation Library: вся логика
  GNSS, PMTK-строки и парсинг; получает колбэки I/O от `mnld`.
- `/vendor/etc/init/hw/init.connectivity.rc`: `service mnld /vendor/bin/mnld`,
  `user gps`, `socket mnld stream 660 gps system`.

## Что найдено в `mnld`

- Строка `/dev/stpgps` — `.data` vaddr `0x38aa4`.
- `open_port` (`fcn.00028900`): `__open_2(path, O_RDWR)` в `0x28e9c`, fd
  сохраняется в глобал; при ошибке ретраи (до 22) с логами
  `open_port: Unable to open - %s`, `open dsp successfully(fd:%d)`.
- `write_all` = `fcn.00019ce6` (144 Б): `__write_chk(fd, buf, len, -1)`,
  повтор при `EINTR`, лог ошибки. Прямых вызовов нет — регистрируется как
  колбэк.
- Единственный вызов `mtk_gps_sys_function_register` — `0x261d2`
  (стаб `0x35720`); перед ним в `r0` кладётся указатель, вычисленный через
  литерал (требует дальнейшего разбора — структура колбэков).
- Импорты из `libmnl.so`: `mtk_gps_mnl_run/stop`,
  `mtk_gps_sys_function_register`, `mtk_gps_set_param`,
  `mtk_gps_get_MNL_Config_XML_param`, `mtk_gnss_get_measurement/clock/…`.

## Что найдено в `libmnl.so`

- Готовые PMTK-строки: `$PMTK010,001/002/003` (статусы),
  `$PMTK500,%d,%d,%d,%.1f,%.1f` (AGPS-время), `$PMTK514,…` (19 полей конфига),
  `$PMTK817`, `$PMTK898 0/1`, ответы `$PMTK001,…`.
- Строк `/dev/...` и файлового I/O нет — только сокеты, NVRAM, парсинг.
- Вывод: текстовые PMTK формирует `libmnl.so`, а передаёт их в устройство
  через колбэк `mnld` (`write_all`).

## Гипотезы, почему raw-PMTK молчит

1. Между `libmnl` и устройством есть обёртка (заголовок кадра: тип/длина/CRC),
   которую пока не восстановили.
2. Перед PMTK нужен бинарный handshake (инициализация GNSS-ядра), который
   `libmnl` шлёт при `mtk_gps_mnl_run`.
3. Наш `gps_drv` не включает какой-то режим STP для GPS (ср. bluez-режим BT,
   где пакеты идут не в rx-очередь, а в `if_rx`).

## Следующие шаги

1. Доразобрать `mnld` в районе `0x261bc–0x26240`: структура колбэков,
   которую получает `mtk_gps_sys_function_register` (ожидается пара
   `write_all` + read).
2. Найти в `libmnl.so` функцию, которая собирает PMTK и вызывает колбэк:
   проверить, добавляется ли заголовок кадра.
3. Если формат подтвердится — реализовать минимальный userspace-клиент
   `t1100-gps` (пишет handshake + PMTK в `/dev/stpgps`, читает NMEA/PMTK).
4. Резервный путь: перенести на планшет `mnld` + `libmnl.so` + bionic-линкер
   (грязно, но может сразу дать фиксы).

## Ограничения, с которыми столкнулись

- На Aurora `ro.debuggable=0` → init игнорирует `wrap.mnld`, LD_PRELOAD не
  применяется; SELinux в enforcing, `ptrace` под su-доменом недоступен;
  `strace`/`gdb` отсутствуют.
- Поэтому единственный путь — статический реверс (capstone/r2), он и ведётся.
