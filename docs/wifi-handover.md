# Wi-Fi (внутренний CONSYS/MT6631) — состояние и хендовер

Документ для продолжения работы в следующей сессии. Описывает, что уже работает,
где именно мы застряли, какие артефакты остались и что делать дальше.
Хронология по рубежам — `docs/wifi-port-log.md` (§1–§90) и `docs/STATUS.md`
(разделы «12.11 (12)…(35)», «13.11», «16.11»).

## 1. Короткий итог

- **Второй разработчик довёл внутренний Wi-Fi до рабочего состояния**: `wlan0`,
  скан, ассоциация с `home` (5 ГГц, канал 52, 433 Мбит/с), DHCP
  `192.168.2.146/24`, `ping 1.1.1.1` 17 мс, SSH по Wi-Fi. Его отчёт —
  `docs/wifi-port-log.md` §86–§87, сводка — `docs/STATUS.md` «16.11 (4)…(5)».
- **Мы это состояние воспроизвести пока не смогли**: его `.ko` в git не попали,
  а сборка из репозитория (чистый `vendor/` + патчи) даёт модули, которые
  **вешаются внутри `nicpmSetDriverOwn()`**.
- Плата сейчас в безопасном состоянии: `t1100-wifi.service` **masked**,
  автозапуска нет, ssh/заряд живы, `wlan0` отсутствует.

## 2. Что сделано и зафиксировано в репозитории

### 2.1 Смержено

`origin/master` содержит его работу (49 коммитов, fast-forward без конфликтов):
Wi-Fi (`0039–0047`), BT по STP (`0077`), FM, GPS, WEXT-скорость линка, плюс
купон работ по питанию/термалу/батарее/микрофону.

### 2.2 Патчи Wi-Fi (`patches/wifi/`, 49 файлов)

Две линии, обе лежат в дереве:

- **наша** (доведение вендорского стека): `0009`, `0010-common-btif-stp`,
  `0013`, `0015–0019` — порт, BTIF-транспорт (включая исправленную полярность
  гейта!), SPM-partial/warm-reset, доставка набора ROMv4, стп-трассы, Makefile;
- **его** (рабочий режим): `0020–0047`, ключевое:
  - `0027` skip driver-own при WMT, `0028` func-on через WMT, `0029` STP init-cmd;
  - `0039` stock start order (стоковый gate `fgIsFwOwn == TRUE ⇒ abort`, один
    `wlanConfigWifiFunc(FALSE,0)`), `0040` без дампов MCR, `0041` тихое окно;
  - `0042` NVRAM из `/mnt/vendor/nvdata/APCFG/APRDEB/WIFI` (даёт реальный MAC
    `08:26:ae:b1:87:39`);
  - `0043` post-ready диагностика (**по умолчанию выключена** — иначе FW уходит в
    `FW_OWN_INVALID_ACCESS` и `Whole chip reset`, см. §87);
  - `0044` CMD52-wake (не помог), **`0045` `t1100_no_fw_own=1`** — не отдавать
    владение FW, иначе MCU гасит HIF-окно `0x180f0000`;
  - `0046`/`0047` — WEXT link speed и попытка power-save.

Важно: **его линия не собирается без нашей** — `0030` не накладывается без
`0017`, `0020` — без `0018`, а `0016` нужен из-за
`mtk_wcn_stp_reset_seq_state()` (иначе `modpost: undefined`).

### 2.3 Rootfs для Wi-Fi (то, что жило только у него на плате)

- `rootfs-overlay/etc/modprobe.d/99-t1100-wifi.conf`:
  `options wmt_drv t1100_btif_stp=1 t1100_quiet_ms=100 t1100_rom_patch="ROMv4_be_patch_1_1_hdr.bin ROMv4_be_patch_1_0_hdr.bin"`,
  `options wlan_drv_gen3 t1100_probe=0 t1100_rom_patch_mcif=0 t1100_pwr_on_done=1`;
- `rootfs-overlay/etc/systemd/system/t1100-wifi.service` (oneshot) и helper
  `usr/local/sbin/t1100-wifi-func-on` (ioctl `0x4004A006` / `0xBEEF0003` на
  `/dev/stpwmt`). Helper'ы должны быть **исполняемыми** (в git были 644 →
  systemd `203/EXEC`), `tools/host/deploy-overlay.sh` это теперь ставит;
- `mnt-vendor-nvdata.mount` — без него `0042` не находит NVRAM.

### 2.4 Прошивки (лежат на планшете в `/lib/firmware`)

`ROMv4_be_patch_1_0_hdr.bin` (`83f7e9bc…`, 229 384 Б),
`ROMv4_be_patch_1_1_hdr.bin` (`2203d8b7…`, 314 120 Б),
`WIFI_RAM_CODE_6759` (480 752 Б), `WMT_SOC.cfg`, `soc3_0_ram_*`, `mt6631_fm_*`.
Источник — образ Aurora (`/home/l/aurora_root.img`, `/vendor/firmware`), см.
`tools/host/extract-aurora-firmware.sh`.

## 3. Где именно мы застряли (наши замеры)

Рабочая последовательность по §86:

```sh
modprobe wmt_drv t1100_quiet_ms=100
modprobe wlan_drv_gen3 t1100_probe=0 t1100_rom_patch_mcif=0 t1100_pwr_on_done=1
/usr/local/sbin/t1100-wifi-func-on
```

Что у нас происходит (последний прогон, `hisline`-сборка):

```
polling_consys_chipid: chipId 0x00000788
patch ROMv4_be_patch_1_1_hdr.bin: num=2 seq=1 addr=218007f0 size=314120
patch ROMv4_be_patch_1_0_hdr.bin: num=2 seq=2 addr=22800900
co-clock enabled
t1100_btif_boot_work: WMT_OPID_PWR_ON (BTIF STP, ROM patch) -> 1
opfunc_wlan_probe: not implemented yet hifType: 0x2
t1100-clk: HIF DMA clock enabled, rate=156000000
t1100_load_nvram_file: nvram loaded from file (1024 bytes)
wlanAdapterStart: driver-own skipped (CONSYS owned by wmt_drv)
nicpmSetDriverOwn: CMD52 own readback 0x00 (i=0) … (i=384)   ← последняя строка
```

То есть: patch-сет доставляется, NVRAM читается, но **прошивка не отдаёт
владение** (`WHLPCR_FW_OWN_REQ_SET` не встаёт, readback `0x00`), цикл крутится
~0.4 с, после чего обращения к окну HIF вешают шину (`usb0` умирает, `helper.out`
пуст). В **его рабочем** логе на этом месте было `DRIVER OWN, status=1 count=14`.

### 3.1 Что исключено нашими замерами (чтобы не повторять)

| Гипотеза | Почему закрыта |
|---|---|
| неверное окно/база MCR | регистры MCU читаются через CMD53 (`0x180f0000` setup → `+0x1000` data), проверено дампом |
| «chip-id не тот» (`0xf004`) | это было слово CMD53, реальный `WCIR=0x00100788` |
| ROMv4-патч не доставляется | доставляется: `1_1` 315/315, `1_0` 230/230, `reset ack: yes` |
| не тот файл/смещение/CRC | файлы совпадают со стоковыми по sha256; резка 28 Б как в стоке; хвостового CRC нет |
| неверная start-команда | `wmt_loader`/mt6765 подтверждают `WMT_RESET_CMD`; H2D/`WSICR` в путь старта не входят |
| EMI MPU | на arm64 только через SMC, LK стоковый ⇒ настроен |
| клок CONN main | это наш же SPM `0x1000632c` |
| гейт BTIF | был **инвертирован** — это был корень M23–M28, исправлено (`IFR0[31]=1` = клок закрыт) |
| `u4DataMode`/`ucEnc` | правка оказалась no-op: у секции 1 `ucEnc=1` и так; флаги не влияли |
| запись образа по STP | вешает домен (проверено 1×) |
| двойной путь из-за смешения линий | без наших `0015` поведение идентично |

## 4. Гипотезы, которые остались (по убыванию вероятности)

1. **Точная комбинация патчей/параметров у него.** У нас `own` не приходит вообще,
   у него — за 14 мс. Отличие наверняка в конкретном наборе (его `work/` не
   совпадал с репозиторием). Самый быстрый путь — получить от него:
   `patches/wifi` целиком + команду сборки, либо три `.ko` с sha
   (`wmt_drv 73256ebb…`, `wlan_drv_gen3 505273da…`, `mtk_btif_drv 92d4740c…`).
2. ~~**`0046`/`0047`** (WEXT/power-save)~~ — **проверено, не причина**: без них
   клин воспроизводится (`wlan_drv_gen3` `b736e185…`, журнал §91). Значит виснет
   штатный `HAL_MCR_RD(MCR_WHLPCR)` в `while(1)` (~0.4 с, шаг 1 мс), то есть шина
   отказывает при повторных обращениях к `0x180f0000`, когда MCU не отвечает.
3. **`t1100_btif_stp=0`** — power-on и ROMv4-патчи не из boot-work, а через
   ioctl-путь. **Следующий по плану, не проверен.**
4. **`t1100_quiet_ms=1000`** вместо 100 — дать MCU больше времени после хвоста
   патча. **Не проверен.**
4a. **1 + 3** — комбинация. **Не проверена.**
5. **`0043` (`t1100_post_ready`)**: у него дефолт выключен; если кто-то включит —
   гарантированный `FW_OWN_INVALID_ACCESS` и `Whole chip reset` (см. §87).

## 5. Правила работы с платой (выстрадано)

- **`rmmod` вендорских модулей не вызывать никогда** — выгрузка уходит в D-state
  и вешает shutdown; получается цикл перезагрузок (лечение — recovery, см.
  `docs/STATUS.md` «13.11 (59)»).
- Для смены модулей: `sync; echo b > /proc/sysrq-trigger` (немедленный рестарт,
  процессы не ждём). Если плата зависла намертво — нужен физический power-cycle.
- **`t1100-wifi.service` держать masked**, пока комбинация не подтверждена:
  его helper вешает SoC детерминированно (~5 с после multi-user).
- Если автозапуск всё же включён и плата уходит в цикл — из recovery:
  ```
  mount /dev/mmcblk0p54 /mnt/r
  rm -f /mnt/r/etc/systemd/system/multi-user.target.wants/t1100-wifi.service
  ln -sf /dev/null /mnt/r/etc/systemd/system/t1100-wifi.service
  sync; umount /mnt/r; reboot
  ```
  Доступ к recovery — `tools/host/recovery.py` (telnet поверх USB: поднять
  интерфейс и дать хосту `10.42.66.67/29`, планшет `10.42.66.66`).
- Не прошивать boot/ядро ради экспериментов: патчи Wi-Fi — модульные, ядро
  остаётся `6.12.114-g400cb6f-touch-rot`.

## 6. Что рядом и тоже важно (не потерять)

- **Заряд**: профиль `hub` в `/etc/default/t1100-charge` (`HUB_IAICR_UA=2500000`,
  `ICHG=2000000`), проверено на powered hub: `IBUS≈2.0 А`, `IBAT≈1.45 А`,
  `VBUS 4.43–4.55 В`. Если окажется нестабильно — откат до 1.5 А и
  `VBUS_MIN_MV=4300`. Утилита `t1100-charge.sh` (`status/sample/set/auto/hub/wall/off`).
- **Вход root**: PAM-служба `sddm` блокировала greeter (`user != root`) — снято,
  файл в `rootfs-overlay/etc/pam.d/sddm`; проверка — `tools/host/check-root-login.sh`
  (см. `docs/root-login-pam.md`).
- **Watchdog-цикл** из-за `rmmod`: `RuntimeWatchdogSec=0`, `DefaultTimeoutStopSec=20s`
  в `/etc/systemd/system.conf.d/10-t1100-timeouts.conf`.

## 7. Полезные артефакты

| Что | Где |
|---|---|
| Отчёты по рубежам Wi-Fi | `docs/wifi-port-log.md` (§82–§90 — самая свежая часть) |
| Сводка по фазам | `docs/STATUS.md` («16.11 (4)…», «13.11 (59)», «14.11») |
| Скрипт сборки стека | `scripts/build-wifi-remote.sh` (приватный `WIFI_DIR`, `KERNEL_OUT=/home/l/t1100-merge2-out`) |
| Развёртывание оверлея | `tools/host/deploy-overlay.sh` |
| Доступ к recovery | `tools/host/recovery.py` (`sh`/`get`/`put`/`reboot`) |
| Снимок/диагностика BTIF | `tools/device/btif-probe.sh`, `tools/mempeek/` |
| Файрмвари combo-чипа | `/lib/firmware` на планшете; источник — `/home/l/aurora_root.img` |

## 8. С чего начинать следующую сессию

1. **Плата:** после последнего прогона SoC остался в клине — нужен физический
   power-cycle. После включения поднимется штатно (`t1100-wifi` masked).
2. **Прочитать** `/root/own-1.log` (потоковый `dmesg -W`, пережил сброс) — там
   последние строки перед клином на варианте «без 0046/0047».
3. **Продолжить перебор с варианта 2** из §4: `t1100_btif_stp=0`, затем
   `quiet_ms=1000`, затем комбинация. Дисциплина прежняя: один прогон — одно
   изменение, `dmesg -W` в файл + `sync`, helper под `timeout 20`.
4. **Параллельно** — запросить у автора рабочего решения его `patches/wifi`
   и/или три `.ko` (`73256ebb…`, `505273da…`, `92d4740c…`): это самый короткий
   путь, потому что у него `DRIVER OWN, status=1 count=14`, а у нас own не
   приходит вовсе.
5. Подробный разбор последнего рубежа — `docs/wifi-port-log.md` §91,
   `docs/STATUS.md` «16.11 (16)».
