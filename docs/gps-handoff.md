# GPS MT6771 (Fplus T1100) — передача в новую сессию

Дата: 22.11.2026 (ред. 2, после полного pty-захвата потока `mnld`).
Читать вместе с `docs/STATUS.md` и `docs/gps-port-log.md`.

## Цель

Внутренний GPS планшета T1100 (MT6771/MT8788, MT6631) на ALT/Ubuntu:
NMEA/фиксы в Satellite. Wi-Fi `192.168.2.77` не ломать. Внешний
Android-бридж (`t1100-nmea-adb`) не использовать.

## Итог одной строкой

Транспорт STP и загрузка DSP-образа работают: `mnld` (и наш клиент его
потоком) шлёт 30 кадров, чип отвечает статусом `0x31` и 28 ACK `0x32`,
но **ни одного кадра измерений не отдаёт**. NMEA формирует
`libmnl.so` в userspace из измерений чипа — ждать `$`-строки прямо из
`/dev/stpgps` бессмысленно; «NMEA 21.11» в commit `9f20e28` по журналам
не подтверждается.

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
2. `persist.vendor.connsys.chipid` — в стоке `-1`, выставляет
   `wmt_launcher` (`0x788` для MT6771). Закрыто шимом (см. «22.11 (4)»):
   с `0x0788` поток DSP-фрагментов не изменился, т.е. на выбор образа
   chipid не влияет.
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
- **С выбором DSP-образа chipid не связан:** поток mnld→чип с шимом
  побайтово совпал с прежним (sha256 `d83b6e09…`, 39 721 Б, 30 кадров),
  chip по-прежнему отдаёт только статус `0x31` + 28 ACK `0x32`.
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

1. **DTS pinctrl**: добавить в `consys` состояния `gps_lna_state_*`
   (`pins = "gpio155"`, init/oh/ol) и `pinctrl-1`-phandle; пересобрать
   dtb; проверить `GPS LNA gpio pin number:155` и ioctl 16 = 155.
   Это штатный путь LNA и нужен сервису независимо от NMEA.
2. **~~Property shim~~ — СДЕЛАНО** (см. раздел «22.11 (4)»):
   `tools/device/t1100-propfix.c` → `libpropfix.so`, `LD_PRELOAD` в
   chroot. `chipid=0x0788` и `nvram_init=Ready` mnld видит. На выбор
   DSP-образа это не влияет (поток тот же) — пункт закрыт.
3. **Проверить, доходит ли DSP boot**: в `libmnl.so` есть
   `_BootDSP_UART_V2(): code_size,start_addr,exec_addr,cipher_key,
   code_frag_num`, `BootDSP: start/finished`; в logd этих строк нет.
   Включить debug-вывод mnld и `fw_log_gps` (ioctl ON_OFF=1), снять
   лог DSP после replay. Если `code_frag_num` не 28 — геометрия
   образа другая.
4. **Именованные DSP-образы**: выяснить размер/формат
   `MT6771_DSP_0064_B183/C189` и отправить их фрагментами `0x0C`
   вместо generic. Сравнить реакцию чипа.
5. **Эталон с рабочего Android**: снять `chip.bin` на устройстве, где
   GPS реально даёт фиксы (AYYA T1 `192.168.2.113` сейчас недоступен;
   можно стоковый Android на самом T1100, если найдётся время).
   Главный вопрос — какие кадры чип шлёт после 28 ACK.
6. Если измерений так и нет — проверить питание/клок GPS-ядра в WMT
   (`wmt_ctrl`, `co_clock_flag`) и статус `0x31`: его поле
   `46 15 00 00 00 00 00 00 98 01` пока не декодировано.

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
