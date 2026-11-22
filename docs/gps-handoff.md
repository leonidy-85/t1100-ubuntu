# GPS MT6771 (Fplus T1100) — передача в новую сессию

Дата: 22.11.2026 (ред. 2, после полного pty-захвата потока `mnld`).
Читать вместе с `docs/STATUS.md` и `docs/gps-port-log.md`.

## Цель

Внутренний GPS планшета T1100 (MT6771/MT8788, MT6631) на ALT/Ubuntu:
NMEA/фиксы в Satellite. Wi-Fi `192.168.2.77` не ломать. Внешний
Android-бридж (`t1100-nmea-adb`) не использовать.

## Итог одной строкой

**GPS работает.** Корневая причина многодневной тишины — неверное
значение Android-свойства `persist.vendor.connsys.chipid`: шим отдавал
`0x0788` (значение с другой платформы), `libmnl.so` выбирала по нему
generic DSP-образ (28 фрагментов), и GNSS-ядро не стартовало. С
`0x6771` (= MT6771) выбирается родной образ (сотни фрагментов), чип
начинает отдавать измерения, `mnld` — NMEA. Проверено на штатном
сервисе `t1100-internal-gps`: **111 NMEA-строк за 10 с**, включая
`$GPGSV` с 12 спутниками.

## Решение (22.11, вечер)

1. На втором T1100 с рабочим Android 11 (эталон, root adb
   `192.168.2.100:41147`) сняты свойства: `persist.vendor.connsys.chipid
   = 0x6771`, `vendor.gps.gps.version = 0x6771`, `ro.board.platform =
   mt6771`. Наш шим отдавал `0x0788`.
2. `tools/device/t1100-propfix.c` исправлен на `0x6771`, пересобран
   `libpropfix.so` (67 184 Б) и положен в
   `/opt/bionic/vendor/lib/libpropfix.so`.
3. `rootfs-overlay/usr/local/sbin/t1100-internal-gps` теперь выставляет
   `LD_PRELOAD=/vendor/lib/libpropfix.so` **внутри** chroot-шелла, перед
   `exec /system/bin/mnld` (раньше сервис запускал mnld без шима — то
   есть штатный путь до сих пор шёл с пустым свойством).
4. Проверка: `combo_chip_id is 0x6771` в logd, поток mnld→чип
   1533 кадра / 106 824 Б, ответ чипа 677 кадров / 38 252 Б (статус
   `0xFE31`, ACK `0xFE32` и содержательные `0xFE30/0xFE37/0xFE4E/
   0xFE14/0xFE42`), в logd `$GNGGA,142207.01...` раз в секунду.
   Чтение `/run/t1100-nmea.sock`: 111 строк за 10 с, `$GPGSV` — 12
   спутников.

Важно: efuse/ioctl 9 ни при чём — на рабочем эталоне тоже
`Read Efuse not supported in this platform`. NMEA формирует сам
DSP/чип (mnld её только парсит), поэтому ждать `$` из `/dev/stpgps`
без запущенного DSP бессмысленно.

## Что работает и проверено

- Wi-Fi: `wlan0 192.168.2.77/24`, `t1100_no_fw_own=0`,
  `t1100_pwr_on_done=1`; после whole-chip reset watchdog поднимает
  `.77` сам за ~10 с.
- GPS-функция: `GPS_open: WMT turn on GPS OK!`; устройства
  `/dev/stpgps` (191:0), `/dev/stpwmt`, `/dev/gps_emi`,
  `/dev/fw_log_gps`.
- `gps_emi`: `gConEmiPhyBase=0xbfc00000`, GPS-база `0xbfd00000`
  (`+SZ_1M`); `thread_adc_capture_init: ADC emi address:(0xbfd00000)`.
- **Полный поток mnld снят** pty-релеем (см. инструменты):
  `/root/gpscap-real2.mnld.bin`, 39 721 Б, ровно 30 кадров:
  config `0x08` (seq 26, payload 110) → 28 фрагментов `0x0C`
  (seq 1..28) → keepalive `0x05` (seq 50, payload 9).
  Ответ чипа (`gpscap-real2.chip.bin`, 356 Б): `0x31` (len 14) +
  28 ACK `0x32` (len 6); третье поле ACK = seq + `0x136`.
- `0x0C` — **фрагменты DSP-образа** GNSS (не EPO/assistance): тело
  каждого = запись 1400 Б из `libmnl.so` `.rodata`, файловый offset
  `1474812` (`0x1680fc`, vaddr `0x16a0fc`), seq N → offset
  `1474812 + (N-1)*1400`; seq 28 — 1394 Б, итого 39 194 Б.
- **Геометрия кадров**: `AA F0` + len LE16 + payload + `AA 0F`.
  Поле len у `0x0C` всегда 1406 и **не равно** длине кадра
  (1407–1421 Б): настоящая граница — терминатор `AA 0F`, за которым
  сразу идёт `AA F0`. Байт-стаффинг в проводе: `DE E0` → `DE`,
  `DE DF` → `AA`. Поэтому поток mnld надо слать **verbatim**, а не
  собирать из полей длины.
- Replay точным потоком — штатным клиентом
  `t1100-gps --replay /root/gpscap-real2.mnld.bin`: 29 кадров, все
  `0x32`, за 45–120 с **0 измерений**, NMEA нет, ассертов нет.
- Драйвер: module_param `t1100_trace=1` — трасса `WRITE`/`READ`
  (первые 16 Б) в dmesg; `GPS_compat_ioctl()` сведён к вызову
  `GPS_unlocked_ioctl()` (убраны безусловные `pr_warn`).
- ioctl на `/dev/stpgps`: 6 (HWVER) → `0x0` (WMTHWVER_E1),
  7/8 (IC HW/FW version) → `0x8a00`, 16 (GPS_LNA_PIN) →
  `0xffffffff`.

## Что исключено (не тратить время)

- `gps_fw` — имя log-канала coredump
  (`connsys_debug_utility.c`), не файл прошивки; в `/vendor/firmware`
  его нет. Гипотеза закрыта.
- `mtkgps.dat`/`cache.dat`/`EPO.DAT` — не источник `0x0C`.
- `nvdata` (p6) / `nvcfg` (p5): калибровки найдены, монтирование в
  chroot не помогло.
- `WMT_SOC.cfg` совпадает со стоком (`co_clock_flag=0`,
  `wmt_gps_lna_enable=0`, `wmt_gps_lna_pin=0`).
- AFE (`CONSYS_AFE_REG_SETTING=1`, `GPS_02=0x110A2000`) и EMI MPU
  region 30 (настраивает LK) — в порядке.
- ROM-patch путь (`t1100_emi_rom_patch`, `srh_rom_patch`) относится к
  Wi-Fi/BT combo, не к GPS.
- Ручной GPIO155 high + включённый VCN28 (2800 мВ) — измерений нет;
  LNA влияет на сигнал, но не на факт запуска движка.
- ioctl 6 (`COMBO_IOC_GPS_HWVER`) включён — `chip_detector` им не
  пользуется (в dmesg нет ни одного `GPS_ioctl`), значение не влияет.

## Дефекты окружения (известны; кандидаты, не доказанные блокеры)

1. `vendor.service.nvram_init` — Android-свойство, которого в Ubuntu
   нет (`/dev/__properties__` отсутствует). `mnld` ждёт 10 с, затем
   `mtk_gps_sys_init err = 2`, но продолжает старт. В стоке свойство
   выставляет nvram-сервис (`/vendor/etc/init/hw/*nvram*rc`).
2. `persist.vendor.connsys.chipid` — **главный блокер, закрыт**. В стоке
   значение `0x6771` (MT6771). Шим должен отдавать именно его; с чужим
   `0x0788` libmnl выбирает generic DSP-образ, и чип молчит.
3. DTS: у узла `consys@18070000` нет `pinctrl-*`; wmt логирует
   `get consys pinctrl fail` и `GPS LNA pin number(-1)`, ioctl 16
   отдаёт `0xffffffff`. В стоковом dtbo есть `gpslna@0/1/2`
   (GPIO155, `pinmux=0x9b00`) и `pinctrl-names = "default",
   "gps_lna_state_init", "gps_lna_state_oh", "gps_lna_state_ol"`.
4. В pty-захвате ioctl STP дают `ENOTTY` (`errno=25`) — артефакт tty,
   на реальном узле их нет.

## 22.11 (4): вечерние эксперименты — что проверено после передачи

- **Android-свойства подделаны шимом.** `tools/device/t1100-propfix.c`
  собирается ARM32 (`arm-linux-gnueabihf-gcc -shared -fPIC -nostdlib`) в
  `libpropfix.so` и кладётся в `/opt/bionic/vendor/lib/`; `LD_PRELOAD`
  задаётся **внутри** chroot-шелла (иначе x86-chroot грузит ARM-библиотеку).
  Шим отвечает `persist.vendor.connsys.chipid=0x0788`,
  `vendor.service.nvram_init=Ready`, `ro.property_service.version=2` и
  логирует все запросы в `/data/vendor/gps/propfix.log`.
  Результат: `combo_chip_id is 0x0788`, `nvram_init_val Ready`,
  `GPS NVRam gps_nvram_fd == NULL` (файл не открылся — не блокер).
- **Выбор DSP-образа зависит от chipid — это и был блокер.** С шимом
  `0x0788` поток mnld→чип совпадал с прежним (sha256 `d83b6e09…`,
  39 721 Б, 30 кадров), чип отдавал только `0x31` + 28 ACK. После
  исправления на `0x6771` mnld отправил 1533 кадра / 106 824 Б
  (родной MT6771-образ), чип ответил 677 кадрами и NMEA пошла.
  Первый вывод («chipid не влияет») был сделан на неверном значении
  свойства и оказался ошибочным.
- **EMI — ложный след.** `read()` в `gps_emi.c` всегда возвращал 0
  (не выставлялся `ret`) — исправлено. После фикса прочитаны оба MiB
  региона CONNSYS: в первом (`emi_off_mb=0`, `0xbfc00000`) лежит
  coredump/лог (nonzero 56 704), сигнатуры DSP-образа нет; во втором
  (`0xbfd00000`) — нули. Вывод: образ уходит по STP внутрь combo-чипа,
  а не в SoC EMI; проверять там нечего.
- **ioctl 9 (D1 efuse) реализован для MT6771** (`0x11f10048`): mnld его
  действительно вызывает сразу после `GPS_open`, раньше получал
  `Read Efuse not supported`. На старт DSP не повлияло.
- **Проба протокола** (`tools/device/mnl-probe.py`, non-blocking):
  keepalive → молчание; неизвестный тип `0x99` → молчание; config →
  ровно один `0x31`; т.е. ответы настоящие и адресные, не canned.
- **WMT-путь GPS on** проверен по исходникам: `wmt_func_gps_pre_ctrl`
  делает только GPS_SYNC и LNA, канала `gps_mcu_ctrl` в power-on нет;
  VCN28 подан (regulator_summary: 2800 мВ, потребитель consys активен).
  ROM-patch файлы на месте, MCU-патч скачивается (166 фрагментов),
  версия чипа определяется как `SOC_CONSYS.E1 (0x8a00/0x8a00)`.
- **Ограничение метода:** `arm-linux-gnueabihf-objdump` по `libmnl.so`
  не находит литеральных ссылок на строки (`_BootDSP_UART_V2`,
  `ChipID,x,`) — PIC-адресация; дальнейший статический RE требует
  radare2/Ghidra.

## Следующие шаги (по приоритету)

1. **DTS pinctrl (единственное известное несоответствие стоку):**
   добавить в `consys@18070000` `pinctrl-names` = "default",
   "gps_lna_state_init", "gps_lna_state_oh", "gps_lna_state_ol" и
   `pinctrl-0..3` с `gpslna@0/1/2` (`pins = "gpio155"`,
   `pinmux = <0x9b00>`), пересобрать dtb. Проверить
   `GPS LNA gpio pin number:155` и ioctl 16 = 155. На NMEA не влияет
   (GPS уже работает), но это штатное питание антенны.
2. **Satellite**: открыть приложение на планшете и убедиться, что оно
   читает `/run/t1100-nmea.sock` (сокет отдаёт `$GPGSV` с 12
   спутниками). Если нет — смотреть клиент Satellite, а не GPS.
3. **Холодный старт**: с холодного бута замерить время до первых
   `$GPGSV` (сейчас проверено на тёплом состоянии: NMEA пошла сразу
   после загрузки образа). Если mnld не поднимается — проверить, что
   сервис стартует с `LD_PRELOAD` (это было главной причиной).
4. **Убрать зависимость от шима** (косметика): когда появится
   property-сервис или пропатченный mnld, `LD_PRELOAD` можно убрать;
   ценность шима — только `chipid=0x6771` и `nvram_init=Ready`.

## Инструменты

- `tools/device/gps-capture.py` — pty-захват (`tty.setraw`, symlink
  `/dev/stpgps` → `/dev/pts/N`, реальный узел `.real`, восстановление
  в atexit). Обязательны оба флага: `--start-mnld --start-hal` (без
  HAL `mnld` не пишет в устройство). Пишет `.txt`, `.mnld.bin`,
  `.chip.bin`.
- `tools/device/gps-replay-raw.py` — replay сырого потока без разбора
  полей длины.
- `rootfs-overlay/usr/local/sbin/t1100-gps` — штатный клиент:
  `--replay FILE`, `--replay-pause`, `--power-cycle`, `--seconds`,
  `--raw`; печатает не-ACK кадры и `$`-строки.
- `tools/device/mnl-probe.py` — non-blocking проба `/dev/stpgps`:
  keepalive / неизвестный тип / config, печатает hex ответов.
- `tools/device/t1100-propfix.c` — ARM32 `LD_PRELOAD`-шим
  `__system_property_get` (chipid + nvram), лог в
  `/data/vendor/gps/propfix.log`; сборка
  `arm-linux-gnueabihf-gcc -shared -fPIC -nostdlib -O2`.
- Драйвер: `insmod gps_drv.ko t1100_trace=1` (есть ещё `emi_off_mb`).
- Сборка: `scripts/build-gps-remote.sh` с
  `BUILD_HOST=l@172.17.141.124`,
  `EXTRA_SYMBOLS=/home/l/t1100-wifi-build-own48/work/common/Module.symvers`,
  `LOCALVERSION=-wifi1`.

## Доступы и пути

- Планшет: `192.168.2.77` (Wi-Fi, root/`REDACTED`; с dev-хоста SSH
  работает по ключу). USB `10.42.66.66` — интерфейс `enx*` есть, но
  IPv4 не поднят (NM-профиль `t1100`).
- Build host: `l@172.17.141.124`, pass `0`; kernel
  `/home/l/t1100-ubuntu-build/src-nonwifi` + `out-wifi`; wmt source
  `/home/l/t1100-wifi-build-own48/work/common`.
- Планшет: `/root/gpscap-real2.mnld.bin` (полный поток),
  `/root/gpscap-real2.chip.bin` (ответы), `/root/gps-frames-ok.bin`
  (тот же поток, но парсить только по `AA 0F`), `/root/gps-capture.py`,
  `/root/gps-replay-raw.py`, `/root/aurora-root.img`, `/opt/bionic`
  (chroot), `/data/vendor/gps`.
- Репозиторий: `docs/gps-port-log.md`, `docs/gps-mnl-reverse.md`,
  `docs/STATUS.md`; `refs/stock-mt6771.dts`, `refs/emi-mpu-*`;
  стоковые образы — `../1100/`.

## Состояние планшета на момент передачи

- Wi-Fi `.77` жива; `t1100-internal-gps` stopped/disabled; `mnld` и
  `gps_hal_test` не запущены; `/dev/stpgps` 191:0; `gps_drv` загружен
  с `t1100_trace=1`; ассертов в текущем буте нет.
- После assert-шторма нужен **холодный старт** (выключить, снять
  заряд на 10–15 с); тёплый ребут CONSYS не сбрасывает.
- Не коммитить `vendor/vcodec/tools/ionshim.c` (чужая работа);
  коммиты — явными путями, пушить периодически.
