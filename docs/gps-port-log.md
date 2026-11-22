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

## T1100: config принят после холодной перезагрузки

Снятый с Android T1100 config отличается от варианта AYYA T1 в средней части
(`9d 00 6f 3c 88 89 a2 04 … dc 00 c1 00 … 5c 4a … 5c 4a … 4e 4f 5c 15`).
После замены `CONFIG` в `t1100-gps` на этот вариант и **холодной** перезагрузки
(свежий CONSYS) при активных Wi-Fi/BT получен ответ:

```
opened /dev/stpgps
sent config (116 bytes)
   0.001 frame id=0x31 len=14 31 fe 00 00 46 15 ... 98 01
frames: 1
```

`GPS_open: WMT turn on GPS OK!`, `STP speed rx:20 tx:493`. Значит транспорт и
протокол на T1100 рабочие; в помещении после `0x31` идут только keepalive.

Важно: config нужно отправлять **не сразу после open**, а с паузой ~2 с —
чип/WMT после power-on ещё не готов, и первый config теряется. После добавления
`time.sleep(2)` перед записью config ответ `0x31` стабильно появляется и при
тёплом запуске.
Следующий тест — на улице/у окна, с `t1100-gps --seconds 60 --raw`, и отдельно
LNA pinctrl (`get consys pinctrl fail`, pin -1).

Клиент: `rootfs-overlay/usr/local/sbin/t1100-gps`
(`--power-cycle`, `--seconds`, `--keepalive`, `--raw`).

## 21.11: assert-петля CONSYS и порядок запуска

При старте GPS одновременно с Wi-Fi (`23:31:00`) прошивка WMT ушла в
assert через 11 с (`read HOST_AWAKE_EVT fail`), затем whole chip reset
снял `wlan0`. Повторные `mnld`/`gps_hal_test` после этого открывали
`/dev/stpgps`, но NMEA не шло: chip coredump → host trigger FW assert
(`reason:2`) каждые ~6 с. После остановки GPS assert-ы прекратились.

Вывод: CONSYS нельзя поднимать одновременно с Wi-Fi; сервис GPS получил
`After=t1100-wifi.service` и `ExecStartPre=/bin/sleep 15`. После серии
assert-ов нужен холодный power-cycle (тёплый ребут CONSYS не выключает).

Дополнительно: `/dev/socket` живёт на devtmpfs и после ребута исчезает —
`t1100-fake-logd` создаёт его сам, `t1100-internal-gps` — после bind-mount
`/dev`; иначе `mnld` не стартует, а HAL остаётся без NMEA.

## 22.11: NMEA 21.11 дал raw-клиент, а не mnld

Проверка журнала boot -5 (20:04–23:30) по абсолютному времени:

- 21:17:51 `GPS_open` pid 4868 — это `t1100-gps`, запущенный руками
  (`/root/.bash_history`: `t1100-gps --power-cycle --seconds 120 --raw`).
  В 21:18:57 клиент закрыл порт (`WMT turn off GPS OK`) и открыл снова;
  повторный прогон (pid 4921) закрылся в 21:25:23, тоже `OK`.
- 21:25:26 сервис `t1100-internal-gps` (aa887c8) открыл GPS (pid 5320),
  но уже в 21:25:28 закрыл — сервис прожил 2 секунды и ни разу не был
  проверен на NMEA.
- 23:31 сервис на следующем буте открыл GPS, через 25 с mnld сделал
  assert (NMEA не пришла), `GPS_close: WMT turn off GPS fail!`, whole chip
  reset. С этого момента даже raw-клиент получает только `0x31`,
  NMEA нет; тёплые ребуты (23:46, 00:06, 00:40, 01:12) состояние не
  исправляют.

Вывод: рабочий путь — raw-клиент `t1100-gps` на «чистом» CONSYS; mnld/HAL
пока ни разу не дал NMEA. Первый шаг — настоящий холодный старт
(выключение с отключённым зарядом), затем raw-клиент **до** запуска
mnld/сервиса. Если NMEA пойдёт — делать штатный GPS на raw-клиенте,
а mnld оставить отдельной веткой для разбора.

## 22.11 (2): `gps_fw` — это log-канал, а не файл прошивки

Проверка стока через `debugfs` по `/root/aurora-root.img`:

- `/system/etc/firmware` в образе отсутствует; `/vendor/firmware`
  содержит `ROMv4_be_patch_1_0_hdr.bin` (229 384), `ROMv4_be_patch_1_1_hdr.bin`
  (314 120), `WIFI_RAM_CODE_6759`, `soc3_0_ram_mcu_1_1/1a_1/e1_hdr.bin`
  (все три побайтово одинаковы, md5 `979369a4…`), BT RAM code, FM-тюнинг
  и `Himax_firmware.bin`. Файла `gps_fw`/`*gps*fw*` нет.
- Строка `gps_fw` в стоковом `wmt_drv.ko` — элемент массива имён
  log-каналов (`common_main/debug_utility/connsys_debug_utility.c:115`):
  `"wifi_fw", "bt_fw", "gps_fw", "mcu_fw"`, а не имя firmware-файла.
- DSP-образ GPS лежит внутри `libmnl.so`: данные 28 кадров `0x0C` с
  T1100 совпадают с образом по файловому offset `0x1680fc` (vaddr
  `0x16a0fc`) до байта 346, дальше libmnl отдаёт на провод уже
  преобразованный вариант (escape/упаковка) — реплей шлёт именно его.

Вывод: гипотеза «в `/lib/firmware` не хватает `gps_fw`» закрыта.

## 22.11 (3): LNA, VCN28 и EMI проверены на железе

- GPIO155 (LNA): MODE-регистр `0x10005430` = `0x00880988`, поле pin155
  (биты 12..15) = 0 — **GPIO mode**; DIR/DO = 1 (output high). VCN28
  включён: `regulator_summary` — 1 consumer, 2800 mV. Ручной high
  действительно доходит до пада; pinctrl в DTS нужен для штатного
  управления, но это не блокер.
- `/dev/mem`: `0xbfc00000` (CONSYS EMI) содержит ROMv4-патч (3524 из
  4096 байт первого КБ ненулевые), `0xbfd00000` (GPS EMI) — нули.
- `CONSYS_PMIC_CTRL_ENABLE=1`, `consys_hw_vcn28_ctrl()` реально включает
  регулятор; `co_clock_flag=1` как в стоковом `WMT_SOC.cfg`.

## 22.11 (4): mnld-последовательность без 1 Гц `0x05` не ассертит

Реплей ровно той последовательности, что снята с mnld (config `0x08` →
28 чанков `0x0C` с ожиданием ACK → **один** кадр `0x05`), затем только
чтение 90 с:

```
records=30
sequence ok (0x31 + 28 acks), 0x05 sent once
done frames=0
```

`Host trigger FW assert` за прогон **нет**, Wi-Fi `.77` живой. Старый
`gps-replay.py`/`t1100-gps` слали `0x05` раз в секунду — это, вероятно,
и вызывало assert-петлю (`reason:2`), но NMEA не появляется и без неё.

## 22.11 (5): гипотеза — chip id для выбора DSP-образа

`mnld` содержит строки `persist.vendor.connsys.chipid` и
`combo_chip_id is %s`; в стоковом `/vendor/build.prop` значение `-1`
(его выставляет `wmt_launcher` после чтения chip id из ядра: `0x0788`).
В нашем bionic-chroot property-сервиса нет (`/dev/__properties__`
отсутствует), поэтому `property_get()` для этого ключа вернёт пусто.
Если mnld выбирает DSP-образ по этому id, он может взять generic-образ:
в захвате уходит образ из `libmnl.so` offset `0x1680fc`, у которого нет
имени MT6771 (именованные — `MT6771_DSP_0064_B183` / `C189`).

Проверка (следующая сессия): поднять property-сервис или подставить
`0x788` preload-ом; сравнить набор кадров `0x0C` с захватом. Пока не
проверено.

## 22.11 (6): полный pty-захват потока mnld; replay не даёт измерений

Метод: `tools/device/gps-capture.py` — pty-пара вместо FIFO. Причина:
один FIFO с `O_RDWR` с обеих сторон — общая очередь, стороны «воруют»
байты, поэтому прошлый дамп был неполным; вдобавок он парсился по полю
len, которое у `0x0C` всегда 1406 и не соответствует длине кадра.
`mnld` при этом пишет только при живом HAL-клиенте, поэтому нужны оба
флага: `--start-mnld --start-hal`.

Полный поток (`/root/gpscap-real2.mnld.bin`, 39 721 Б): config `0x08`
(seq 26) → 28 фрагментов `0x0C` (seq 1..28) → keepalive `0x05`
(seq 50). Ответ чипа (`.chip.bin`, 356 Б): `0x31` + 28 ACK `0x32`
(третье поле = seq + `0x136`).

Геометрия: граница кадра — только терминатор `AA 0F AA F0`; в проводе
байт-стаффинг `DE E0` → `DE`, `DE DF` → `AA`. Тело `0x0C` = запись
1400 Б из `libmnl.so` `.rodata` (file offset `1474812`, seq N →
`+ (N-1)*1400`) + хвост 2 Б (у seq 28 хвоста нет, 1394 Б). Хвост не
CRC: перебраны CRC16/суммы по 28 записям — не сходится ни одна
комбинация; для replay он не нужен, шлём точные байты.

Replay штатным клиентом (`t1100-gps --replay ...`, 45–120 с): 29
кадров, все `0x32`, измерений и NMEA нет, ассертов нет. Вывод: поток
mnld корректен (чип его принимает), но GPS-движок не выдаёт данных;
причина не в MNL-последовательности.

Драйвер: `t1100_trace=1` — трасса WRITE/READ; `GPS_compat_ioctl()`
сведён к вызову `GPS_unlocked_ioctl()`; ioctl 6 (`COMBO_IOC_GPS_HWVER`)
включён, но `chip_detector` ходит не в устройство, а в свойство
`persist.vendor.connsys.chipid` (в dmesg нет ни одного `GPS_ioctl`).
`vendor.service.nvram_init` в Ubuntu отсутствует → `mtk_gps_sys_init
err = 2`, но старт продолжается. Оба свойства — кандидаты на шим.

## 22.11 (7): property-шим, EMI, efuse — блокер не найден

- `tools/device/t1100-propfix.c` (ARM32, `-nostdlib`) подменяет
  `__system_property_get`: `persist.vendor.connsys.chipid=0x0788`,
  `vendor.service.nvram_init=Ready`. mnld: `combo_chip_id is 0x0788`,
  `nvram_init_val Ready`, `GPS NVRam gps_nvram_fd == NULL`. Поток
  mnld→чип с шимом побайтово тот же (sha256 `d83b6e09…`), чип — только
  `0x31` + 28 ACK. Выбор DSP-образа от chipid не зависит.
- `gps_emi_read()` не выставлял `ret` → `dd` отдавал 0 байт. Исправлено.
  Прочитаны оба MiB CONNSYS: `0xbfc00000` — coredump/лог (56 704
  ненулевых), `0xbfd00000` — нули; сигнатуры DSP-образа нет. Значит
  образ уходит по STP внутрь combo-чипа, SoC EMI — ложный след.
- ioctl 9 (`COMBO_IOC_D1_EFUSE_GET`) реализован для MT6771
  (`ioremap(0x11f10048)`); mnld его вызывает сразу после `GPS_open`.
  На старт DSP не влияет.
- `tools/device/mnl-probe.py`: keepalive и неизвестный тип `0x99` —
  молчание, config — ровно один `0x31`. Ответы адресные, не canned.
- WMT GPS on в исходниках: только GPS_SYNC и LNA, `gps_mcu_ctrl` в
  power-on нет. VCN28 подан (2800 мВ). ROM-patch и MCU-патч (166
  фрагментов) в порядке, чип определяется как `SOC_CONSYS.E1`.
- Статический RE libmnl через `arm-linux-gnueabihf-objdump` упирается в
  PIC-адресацию (нет литеральных ссылок на строки); нужен radare2/Ghidra.
