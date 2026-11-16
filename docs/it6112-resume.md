# IT6112: восстановление моста после остановки DSI-потока (s2idle / DPMS)

Дата: 15–16.11.2026. Патч: `patches/0074-drm-panel-it6112-recover-the-bridge-after-the-dsi-st.patch`.

## Симптом

После 10-минутного `s2idle` (пробуждение по RTC) физическая панель показывает
цветные полосы. При этом `KWin`-скриншот (`/tmp/opencode/after_sleep.png`,
2176×1600) чистый, то есть GPU/DRM/panfrost и композитор кадр отдают правильно —
портится путь DSI → IT6112 → панель.

## Что не помогало (до патча)

- `kscreen-doctor --dpms off/on` — полосы остаются;
- полный modeset (`output.DSI-1.rotation.normal` → `right`) — не помогает;
- повторная посылка DCS `exit sleep` / `display on` из драйвера
  (`experiment A: re-sending exit sleep/display on` в dmesg) — не помогает.

Ошибок CMDQ/DSI в dmesg нет; DSI стартует с теми же `start=0x1 mode=0x1
ps=0x312c0 txrx=0x3c`, что и при загрузке.

## Измерения на живом «сломанном» мосте

Снят полный дамп TX (`0x56`) и RX (`0x5e`) через `i2cpeek`
(`refs/device/it6112-regs-broken-2026-11-15.txt`). Сравнение с рабочим
состоянием загрузки (dump `post-dcs` в `dmesg`, `refs/device/journal-it6112-resume-2026-11-15.txt.gz`):

| Блок | Результат |
|---|---|
| TX `0x00..0x2f`, `0x30..0x4f`, `0x98..0xd7` | совпадает, кроме счётчиков `0x0e` и `0xa6` (меняются при каждом чтении) |
| TX `0x05` | `0x00` — `HOLD_TX` снят, DCS проходит |
| TX `0x06` | `0x00` — тот самый bit2, который нельзя ставить |
| TX `0x22` / `0x1f` | `0x30` / `0x0b` — как в рабочем состоянии LK |
| RX `0x00..0x6f` | побайтово совпадает, включая `RX 0x21 = 0x08` (bit3: формат видео автоопределён) |
| I2C | мост отвечает на оба адреса |

Вывод: **регистровая карта цела**. Ломается не конфигурация, а внутренний
TX-автомат вывода: когда исчезает входной поток (DSI уходит в ULP на DPMS
off / suspend), он теряет тайминг и сам не восстанавливается.

## Вендорский импульс

В LK перед DCS идёт импульс `TX 0x05 = 0xfe` → `0x00` (биты 1..7, затем ноль;
`0x05` bit0 чип не принимает — NAK, это свойство чипа). На живом «сломанном»
мосте:

```
/root/i2cpeek -w 3 0x56 0x05 0xfe
/root/i2cpeek -w 3 0x56 0x05 0x00
```

картинка возвращается сразу. Проверено дважды: 12.11 (после DPMS off/on) и
15.11 (после s2idle) — оба раза владелец подтвердил.

## Реализация: патч 0074

Режим выбирается в cmdline (перепаковка boot.img, без пересборки ядра):

```
t1100.it6112_resume=full    # по умолчанию
t1100.it6112_resume=pulse
t1100.it6112_resume=none
```

- **full** — при повторном `->prepare()` (после остановки потока) выполняется
  reset-импульс моста и полный RX/TX init; затем в `->enable()` измеряется
  MCLK, пересчитываются `0x22`/`0x1f`, посылается TX-импульс и только потом
  DCS `exit sleep`/`display on`;
- **pulse** — только TX-импульс перед DCS (лёгкий путь, без reset);
- **none** — прежнее поведение (для бисекта).

`->prepare()` вызывается до старта потока (`drm_atomic_bridge_chain_pre_enable`
идёт в обратном порядке), поэтому reset и init не мешают видео;
`->enable()` — уже после `mtk_dsi` `output_enable`, поэтому MCLK измеряется на
живом потоке, как это делает LK.

Путь загрузки не изменён: при `t1100.it6112_skip_init=1` первый `->enable()`
по-прежнему не трогает состояние, оставленное LK (`enabled_once` = false,
`bridge_owned` = false). Восстановление включается со второго enable.

Регуляторы переведены на учитывающий хелпер (`rails_on`), иначе повторные
`->prepare()` в режиме skip накапливали бы usecount.

## Проверка на железе

Образ `build/it6112-resume/boot_resume_full.img` (kernel `6.12.114 #14`,
sha256 `75af7b5f3343f0bfd6d2c748ea5c06f38752fc2ac2039447373f342668a81687`,
md5 p29 `21fee0a6803b5b305009c9ebdc350752`), cmdline = cmdline p29 v5
(`t1100.it6112_skip_init=1`), DTB и ramdisk из p29 v5.

| Что | Факт |
|---|---|
| загрузка | панель нормальная, `skip-init 1`, DSI-1 connected (владелец) |
| DPMS off 6 с → on | dmesg: `bridge re-initialised for resume`, `MCLK=188MHz`, `TX clk: MCLK=188100 kHz -> 0x22=0x2f 0x1f=0x0b`, `started`; картинка нормальная (владелец) |
| s2idle, 5 циклов (15.11) | в каждом dmesg `bridge re-initialised for resume`; после resume картинка чистая, полос нет (подтверждено визуально) |
| s2idle, наш прогон | `PM: suspend entry (s2idle)` 11:55:54 → пробуждение 11:57:40 → `bridge re-initialised for resume` 11:57:41, DSI `started`, кадр пошёл |
| 10 минут с RTC | **пока не выполнен**: panfrost не уходит в suspend (`PM: failed to suspend: error -16` после `js fault ... DATA_INVALID_FAULT`), сон обрывается через ~1 с; это отдельный GPU-баг, вне задачи про панель |

То есть код-путь resume проверен и на реальном s2idle, а не только на DPMS;
10-минутная выдержка блокируется не дисплеем, а panfrost (см. ниже).

## Финальный тест (когда планшет свободен)

Предусловие: планшет должен реально проспать 10 минут. Сейчас длинный s2idle
обрывает panfrost:

```
panfrost_device_suspend()            drivers/gpu/drm/panfrost/panfrost_device.c:478
  pm_runtime_force_suspend()
    panfrost_device_runtime_suspend()                            :416
       if (!panfrost_job_is_idle(pfdev)) return -EBUSY;          :420
```

То есть после `js fault ... DATA_INVALID_FAULT` зависший job никогда не
становится idle, и системный suspend возвращает `-EBUSY` (в dmesg:
`panfrost 13040000.gpu: PM: failed to suspend: error -16`). Это отдельный
GPU-баг, драйвер panfrost по условию задачи не трогаем. Как обойти его для
проверки панели, не меняя GPU-код:

1. остановить графическую сессию: `systemctl isolate multi-user.target`
   (KWin/SDDM отпускают GPU, на панели остаётся текстовый fbcon);
2. снять panfrost с шины (тогда его PM-колбэк вообще не вызывается):
   `echo 13040000.gpu > /sys/bus/platform/drivers/panfrost/unbind`;
3. убедиться, что сон не обрывается: `dmesg | grep "failed to suspend"` — пусто;
4. после теста вернуть: `echo 13040000.gpu > /sys/bus/platform/drivers/panfrost/bind`.

Второй вариант — дождаться, пока panfrost-suspend починят, и повторить с KWin.

Планшет — эксклюзивный ресурс: перед прошивкой согласовать окно и **снять
бэкап текущего p29** (в нём может быть чужая сборка, 16.11 там был образ
Wi-Fi-сессии `d9a1f402…`).

```sh
# 1. бэкап текущего p29 и проверка
ssh root@10.42.66.66 'dd if=/dev/mmcblk0p29 bs=4M' > /tmp/opencode/p29_before.img
sha256sum /tmp/opencode/p29_before.img

# 2. прошивка проверенного образа (он же возвращает картинку)
tools/host/flash-ssh.sh build/it6112-resume/boot_resume_full.img /dev/mmcblk0p29 --reboot

# 3. после загрузки — 10 минут s2idle с будильником (без нажатия кнопки)
ssh root@10.42.66.66 'echo +620 > /sys/class/rtc/rtc0/wakealarm; systemctl suspend'

# 4. через ~11 минут: устройство должно само проснуться
ssh root@10.42.66.66 'dmesg | grep -E "suspend (entry|exit)|bridge re-initialised|MCLK=|started" | tail'

# 5. визуально: полос нет; скриншот KWin для сравнения
# 6. вернуть прежний p29
tools/host/flash-ssh.sh /tmp/opencode/p29_before.img /dev/mmcblk0p29 --reboot
```

Если RTC-будильник не сработает, будить кнопкой питания: код-путь resume от
этого не меняется, но длительность сна будет другой.

## Откат

- p29 v5 (до работы): `build/gauge/boot_gauge_v5.img`
  sha256 `2d1177c6d5c6e71b7cc4bf61bc79aec48d76730cee294d10c56414ee41a17861`,
  md5 `e8fe189611166c4d0246a8dced1f38c6`.
- Отключить восстановление без пересборки:
  добавить в cmdline `t1100.it6112_resume=none` и перепаковать boot.img.

## Ссылки

- `refs/device/it6112-regs-broken-2026-11-15.txt` — дамп «сломанного» моста;
- `refs/device/journal-it6112-resume-2026-11-15.txt.gz` — журнал boot -71
  (suspend 11:55:54, resume 11:57:40, оба прохода `bridge re-initialised`);
- `docs/it6112-vendor-init.md`, `docs/it6112-lk-init-re.md` — вендорская
  последовательность и RE LK;
- `docs/STATUS.md`, запись «15.11 (11): IT6112 resume fix (0074)» (коммит
  `9d6ad78`);
