# Эксперимент A: отдать мост IT6112 загрузчику (07.11.2026)

Гипотеза (из `docs/handover.md`, п. 2d): вендор инициализирует мост **и панель**
в LK, поэтому нужно проверить, не оживёт ли панель, если наш драйвер вообще не
будет программировать IT6112.

**Результат: панель работает.** На состоянии, которое оставил LK, экран
показывает консоль (`Ubuntu 24.04.3 LTS t1100 tty1` / `t1100 login:`) — это
подтверждено и владельцем («пингвинов видел и список загружаемых сервисов,
сейчас просит логин»), и дампом самого фреймбуфера:
`refs/device/fb0-expA2-console.png` (тот же текст читается из `/dev/fb0`).

## Переключатель (патч 0036)

`patches/0036-drm-panel-it6112-add-a-switch-that-leaves-the-bridge.patch`,
коммит `7dc074437` в `../linux-t1100`:

```
t1100.it6112_skip_init=1        # в cmdline boot.img
```

Драйвер собран в ядро, поэтому используется `__setup()`; менять поведение можно
**без пересборки** — только перепаковкой `boot.img` (`scripts/repack_boot.py`).
В этом режиме драйвер:

- в `probe` не делает power-up, reset-pulse и не гасит рельсы после чтения PID;
  GPIO (`reset`/`stby`/`ext-pwr`) запрашиваются как `GPIOD_ASIS` и их уровни
  печатаются в dmesg, PID читается «как есть» (не фатально) и дампится состояние
  моста `boot:`;
- в `prepare` включает только рельсы панели (`dvdd` всегда включён, `vpos`/`vneg`
  — DSV MT6370);
- в `enable` не пишет ни одного регистра TX/RX и не трогает TX-PLL: только DCS
  `exit sleep` и `display on` через пакетный регистр `0x73` (+ повтор из
  delayed work через 200 мс);
- в `unprepare` ничего не выключает и не сбрасывает (иначе состояние LK
  теряется навсегда).

## Итерация 1 (`build/boot_ubuntu18.img`, sha256 `a5baad10…a88a01`): мост «умер»

Первая версия патча всё ещё запрашивала `stby`/`ext-pwr` как `GPIOD_OUT_LOW`.
Это **сразу выставляет линии в 0**, то есть снимает `EXT_PWR` (GPIO175) и
`STBY` (GPIO44), ещё до чтения PID. Факты (`refs/device/dmesg-expA1-skip-init.txt.gz`,
`refs/device/it6112-regs-expA1-skip-init.txt.gz`):

```
it6112_bridge 3-0056: experiment A: bridge product id 0x0000 (read without touching the bridge)
it6112_bridge 3-0056: boot: tx 00-2c: 00 00 00 ... (все регистры TX/RX = 0x00)
 gpio-556 (stby) out lo | gpio-557 (reset) out hi | gpio-687 (ext-pwr) out lo
```

То есть эксперимент был испорчен собственным драйвером: чтение возвращало
нули, а не состояние LK. Вывод итерации: `EXT_PWR` обязателен, и запрос линии
как выхода сам по себе является вмешательством.

## Итерация 2 (`build/boot_ubuntu19.img`, sha256 `ec631615…733620`): экран работает

С `GPIOD_ASIS` мост отвечает и **остаётся в рабочем состоянии LK**:

```
it6112_bridge 3-0056: experiment A: lines as the bootloader left them: reset=1 stby=0 ext-pwr=1
it6112_bridge 3-0056: experiment A: bridge product id 0x6112 (read without touching the bridge)
it6112_bridge 3-0056: boot: tx 00-2c: 54 49 12 61 b0 00 00 00 00 00 00 00 00 08 58 04 a0 63 00 24 ff ff ff ff 00 00 ff ff ff ff ff 0b 24 03 30 00 01 00 01 00 00 00 40 00 00
it6112_bridge 3-0056: boot: tx 44-47: 0d 24 22 12
it6112_bridge 3-0056: boot: tx b0-b0: 27
mtk-dsi 14014000.dsi: T1100DSI: started, start=0x1 con=0x0 mode=0x1 ps=0x312c0 txrx=0x3c
it6112_bridge 3-0056: MCLK=188MHz
it6112_bridge 3-0056: stream-on: rx 21 = 0x08 (bit3 = video format auto-detected)
it6112_bridge 3-0056: experiment A: re-sending exit sleep/display on
```

Счётчики: `grep 14014000.dsi /proc/interrupts` = **0** (video mode, IRQ не
используются — как и раньше, это не признак). Подсветка `1023/1023`, DSV
`vpos/vneg 5500 мВ` (use_count 1), `card0-DSI-1` = `connected`/`enabled`,
режим `1600x2176`.

## Чем наш init отличается от состояния LK

Сравнение устойчивых регистров (динамические `0x0d`–`0x0f` RX/TX и `0x94`–`0x9b`
не считаем — они меняются сами между двумя чтениями без единой записи):

| Регистр | Оставил LK | Пишет наш драйвер | Комментарий |
|---|---|---|---|
| TX `0x22` | `0x30` | `0x21` | наша формула из RE (`it6112_tx_calc_clk()`); `0x30` — дефолт чипа, LK его **не пишет** |
| TX `0x24` | `0x01` | `0x00` | мы чистим младший ниббл (`V_LPS_TIME`) |
| TX `0x26` | `0x01` | `0x00` | мы чистим младший ниббл (`LPX_NUM`) |
| RX `0x11` | `0x01` | `0x02` | мы ставим bit1 («inverse MCLK» по RE); у LK bit0 |
| TX `0x05` | `0x00` | `0x00` | совпадает (в процессе init мы ставим `0x20` HOLD_TX и снимаем) |
| TX `0x06/0x10/0x11/0x1f/0x21/0x23/0x25/0x27/0x3c/0x44..0x47/0xb0/0xd0/0xd3` | — | — | совпадают |
| RX `0x05/0x09/0x0a/0x0b/0x0c/0x18/0x19/0x20/0x21/0x27/0x44/0x72/0x80/0x8a/0xa0` | — | — | совпадают |

Итого подозреваемых ровно четыре записи: **TX `0x22`, `0x24`, `0x26` и RX `0x11`**.
Остальная часть нашей инициализации (reset/power sequence, `0x05/0x10/0x11/0x3c/
0x44/0x45/0x47/0xb0`, RX-блок) состоянию LK не противоречит.

## Воспроизведение

```sh
# ядро с патчем 0036 (build/boot_ubuntu19.img)
OUT=/home/l/projects/t1100-ubuntu/build/k1 scripts/build_kernel.sh
gzip -9 -c build/k1/arch/arm64/boot/Image > /tmp/Image.gz
python3 scripts/repack_boot.py --ref build/boot_ubuntu17.img \
    --kernel /tmp/Image.gz --ramdisk <ramdisk> \
    --dtb build/k1/.../mt6771-fplus-t1100.dtb \
    --cmdline "<старый cmdline> t1100.it6112_skip_init=1" --out build/boot_ubuntu19.img
tools/host/flash-ssh.sh build/boot_ubuntu19.img /dev/mmcblk0p29 --reboot
```

Дампы: `refs/device/dmesg-expA2-gpio-asis.txt.gz`,
`refs/device/it6112-regs-expA2.txt.gz` (сняты через `tools/i2cpeek` на живом
мосте), `refs/device/diag-drm-expA2-gpio-asis.txt.gz`,
`refs/device/fb0-expA2-console.png` (содержимое фреймбуфера — доказательство,
что картинка доходит до панели).

## Что дальше

1. Вернуть нормальный путь (`skip_init=0`), но **не писать** TX `0x22`, `0x24`,
   `0x26` и не ставить RX `0x11` bit1 (оставить значения чипа/LK). Это
   единственное известное расхождение с работающим состоянием.
2. Если после этого экран жив, но картинки нет — по одному возвращать записи,
   начиная с `0x24`/`0x26`, и смотреть на экран (переключение — только cmdline,
   без пересборки).
3. Параллельно полезно снять дамп LK-инициализации панели: LK лежит на плате
   (`mmcblk0p28`, дамп `build/lk/lk_a.bin`, sha256 `cedbe12e…0f76a`, загрузка по
   `0x56000000`); `lcm init` для `tv110xum_lb2` — `0x56031a40`, там же таблица
   DCS для панели (`0x73`), которую наш драйвер не отправляет вовсе.

## Ограничения эксперимента

- `modetest`/`kmscube` на планшете не установлены, поэтому проверка — по
  `/sys/class/drm`, debugfs и содержимому `/dev/fb0`; текст на панели совпадает
  с содержимым фреймбуфера.
- Мост при `skip_init=1` остаётся в состоянии LK: после `poweroff`/холодной
  загрузки его снова инициализирует LK, так что это состояние воспроизводимо,
  но не является «нашей» инициализацией.
