# Задачи T1100

Обновлено: 14.11.2026. Текущий фокус — пункт 6 (мелочи).

## Приоритеты

1. **PD-зарядка и powered hub.** Проверить реальный PD-адаптер, ток,
   `t1100-charge.sh`, hub + USB host.
2. **Thermal soak + SVS.** 30–60 минут нагрузки 8 ядер, throttling;
   SVS/efuse — отдельно.
3. **Wi-Fi/BT (фаза 5).** M80: TX из MCU не уходит, линия прошивки в тупике,
   нужна архитектурная развилка.
4. **Panfrost.** Редкие `js fault` при старте KDE и shader-таймауты.
5. **Воспроизводимая сборка.** Clean mainline + вся `patches/series`,
   а не `merge3-src` + отдельные патчи.
6. **Мелочи (текущий).**
   - [x] 6.1 Постоянный PGA-гейн микрофона (патч 0068).
   - [x] 6.2 Точность индикации батареи (0069: вендорская OCV-таблица).
   - [ ] 6.2a Топливомер MT6358 (0072): драйвер собран и прошит, на железе не проверен (планшет отключён от USB).
   - [ ] 6.3 Длительный suspend/разряд/wakeup.
   - [x] 6.4 Гарнитура: ручное переключение speaker/headphones (авто-ACCDET — отдельный драйвер).

## 6.1 Микрофонный PGA — сделано

Проблема была в `mt6358_amic_disable()`: при закрытии capture он писал
PGA 0 dB, поэтому 4,4 (24 dB) действовали только до конца записи.

Патч 0068 убирает биты гейна из маски disable и сохраняет пользовательское
значение. Проверено на `boot_nonwifi_pga.img` (p29 md5 `ab00fd42…`):
после `arecord -D hw:0,1 ... -d 1` значение `PGA Volume` остаётся `4,4`,
сигнал ненулевой (`Maximum 0.0248`, `RMS 0.0063`).

## 6.2 Батарея — 0069 закрыт, 0072 ждёт проверки

Топливомера в mainline нет; `mt6370-battery` считает ёмкость по OCV.
Старая таблица завышала заряд в нижней части (3.8 В ≈ 50%, 3.7 В ≈ 40%).
Патч 0069 заменяет её на 21 точку вендорского MT6358 gauge (t2):
4.337 В/100 %, 4.195/90, 4.090/80, 3.975/70, 3.901/60, 3.833/50,
3.799/40, 3.776/30, 3.749/20, 3.697/10, 3.372/0.

Проверено на `boot_nonwifi_battery.img` (p29 md5 `0b64a8af…`):
при 3.77 В `capacity=27` (старая таблица дала бы ~43 %), статус
`Charging`. Интернет через `t1100-usb0` после reboot включается
вручную (`nmcli con up t1100-usb0`).

### 6.2a Минимальный порт MT6358 gauge (0072)

Проблема 0069: MT6370 меряет VBAT под нагрузкой, поэтому при снятии кабеля
проценты падают (~20 %), а на зарядке растут (~50 %) — это IR drop, а не
заряд. Патч 0072 добавляет MFD-ячейку `mediatek,mt6358-gauge` и драйвер
`drivers/power/supply/mt6358-gauge.c`:

- напряжение — BATADC MT6358 через mainline IIO (`mt6359-auxadc`),
  `raw 23280…23352 × 5400 / 32768 = 3836…3845 мВ` (проверено на auxadc-образе);
- ток — `FGADC_CUR_CON0` 0x0d8a через parent regmap (знаковый, 381.470 мкА/LSB,
  `r_fg=5`, `car_tune=100` из стокового DTS);
- OCV = VBAT − I·R(SOC), профиль `battery0_profile_t2` (100 троек) в board DTS;
- `mt6370-battery` берёт capacity/voltage/current из gauge, если он поднялся;
  старая таблица 0069 остаётся fallback;
- пороги `t1100-power-guard` 3.72/3.60 В не менялись.

Сборка: `Image` sha256 `18efb451…`, DTB `4f01d337…`.
Образ `build/boot_gauge.img` (v1) прошит в p29 (md5 `34db0025…`), но
**на железе не проверен**: планшет был отключён от USB и поставлен на
зарядку. v1 использует vendor latch-запись `FGADC_CON1`; в v2
(`build/boot_gauge_v2.img`, md5 `9d2bf057…`) она убрана, ток читается
простым `regmap_read`. Страховочный вариант без чтения FG —
`build/boot_gauge_nocurrent.img` (md5 `226f56e3…`).
Откат: `build/recovery/boot_a_before_gauge.img` (md5 `d401cf2d…`).


## 6.4 Гарнитура — сделано (manual)

3.5 мм jack физически есть и работает. В MT6358 нет автоматического jack-
детекта в mainline, поэтому переключение ручное:

```
amixer -c0 cset name="HPL Mux" 2
amixer -c0 cset name="HPR Mux" 2
amixer -c0 cset name="Speaker Switch" off
amixer -c0 cset numid=78 12
```

Обратно: `Speaker Switch on`, `HPL/HPR Mux` = 1 (LoudSPK Playback).
Патчи 0070/0071 добавляют в machine driver DAPM `Headphone Jack`/`Speaker`,
`Speaker Switch` и gating amp GPIO по DAPM-пути Speaker; проверено на
`boot_nonwifi_amp.img` (p29 `61e08a8b…`), пользователь подтвердил: при
`Speaker Switch=off` динамик молчит, звук идёт в наушники.

Автоматический детект требует порта вендорского ACCDET MT6771; исходник
найден, но драйвер не реализован.

### UI «Аудиовыход»

Добавлено отдельное окно `t1100-audio-ui` (KDialog): две кнопки
«Наушники»/«Динамик». Скрипт вызывает `amixer` и переключает
`HPL/HPR Mux` и `Speaker Switch`. Зависимость — пакет `kdialog`
(установлен из apt). Проверено пользователем.

### UI «USB режим»

Отдельное KDialog-приложение `/usr/local/bin/t1100-usb-ui` (`.desktop` —
`USB режим`) с кнопками «USB host (флешка)» и «USB device (кабель)».
Host вызывает `/usr/local/sbin/t1100-usb-role host` (RNDIS/SSH пропадают,
планшет питает USB-устройство); device возвращает peripheral/RNDIS и
размонтирует `/dev/sd*`. KDialog установлен на планшет.
