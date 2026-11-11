# HX83102E: протокол, init-таблица и раскладка кадра (v3)

Документ отвечает на вопросы «какие i2c-транзакции слать, в каком порядке, что
читать» для in-cell дигитайзера **HX83102E** (BOE TV110XUM-LB2, i2c0 0x48,
EINT 1, reset GPIO158, `ts-avdd` GPIO163).

Источники: (1) **дизассемблированный вендорский драйвер** стокового ядра
4.14.186 (`../t1100/backup_5.1.6.110/boot_a_5.1.6.110.img`) — адреса функций и
инструкций; (2) **публичный GPL-исходник** того же драйвера
(`MorgenYang/himax_v2_common`, коммит `106bb96`) — init-последовательность,
карта адресов и раскладка кадра (§8). Где вывод не доказан — так и написано
(§6).

> v1 документа содержал две ошибки, найденные при повторном разборе:
> (1) путь чтения кадра для 83102E — **другой** callback, чем у остальных IC
> (`0xA9A450`, а не `0xA95DAC`), и он **не** пишет `0x11 = 0` перед чтением;
> (2) «AHB-запись» в v1 была описана правдоподобно, но не по коду. Точный
> протокол — §1.
>
> v3: раскладка кадра и checksum подтверждены исходником (§3.2, §8.4),
> добавлен полный порядок «перед первым кадром» (§5, §8.3).

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

Раскладка **подтверждена вендорским исходником** (§8.4) и совпадает с
mainline `struct himax_event` (`__packed`, `static_assert(sizeof == 56)`):

| смещение | поле | как читает вендор |
|---|---|---|
| 0..39 | `points[10]` — по 4 Б: `be16 x`, `be16 y` | `x = buf[i*4]<<8 \| buf[i*4+1]`, `y = buf[i*4+2]<<8 \| buf[i*4+3]` |
| 40..49 | `majors[10]` — «сила»/площадь | `w = buf[nFinger_support*4 + i]` |
| 50 | — | (не используется) |
| 51 | `ig_count` | `buf[coordInfoSize - 5]` |
| 52 | `num_points`: младший ниббл — число точек (`0xFF` → 0), старший — `raw_data_sel` | `buf[coordInfoSize - 4] & 0x0F`; `buf[52]>>4 & 0x0F` |
| 53..54 | — | |
| 55 | `checksum` | сумма всех 56 байт ≡ 0 (mod 256) |

Правила валидации (исходник, §8.4):

* **checksum**: `for (i=0;i<len;i++) check_sum_cal += buf[i];` и требуется
  `check_sum_cal % 0x100 == 0` — сумма **всех** `touch_info_size` байт, как в
  mainline. (В v1 я записал сюда «16-битную сумму до первого нуля» — это был
  артефакт дизассемблера, в исходнике такого нет.)
* кадр, целиком состоящий из нулей (`zero_cnt == length`), отбрасывается
  («All Zero event»);
* `raw_data_sel = buf[52] >> 4 & 0x0F`; если он не `0x0F` и не равен
  `diag_cmd`, кадр считается raw-данными и отбрасывается (стек при этом
  дочитывается: `fp_read_event_stack(buf, 128 - touch_info_size)`);
* точка валидна, если `0 <= x <= abs_x_max` и `0 <= y <= abs_y_max`;
  `hx_point_num == 0` → отчёт не формируется вообще;
* байты `0xEB/0xEC/0xED` в `himax_ts_event_check` считаются кодами
  исключений (ESD/шум), `0xED` — «shaking».

**«Нет касаний»** = валидный кадр с `buf[52] & 0x0F == 0` (или `0xFF`).
Наблюдаемый у нас кадр `14 × 00 03 00 00` по этой раскладке означает:
`x = 0x0003, y = 0x0000` во всех 10 точках, `buf[52] = 0x00` → **точек 0**,
при этом checksum (14 × 0x03 = 0x2A) не сходится. То есть чип отдаёт не
отчёт, а фиксированный шаблон.

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

Вендорский `himax_mcu_power_on_init` (§8.3) задаёт точный порядок «перед первым
кадром». Для нас он разворачивается так (после сброса и `ICID == 0x83102e`):

```
0) прочитать touch info (RX/TX/max_pt/res) — из него размер кадра 56
1) AHB_write 0x100072EC = 0x00000000        // addr_raw_out_sel — «обычный» вывод
2) AHB_write 0x10007F04 = 0x00000000        // assign_sorting_mode (DSRAM)
3) AHB_write 0x9000005C = 0x00000000        // sense ON (fw_data_clear)
4) usleep 10 мс
5) IC reset: int_disable; GPIO158 0→1; usleep 5 мс; int_enable; usleep 50 мс
6) reload_to_active: писать AHB 0x90000048 = 0xEC, 1 мс, читать назад,
   пока не (data[1] == 0x01 && data[0] == 0xEC) — до HIMAX_REG_RETRY_TIMES
7) ждать 0x900000A8 == 0x05
8) на IRQ: burst (0x13=0x31, 0x0D=0x10) + чтение регистра 0x30, 56 байт
9) разбор по §3.2: points[10] be16 x/y @0..39, majors @40..49,
   num_points @52 (0xFF = нет точек), checksum — сумма всех 56 ≡ 0
```

Проверка, что sense-on действительно сработал: после шага 3 прочитать
`AHB 0x9000005C` — в save-режиме там `0x87` (см. §2.2), после sense-on
ожидается `0x00`.

Чего в mainline нет (обновлённый список, по вендорскому коду):

1. **`AHB 0x100072EC = 0`** (`addr_raw_out_sel`) — голая настройка вывода;
   без неё чип может отдавать raw-данные вместо точек;
2. **`AHB 0x10007F04 = 0`** (`assign_sorting_mode`, `fw_addr_sorting_mode_en`);
3. **`AHB 0x9000005C = 0`** + повторный сброс + `reload_to_active`
   (`0x90000048 = 0xEC`) — собственно sense-on;
4. **проверка `0x900000A8 == 0x05`** после сброса (FW reload done);
5. чтение кадра из **регистра** `0x30` (8-битный суб-адрес, burst), а не из
   AHB `0x30`;
6. `0x11 = 0x00` **не нужен** для 83102E (это generic-путь) — из v1 убрать.

Дополнительно, если понадобится полный «вендорский» цикл (для отладки):
`sense_off` = `0x9000005C = 0xA5` + `0x31=0x27`, `0x32=0x95` (×2), проверка
`0x900000A8 == 0x0C`, затем `AHB 0x80020004 = 0` (reset TCON) — §2.2.

---

## 6. Что осталось недоказанным

1. **Почему кадр `14 × 00 03 00 00`.** По раскладке это «0 точек» с
   неверной контрольной суммой; ни один из проверенных путей (регистр 0x30,
   AHB 0x30) такого давать не должен. Гипотезы: (а) чип остаётся в
   raw-out/ином режиме, потому что не сделаны шаги 1–3 из §5; (б) читается не
   тот порт/длина; (в) буфер не заполняется, а сохраняет предыдущее
   содержимое. Проверяется шагами §5 + hexdump.
2. **Адрес в `himax_mcu_reload_disable`** (4.14-бинарь): берётся из
   `buf(0x2B)[0..3]`, который в статике не заполняется. В v2-исходнике
   `fp_reload_disable` есть, но к 83102E напрямую не привязан. На кадры,
   по всем признакам, не влияет.
3. **`reload_to_active`** (`0x90000048 = 0xEC`, ожидание `data[1]==0x01 &&
   data[0]==0xEC`) — в нашем бинаре этой последовательности я не нашёл
   (возможно, она есть в другой ветке кода). Стоит проверить на железе.
4. **Ветка `sense_on(arg != 0)`** (FlashMode) — в стоке не используется.
4. **Ветка `sense_on(arg != 0)`** (FlashMode: safe-mode release + `0x31/0x32`)
   в стоке не используется (там arg=0), назначение не проверено.
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

---

## 8. Вендорский исходник (GPL): init-таблица и раскладка кадра

### 8.1. Что найдено

| | |
|---|---|
| репозиторий | `https://github.com/MorgenYang/himax_v2_common` |
| коммит | `106bb9614d169e008565c013f7ce0ec110b9646a` (2019-08-09, «modify coding style») |
| лицензия | GPL-2.0 (`SPDX-License-Identifier: GPL-2.0` в каждом файле) |
| объём | 1.3 МБ, только `hxchipset/` |
| файлы | `hxchipset/himax_ic_HX83102.c` (1915 строк), `himax_ic_HX83102.h`, `himax_ic_core.h` (карта адресов), `himax_ic_incell_core.c` (общее ядро), `himax_common.c` (разбор кадра) |

Локальная копия двух ключевых файлов: `refs/himax-v2/himax_ic_HX83102.{c,h}`.

Это **та же кодовая база**, что и в стоковом ядре: все константы совпадают с
тем, что было восстановлено дизассемблером, — `hx83102e_fw_addr_raw_out_sel =
0x100072EC`, `hx83102e_ic_adr_tcon_rst = 0x80020004`,
`fw_data_safe_mode_release_pw_active = 0x53`, `fw_addr_ctrl_fw = 0x9000005C`,
`fw_data_fw_stop = 0xA5`, `fw_addr_chk_fw_status = 0x900000A8`,
`fw_addr_fw_dbg_msg_addr = 0x10007F40`, `fw_addr_sorting_mode_en = 0x10007F04`,
`fw_addr_event_addr = 0x30`, пароль `0x31=0x27 / 0x32=0x95`.
Отличие: в репозитории — «модульная» v2-раскладка (`kp_*`, `g_core_fp`), в
нашем стоке — монолитная 4.14; логика и константы идентичны.

### 8.2. Карта адресов (`himax_ic_core.h`, блок `CORE_FW`)

```c
#define fw_addr_system_reset         0x90000018
#define fw_addr_safe_mode_release_pw 0x90000098   /* data 0x53 = release */
#define fw_addr_ctrl_fw              0x9000005c   /* sense on/off, data_clear=0 / fw_stop=0xA5 */
#define fw_addr_flag_reset_event     0x900000e4
#define fw_addr_hsen_enable          0x10007F14
#define fw_addr_raw_out_sel          0x800204b4   /* переопределяется для 83102e: 0x100072EC */
#define fw_addr_program_reload_to    0x08000000
#define fw_addr_reload_status        0x80050000
#define fw_data_clear                0x00000000
#define fw_data_fw_stop              0x000000A5
#define fw_addr_icid_addr            0x900000d0
#define fw_addr_fw_dbg_msg_addr      0x10007f40
#define fw_addr_chk_fw_status        0x900000a8
#define fw_addr_ahb_addr             0x11        /* ahb_dis=0x00, ahb_en=0x01 */
#define fw_addr_event_addr           0x30        /* блок отчёта */
#define fw_addr_sorting_mode_en      0x10007f04
#define fw_addr_cs_central_state     0x900000a8  /* он же chk_fw_status */
```

`himax_ic_HX83102.h`: `hx83102e_fw_addr_raw_out_sel 0x100072EC`,
`hx83102e_ic_adr_tcon_rst 0x80020004`.

AHB-протокол в исходнике подтверждён дословно:

```c
int hx83102_flash_write_burst(uint8_t *reg_byte, uint8_t *write_data)  /* = запись */
{
	uint8_t data_byte[8];
	for (i = 0; i < 4; i++) data_byte[i] = reg_byte[i];
	for (j = 4; j < 8; j++) data_byte[j] = write_data[j-4];
	return kp_himax_bus_write(0x00, data_byte, 8, ...);   /* одна i2c-запись 8 байт */
}

static int hx83102_register_read(uint8_t *read_addr, int len, uint8_t *out)  /* = чтение */
{
	if (len > 4) hx83102_burst_enable(1); else hx83102_burst_enable(0);
	/* addr[3..0] -> LE word -> bus_write(0x00, tmp, 4) */
	kp_himax_bus_write(0x00, tmp_data, 4, ...);
	tmp_data[0] = 0x00; kp_himax_bus_write(0x0C, tmp_data, 1, ...);
	kp_himax_bus_read(0x08, out, len, ...);
	if (len > 4) hx83102_burst_enable(0);
}
```
То есть §1 документа согласуется с исходником один-в-один.

### 8.3. Последовательность перед первым кадром (`himax_mcu_power_on_init`, `himax_ic_incell_core.c:542`)

```c
static void himax_mcu_power_on_init(void)
{
	I("%s:\n", __func__);
	g_core_fp.fp_touch_information();                 /* RX/TX/max_pt/x_res/y_res */
	g_core_fp.fp_register_write(pfw_op->addr_raw_out_sel, 4, pfw_op->data_clear, 0);
	g_core_fp.fp_assign_sorting_mode(pfw_op->data_clear);   /* 0x10007f04 = 0 */
	g_core_fp.fp_sense_on(0x00);
}
```

`himax_hx83102d_sense_on()` (`himax_ic_HX83102.c:1014`):

```c
I("Enter %s\n", __func__);
fp_interface_on();
fp_register_write(pfw_op->addr_ctrl_fw_isr, 4, pfw_op->data_clear, 0);  /* 0x9000005C = 0 */
usleep_range(10000, 10001);
if (!FlashMode) {
	fp_ic_reset(false, false);        /* pin reset */
	himax_hx83102d_reload_to_active();
} else { ... }
```

`himax_hx83102d_reload_to_active()` (`:973`) — то, чего у нас нет вовсе:

```c
addr[3]=0x90; addr[2]=0; addr[1]=0; addr[0]=0x48;      /* 0x90000048 */
do {
	data = 0x000000EC;
	fp_register_write(addr, 4, data, 0);
	usleep_range(1000, 1100);
	fp_register_read(addr, 4, data, 0);
	retry_cnt++;
} while ((data[1] != 0x01 || data[0] != 0xEC) && retry_cnt < HIMAX_REG_RETRY_TIMES);
```

`hx83102e_sense_off()` (`:796`) — совпадает с дизассемблером: `0x9000005C = 0xA5`,
10 мс, читать `0x900000A8` (должно быть `0x05`), читать назад `0x9000005C`
(ждём `0x87`), затем дважды `0x31=0x27`, `0x32=0x95`, проверка
`0x900000A8 == 0x0C`, и `AHB 0x80020004 = 0` (reset TCON) + 1 мс.

`hx83102e_read_event_stack()` (`:1587`) — ровно:

```c
kp_himax_bus_read((*kp_pfw_op)->addr_event_addr[0] /* 0x30 */, buf, length, retries);
```

### 8.4. Раскладка кадра (`himax_common.c`)

Размер (`himax_report_data_init`, `:1331`):

```c
touch_info_size = (ic_data->HX_MAX_PT + raw_cnt_max + 2) * 4;   /* (10 + 2 + 2)*4 = 56 */
```
Номер байта со счётчиком точек (`calculate_point_number`, `:933`):

```c
HX_TOUCH_INFO_POINT_CNT = HX_MAX_PT * 4;                       /* 40 */
if ((HX_MAX_PT % 4) == 0) += (HX_MAX_PT / 4) * 4;
else                      += ((HX_MAX_PT / 4) + 1) * 4;        /* 40 + 12 = 52 */
```

Разбор точек (`himax_parse_report_points`, `:1998`):

```c
for (loop_i = 0; loop_i < ts->nFinger_support; loop_i++) {
	base = loop_i * 4;
	x = buf[base] << 8 | buf[base + 1];            /* big-endian */
	y = buf[base + 2] << 8 | buf[base + 3];        /* big-endian */
	w = buf[(ts->nFinger_support * 4) + loop_i];   /* majors[] */
	...
}
...
finger_num = buf[ts->coordInfoSize - 4] & 0x0F;      /* = buf[52] */
ig_count   = buf[ts->coordInfoSize - 5];              /* = buf[51] */
```

Счётчик и `raw_data_sel` (`himax_parse_report_data`, `:2176`):

```c
EN_NoiseFilter = (buf[52] >> 3) & 0x01;
ts->hx_point_num = (buf[52] == 0xff) ? 0 : (buf[52] & 0x0f);
raw_data_sel = buf[52] >> 4 & 0x0F;                   /* 0x0F = обычные координаты */
```

Checksum (`himax_checksum_cal`, `:1660`):

```c
for (i = 0; i < length; i++) { check_sum_cal += buf[i]; if (buf[i] == 0x00) zero_cnt++; }
if (check_sum_cal % 0x100 != 0)  ret_val = HX_CHKSUM_FAIL;      /* сумма всех байт */
else if (zero_cnt == length)     ret_val = HX_CHKSUM_FAIL;      /* «All Zero event» */
```

Коды исключений (`himax_ts_event_check`) — `0xEB`/`0xEC`/`0xED` считаются
счётчиками «exception» (ESD/шум/«shaking»), а не данными точки.

### 8.5. Итог сравнения с нашим состоянием

| шаг вендора | у нас | следствие |
|---|---|---|
| `0x100072EC = 0` (raw out sel) | нет | чип может отдавать не координаты |
| `0x10007F04 = 0` (sorting mode) | нет | DSRAM/сортировка не сконфигурирована |
| `0x9000005C = 0` (sense on) | нет | сенсинг выключен |
| pin reset + 10/50 мс | есть (в probe) | порядок не тот: сброс до sense-on |
| `0x90000048 = 0xEC` (reload_to_active) | нет | возможно, чип не выходит в active |
| ожидание `0x900000A8 == 0x05` | есть (пассивно) | ок |
| чтение регистра `0x30`, 56 Б | есть | ок |
| раскладка/checksum | совпадает с mainline | ок |

Именно поэтому кадр стабильно `14 × 00 03 00 00`: по раскладке это «0 точек» с
битой суммой — то есть чип отвечает, но не отчётом.
