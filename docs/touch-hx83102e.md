# HX83102E: протокол по стоковому драйверу (v2, AHB-протокол и sense-цикл)

Документ отвечает на вопросы «какие i2c-транзакции слать, в каком порядке, что
читать» для in-cell дигитайзера **HX83102E** (BOE TV110XUM-LB2, i2c0 0x48,
EINT 1, reset GPIO158, `ts-avdd` GPIO163).

Всё ниже — из **дизассемблированного вендорского драйвера** стокового ядра
4.14.186 (`../t1100/backup_5.1.6.110/boot_a_5.1.6.110.img`), с указанием
адресов функций и конкретных инструкций. Где вывод не доказан — так и написано
(§6).

> v1 этого документа содержал две ошибки, найденные при повторном разборе:
> (1) путь чтения кадра для 83102E — **другой** callback, чем у остальных IC
> (`0xA9A450`, а не `0xA95DAC`), и он **не** пишет `0x11 = 0` перед чтением;
> (2) «AHB-запись» в v1 была описана правдоподобно, но не по коду. Точный
> протокол — §1.

---

## 0. Методика и адреса

| | |
|---|---|
| образ | `boot_a_5.1.6.110.img`, `ANDROID!`, kernel gzip 10 311 313 Б @2048 |
| распаковано | `Image` 27 453 440 Б, Linux **4.14.186**, MT6771 |
| инструмент | `capstone` 5.0.9 |
| символика | kallsyms из `.rodata`: token_table @0x117FA00, token_index @0x117FE00, names @0x10CA600 (57 450 имён), markers @0x117F200 |

Смещения — файловые (VA − `0xffff000008080000`).
Таблица `kallsyms_offsets` в образе (0x10922A4) — от **другой линковки**
(значения занижены на 0x2300…0x6800), не использовать. Функции опознавались по
их `__func__`-строкам и по таблице указателей, которую драйвер строит сам
(`0x20FB720…0x20FBA08`), плюс по `himax_hx83102e_func_re_init`, который
переопределяет слоты для 83102E.

Проверенные адреса:

| адрес | функция / объект |
|---|---|
| 0xA92E78 | `himax_mcu_in_cmd_struct_init` — аллокация буферов, сборка таблицы операций |
| 0xA9336C | `himax_mcu_in_cmd_init` — **карта суб-адресов и команд IC** (§1.4) |
| 0xA994C8 | `himax_hx83102e_reg_re_init` — переопределения 83102E |
| 0xA99544 | `himax_hx83102e_func_re_init` — подмена слотов операций (в т.ч. чтения кадра) |
| 0xA98D6C | `_hx83102_init` — reset → sense_off → chip_detect |
| 0xA99AE0 | `hx83102e_chip_init` |
| 0xA9A068 | **`hx83102e_sense_on`** |
| 0xA9A1BC | **`hx83102e_sense_off`** |
| 0xA9A450 | **чтение кадра 83102E** (слот `[0x20FB830]`) |
| 0xA9A69C | `himax_parse_assign_cmd` (LE-упаковка) |
| 0xA9E278 | `himax_bus_read` |
| 0xA9E400 | `himax_bus_write` |
| 0xA940A8 | `himax_mcu_register_write` (AHB write) |
| 0xA99598 | `hx83102_register_read` (AHB read) |
| 0xA9E5CC | `himax_int_enable` |
| 0xA9E8C8 | `himax_ts_register_interrupt` |
| 0xA9C318 | `himax_touch_get` (валидация кадра) |
| 0xA97E40 | `himax_mcu_pin_reset` |
| 0xA97EB0 | `himax_mcu_ic_reset` |
| 0xA95ADC | `himax_mcu_reload_disable` |
| 0xA96318… | `himax_mcu_assign_sorting_mode` |

---

## 1. Транспорт: точный протокол (доказано кодом)

### 1.1. Примитивы

`himax_bus_read(u8 sub, u8 *buf, int len)` @0xA9E278 — **один** `i2c_transfer`
из двух сообщений:

```
msg0: addr=client, flags=0,       len=1,      buf=&{sub}     // 1 байт суб-адреса
msg1: addr=client, flags=I2C_M_RD, len=len,   buf=<static>   // чтение
```
(`strh w9,[sp,#0x1a]` с `w9=1` = `I2C_M_RD`; `stur w9,[sp,#0xa]` c `w9=0x10000`
задаёт `msg0.len = 1`.) `len ≤ 0x100`, 3 попытки, при провале
`"[HXTP][ERROR] %s: i2c_read_block retry over 3"`.

`himax_bus_write(u8 sub, u8 *addr4, u8 *data, int len)` @0xA9E400 — **одна**
i2c-запись, буфер собирается так:

```
out[0]      = sub
если addr4: out[1..4] = *(u32*)addr4        (LE), смещение := 5, len -= 4
если data : memcpy(out + offset, data, len)
передаётся len+1 байт (len — суммарный payload; len ≤ 0xFC)
```

Ключевое: `addr4` — это **указатель на 32-битное слово адреса**, а не сами
байты; слово кладётся `stur w9,[x8,#1]`, т.е. little-endian.

### 1.2. AHB-запись — одна транзакция из 9 байт

`himax_mcu_register_write(addr_ptr, data_ptr, len)` @0xA940A8:
`himax_mcu_burst_enable(len >= 5)` (слот `[0x20FB720]` = 0xA93EAC), затем
`hx83102_register_write`. Последняя @0xA98D14 — целиком:

```
a98d1c mov x2, x1     ; x2 = data
a98d20 mov x1, x0     ; x1 = addr
a98d24 mov w3, #8     ; len = 4 (addr) + 4 (data)
a98d28 mov w0, wzr    ; sub = 0x00
a98d2c bl  himax_bus_write
```

⇒ на шине (пример: `0x9000005C = 0x000000A5`):

```
S 0x48 W  00  5C 00 00 90  A5 00 00 00  P
          ^sub  ^addr (LE)   ^data (LE)
```

**Никаких отдельных записей в 0x0C / 0x08 при записи нет** — это одна
i2c-транзакция. Именно поэтому попытка `0x00=адрес → 0x0C=0x1 → 0x08=0xA5`
не могла сработать: `0x0C` — регистр направления доступа (0 = read),
а `0x08` — порт чтения данных.

Burst-преамбула (`himax_mcu_burst_enable` / `hx83102_burst_enable` @0xA98C70)
— две отдельные 2-байтные записи:

```
S 0x48 W  13 31  P        // HIMAX_AHB_ADDR_CONTI = 0x13, команда 0x31
S 0x48 W  0D 10  P        // HIMAX_AHB_ADDR_INCR4 = 0x0D, команда 0x10|auto_add
```

### 1.3. AHB-чтение — три транзакции

`hx83102_register_read(u32 *addr, u8 *out)` @0xA99598 (то же самое inline в
`_hx83102_init`):

```
1) S 0x48 W  13 31  P                     // burst on (CONTI = 0x31)
2) S 0x48 W  0D 10  P                     // INCR4 = 0x10
3) S 0x48 W  00 5C 00 00 90  P            // addr в порт 0x00 (LE, 4 байта)
4) S 0x48 W  0C 00  P                     // ACCESS_DIRECTION = read
5) S 0x48 W  08  Sr 0x48 R <4 байта> P    // чтение из порта 0x08
```

Это ровно те константы, что и в mainline-драйвере
(`HIMAX_AHB_ADDR_BYTE_0 0x00`, `RDATA 0x08`, `ACCESS_DIRECTION 0x0c`,
`INCR4 0x0d`, `CONTI 0x13`) — то есть **AHB-путь в mainline уже правильный**.

### 1.4. Карта суб-адресов (`himax_mcu_in_cmd_init` @0xA9336C)

Драйвер собирает её байт за байтом (`himax_parse_assign_cmd`, LE) в
`0x20FB6C0` (40 Б). Восстановленное содержимое:

```
bufA: 00 08 0C 13 0D 31 32 00 31 10 27 95  [20 00 02 80]  ...  [A0 00 00 90]  [A8 00 00 90]  [A8 80 08 90]
      ^0x00 ^0x08 ^0x0C ^0x13 ^0x0D ...                    0x900000A0     0x900000A8     0x900880A8
```

| суб-адрес | смысл |
|---|---|
| `0x00` | **порт AHB**: адрес (4 Б LE) + данные |
| `0x08` | порт **чтения** данных AHB |
| `0x0C` | направление доступа (0x00 = read) |
| `0x13` | CONTI / burst-команда (0x31) |
| `0x0D` | INCR4 (0x10 \| auto_add) |
| `0x31`, `0x32` | служебные строб-регистры (см. §2.2) |
| `0x11` | сброс указателя кадра (используется только generic-путём, §3.1) |
| `0x30` | **блок отчёта (кадр)**, читается burst’ом |

Второй буфер (`0x20FB6C8`, 0xD1 Б) — таблица адресов/данных для sense-цикла:

```
+0x04 = 0x9000005C     ← «sense on/off» команда
+0x08 = 0x900000E4     ← версия/статус
+0x18 = 0x08000000
+0x48 = 0x10007088
+0x4C = 0x900000D0     ← ICID
+0x6C = 0x900000A8     ← «FW reload done»
+0x80 = 0xA55AA55A
+0x94 = 0x00000000     ← данные для sense ON
+0x98 = 0x000000A5     ← данные для sense OFF
+0xC3 = 0x11, +0xC4 = 0x00, +0xC5 = 0x01, +0xC6 = 0x30   ← только generic-путь кадра
```

---

## 2. Полный sense-цикл

### 2.1. Где он в потоке инициализации (dmesg стока)

```
1.418  himax reset over
1.418  _hx83102_init
1.504  hx83102_sense_off: cnt = 0, data[0] = 0xA5!
1.532  hx83102_sense_off: cnt = 1, data[0] = 0x87!
1.533  hx83102_sense_off: Check enter_save_mode data[0]=C
1.537  chip_detect:Read driver IC ID = 83,10,2E   → 0x83102E
1.539  hx83102e_chip_init:IC cell type = 1, RX 48, TX 32, MAX_PT 10, 1600x2176
1.539  himax_ts_register_interrupt / himax_int_enable: enable = 0
1.742  hx_chk_flash_sts: Entering, 131072 ; himax_mcu_calculateChecksum
1.846  himax_mcu_flash_lastdata_check: size 131072, start 0x0001FF80
1.850  FLASH[0001FFFC] ~ FLASH[0001FFFF] = 9392FD9F
1.850  himax_mcu_reload_disable: entering / setting OK!
1.851  himax_mcu_assign_sorting_mode: addr 0x10007F04, write 0x00000000
1.855  Enter hx83102e_sense_on                      ← §2.3
1.868  himax_mcu_ic_reset,status: loadconfig=0,int_off=0
1.868  himax_mcu_pin_reset: Now reset the Touch chip.  (gpio 0 → gpio 1)
1.923  himax_mcu_power_on_init: waiting for FW reload data
1.989  himax_mcu_power_on_init: FW reload done
2.004  himax_int_enable: enable = 1
```

То есть чип **всю инициализацию проводит в save-режиме** (sensing выключен) и
включается только на шаге `sense_on` в самом конце, после чего драйвер
переразрешает прерывание. Это соответствует наблюдаемому: ICID и FW-статус
читаются, счётчики в `0x38…0x3F` тикают, а блок отчёта `0x30` — нули.

### 2.2. `hx83102e_sense_off(int arg)` @0xA9A1BC (доказано)

```
HX_TP_LOG("Enter %s", "hx83102e_sense_off")            // не логируется? (см. ниже)
for (cnt = 0; cnt < 0x22; cnt++) {
    if (cnt == 0 || last == 0 || last == 0xA5)
        AHB_write(0x9000005C, 0x000000A5);             // bufB+0x98 = 0xA5
    usleep_range(10000, 10001);                        // 10 мс
    AHB_read (0x900000A8, &st);                        // bufA+0x18
    if (st[0] != 0x05) { log "not 5"; continue; }
    AHB_read (0x9000005C, &st);                        // читаем назад
    log "cnt = %d, data[0] = 0x%02X!"
    if (st[0] == 0x87) break;
}
for (i = 0; i < 6; i++) {                              // «Check enter_save_mode»
    write(0x31, {0x27}, 1);                            // bufA[0xa]
    write(0x32, {0x95}, 1);                            // bufA[0xb]
    AHB_read(0x900000A8, &st);
    log "Check enter_save_mode data[0]=%X"
    if (st[0] == 0x0C) break;
    usleep_range(5000, 5001);
    himax_int_enable(0); msleep(20); himax_int_enable(1); msleep(50);
}
if (st[0] == 0x0C)
    AHB_write(0x80020004, 0x00000000);                 // «выйти из save/flash access»
    usleep_range(1000, 1001);
    return 1;
return 0;
```

Байтовый вид первой записи (то, что раньше ломало эксперимент):

```
S 0x48 W  13 31 P           // burst on
S 0x48 W  0D 10 P
S 0x48 W  00 5C 00 00 90 A5 00 00 00 P        ← вот это и есть «sense off»
```

Ожидаемая реакция: `AHB 0x900000A8 → 0x05`, чтение назад
`AHB 0x9000005C → 0x87`, затем `0x900000A8 → 0x0C` (лог `data[0]=C`).

### 2.3. `hx83102e_sense_on(int arg)` @0xA9A068 (доказано)

```
HX_TP_LOG("Enter %s", "hx83102e_sense_on")
ops[+0x08]()                                   // 0xA941B0: burst enable + handshake
ops[+0x00](&bufB[0x04], &bufB[0x94], 4)        // AHB_write(0x9000005C, 0x00000000)
usleep_range(10000, 11000)                     // 10 мс
if (arg) {                                     // «мягкий» вариант
    write(0x31, {0x00}, 1);
    write(0x32, {0x00}, 1);
} else {                                       // то, что делает сток при загрузке
    himax_mcu_ic_reset(0, 0);                  // 0xA97EB0
}
```

`himax_mcu_ic_reset` → `himax_mcu_pin_reset` @0xA97E40:

```
HX_TP_LOG("himax_mcu_pin_reset: Now reset the Touch chip.")
himax_int_enable(ts, 0);
<reset GPIO158: низкий>
usleep_range(5000, 5100);
<reset GPIO158: высокий>
himax_int_enable(ts, 1);
usleep_range(50000, 50100);                    // 50 мс
```

после чего `himax_mcu_power_on_init` опрашивает `0x10007F40` / `0x900000A8` /
`0x900000E8` / `0x900000E4` (4 раза по 10 мс), пока `0x900000A8 != 0x05`.

**Итог:** «включение выдачи кадров» = запись `AHB 0x9000005C = 0x00000000`,
10 мс, затем сброс чипа по GPIO158 и ожидание `0x900000A8 == 0x05`.
Сток подтверждает это логом 1.855 → 1.868 → 1.923 (см. §2.1). Отдельного
«enable reporting» регистра в коде нет.

Байтовый вид:

```
S 0x48 W  13 31 P
S 0x48 W  0D 10 P
S 0x48 W  00 5C 00 00 90 00 00 00 00 P        ← sense ON
(10 мс)
GPIO158: 0 → 1, 50 мс
опрос: 00 A8 00 00 90 / 00 0C 00 / чтение 08 → ждём 0x05
```

### 2.4. `himax_mcu_reload_disable(int)` @0xA95ADC

```
log "himax_mcu_reload_disable:entering"
AHB_write(addr = buf(0x2B)+0, data = arg ? buf+0x1B : buf+0x1F, 4)
log "himax_mcu_reload_disable: setting OK!"
```

Адрес берётся из первого 4-байтного слова буфера `0x20FB6D8` (0x2B Б);
в статике он не заполняется ни `in_cmd_init`, ни `reg_re_init` — то есть
**адрес недоказан** (§6). Данные: `[0x1B] = 5A A5 00 00`, `[0x1F] = 00 00 00 08`
(после override 83102E: `[0x18] = 0x30`, `[0x19] = 0x1E`).

`himax_mcu_assign_sorting_mode` пишет `AHB 0x10007F04 = 0x00000000` — это
видно прямо в логе стока (1.851), значение доказано.

---

## 3. Кадр касаний

### 3.1. Как читает 83102E (`[0x20FB830]` = **0xA9A450**)

`himax_hx83102e_func_re_init` @0xA9958C записывает `0xA9A450` в слот
`[0x20FB830]` (база операций `0x20FB740`, смещение `+0xF0`). Реализация
@0xA9A450 целиком:

```
if (debug&4) t0 = ktime_get();
himax_bus_read(bufB[0xC6] /* = 0x30 */, buf, len);
if (debug&4) { ... ts->perf = ... }
return 1;
```

**Никакой записи в `0x11` здесь нет.** Запись `0x11 = 0x00` + чтение `0x30`
принадлежит *generic* callback’у `0xA95DAC` (слот по умолчанию), которым
пользуются другие IC; для 83102E он перекрыт. Это исправление v1.

Итого для 83102E чтение кадра — обычное регистровое чтение с автоинкрементом:

```
S 0x48 W  30  Sr 0x48 R <56 байт> P
```

`himax_bus_read` при `len > 4` сам включает burst (`0x13=0x31`, `0x0D=0x10`),
поэтому отдельно его слать не обязательно, но и не вредно.

Длина: `himax_touch_get(ts, type)` @0xA9C318 берёт `len = ts->touch_info_size`
(= 56) для type 1 и `0x80` для type 3.

### 3.2. Размер и раскладка

`himax_report_data_init` @0xA9AAD8:

```
hx_raw_cnt_max  = touch_info / 4
rem             = touch_info % 4
touch_info_size = 4 * (HX_MAX_PT + hx_raw_cnt_max) + (rem ? 8 : 4)   [+0x0C при stylus]
```

При `HX_MAX_PT = 10`, `hx_raw_cnt_max = 2`: `4*12 + 8 = 56`.

Раскладка, которую использует mainline (`struct himax_event`, `__packed`,
`static_assert(sizeof == 56)`), и которая совпадает с формулой вендора
(10 точек × 4 Б = 40, далее 2 «слов» + 8 байт):

| смещение | поле |
|---|---|
| 0..39 | `points[10]`: по 4 Б — `__be16 x`, `__be16 y` |
| 40..49 | `majors[10]` — «сила»/площадь по точкам |
| 50..51 | pad |
| 52 | `num_points` (0xFF → 0 точек; иначе `& 0x0f`) |
| 53..54 | pad |
| 55 | `checksum_fix` |

Вендорская валидация в `himax_touch_get` (0xA9C5E4…0xA9C7D0) отличается от
mainline и объясняет, почему «сумма всех 56 байт» может не сходиться:

* контрольная сумма — **16-битная сумма байт до первого нулевого байта**
  (`ldrb w13,[x11],#1; cbz; add w13,w2,w13; and w2,w13,#0xffff`), а не сумма
  всех 56 байт;
* байты `0xEB`, `0xEC`, `0xED` считаются служебными кодами (счётчики
  «exception»), байт с `(b >> 4) == 0xF` — маркером/терминатором;
* при «исключительном» кадре печатается
  `TP] EXCEPTION event checked - ALL Zero.`

**Что означает «нет касаний»:** у вендора пустой отчёт — это кадр, который
целиком нулевой (все точки и `num_points` = 0); mainline трактует `0xFF` в
`num_points` как «точек нет». Наблюдаемые нули в `0x30` — это **не** «нет
касаний», а отсутствие отчёта вообще (sensing выключен, §2).

### 3.3. Почему AHB `0x30` не подходит

`regmap_raw_read(reg=0x30, 56)` в mainline отправляет 4-байтный адрес в порт
`0x00` (`00 30 00 00 00`), затем `0C 00`, затем читает 4/56 байт из `0x08` —
то есть обращается к **AHB-адресу 0x00000030**. Вендор же читает **регистр
0x30** восьмибитного пространства (`S W 30` + чтение). Это разные места.

---

## 4. Прерывание и «тик 1 Гц»

DTS стока (`himax_touch@48`): `interrupts = <1 1 1 0>` (EINT 1, edge),
`debounce = <1 0>`; dmesg: `himax_touch_irq=19d` (GPIO 413), `irq enabled at
qpio: 19`, `ints[0] = 1, ints[1] = 0`.

`himax_ts_register_interrupt` @0xA9E8C8: `gpio_set_debounce(2)`,
`gpio_to_irq()`, затем `request_threaded_irq(irq, …)` с флагами
`0x2002 = IRQF_ONESHOT|IRQF_TRIGGER_FALLING`, при неудаче
`0x2008 = IRQF_ONESHOT|IRQF_TRIGGER_LOW`. `HX_INT_IS_EDGE = 1` из touch info
подтверждает edge. Отдельного «enable»-регистра в чипе нет: `himax_int_enable`
@0xA9E5CC управляет только локальной маской (`enable_irq/disable_irq` +
флаг).

**Про 1 Гц.** В таблице `refs/device/interrupts.txt` на `mt-eint 1` висит
ровно одно устройство — `himax_touch`:

```
19: 648 533 594 532 219 156 171 138   mt-eint 1  Edge  himax_touch
```

Сумма по CPU = 2991. Аптайм того же дампа ≈ 6380 с (`dmesg-stock` заканчивается
на 6378 с, `arch_timer` ≈ 578k на CPU при HZ=100). Итого ≈ **0.5 Гц
прерываний без касаний — в стоке тоже**. Значит это не «постороннее
устройство на линии», а сам чип: прошивка периодически дёргает INT, вендор на
каждое прерывание безусловно читает кадр (`himax_ts_work` → `himax_touch_get`
→ callback `0x30`) и, получив пустой отчёт, просто выходит.

Практический вывод: тик 1 Гц — не баг и не индикатор проблемы; он не мешает
получать кадры, если чип в sense-on и чтение идёт из правильного места.
Единственное, что стоит проверить отдельно, — bias/pull на линии EINT 1
(в mainline pin без bias).

---

## 5. Что должен сделать bringup (по шагам)

После штатного сброса и `ICID == 0x83102e`, `0x900000A8 == 0x05`:

```
1) AHB_write 0x9000005C = 0x00000000        // sense ON
2) usleep 10 мс
3) IC reset: int_disable; GPIO158 0→1; usleep 5 мс; int_enable; usleep 50 мс
4) ждать 0x900000A8 == 0x05 (до 4 раз по 10 мс; при неудаче — повторить §2.2/§2.3)
5) на IRQ: burst (0x13=0x31, 0x0D=0x10) + чтение регистра 0x30, 56 байт
6) разбор: points[10] по 4 Б (be16 x, be16 y) @0..39, majors @40..49,
   num_points @52 (0xFF = нет точек), checksum @55
   либо, до подтверждения раскладки: hexdump и сверка с §6
```

Проверка, что sense-on действительно сработал (**новый диагностический шаг,
которого не было в v1**): после шага 1 прочитать `AHB 0x9000005C` — в
save-режиме там `0x87`, после sense-on ожидается `0x00` (симметрично тому, как
sense_off проверяет `0x87`). Это дешёвый и однозначный индикатор состояния
чипа.

Чего в mainline нет (обновлённый список):

1. `AHB 0x9000005C = 0` + повторный сброс и ожидание FW reload — **главное**;
2. запись `0x10007F04 = 0` (sorting mode) перед sense_on;
3. `reload_disable` (адрес недоказан, §6) — вероятно, можно пропустить;
4. чтение кадра из **регистра** `0x30` (8-битный суб-адрес), а не из AHB `0x30`;
5. 16-битная сумма «до первого нуля» вместо суммы всех 56 байт;
6. `0x11 = 0x00` **не нужен** для 83102E (это generic-путь) — из v1 убрать.

---

## 6. Что осталось недоказанным

1. **Адрес в `himax_mcu_reload_disable`.** Берётся из `buf(0x2B)[0..3]`, но ни
   `in_cmd_init`, ни `himax_hx83102e_reg_re_init` его не заполняют в статике
   (возможно, заполняется путём, который не попал в разбор, либо это
   неинициализированная область — вызов может быть no-op). На кадры не влияет.
2. **Раскладка 56 байт именно для 83102E.** Совпадение размера (56) и формула
   вендора `4*(MAX_PT+raw)+8` сходятся с `struct himax_event`, но вендорская
   валидация использует другие смещения (`ts->touch_info_size-0xF` и `-3`), что
   с mainline-раскладкой не сходится. Проверять эмпирически (§7).
3. **Смысл `0x9000005C` и необходимость сброса после него.** По коду: запись
   0 → 10 мс → IC reset. Сток подтверждает порядок, но не объясняет, почему
   команда переживает сброс (возможно, это флаг во flash-конфиге FW).
4. **Ветка `sense_on(arg != 0)`** (два строба `0x31=0`, `0x32=0` без сброса) — в
   стоке не используется (там arg=0), назначение не проверено.
5. **Вендорский ISR** может отбрасывать часть прерываний по счётчику
   (`himax_ts_work` @0xA9C1A0, ветка «Skipit»); влияние на поведение при
   дребезге не разбиралось.

---

## 7. Минимальный эксперимент (без прошивки)

На живой плате, после сброса и `0x900000A8 == 0x05`:

1. `AHB_read 0x9000005C` → записать (ожидание `0x87` = save mode);
2. `AHB_write 0x9000005C = 0` (9 байт, §1.2);
3. `usleep 10 мс`, `AHB_read 0x9000005C` → ожидание `0x00`;
4. `S W 30` + чтение 56 байт → в покое кадр нулевой, при касании — меняющиеся
   4-байтные записи;
5. если после шага 3 всё ещё `0x87` — повторить §2.2 (полный sense_off, до
   `data[0] = 0xC`) и затем §2.3.

Если кадр пошёл, но раскладка не сходится с mainline — снять 3 дампа: покой,
одно касание в известной точке (например, левый верхний угол), два касания.
По смещению ненулевых байт раскладка определится однозначно.
