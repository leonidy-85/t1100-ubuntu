# M43 — как стоковый бинарник качает ROMv4-патч для chip-id `0x0788` (RE, 13.11)

Всё ниже — из **бинарников**, не из исходников: стоковый `wmt_drv.ko` из
`/home/l/aurora_root.img` (`/lib/modules/4.14.186/wmt_drv.ko`), стоковый
`/vendor/bin/wmt_launcher` и наш `.ko` эпохи M40. Устройство не трогали.

## 0. Что извлечено (sha256)

| файл | размер | sha256 |
|---|---|---|
| `wmt_drv.ko` (сток, 4.14.186) | 2 133 051 | `c2c70b9bec3892e04af89de4a2e8e103e3e2071b2efb72a71508eafb02ed2d34` |
| `wmt_chrdev_wifi.ko` (сток) | 42 771 | `129b49669d02855e0dd6143d521dd84c443a4c6930468a95ab8f73e3765ca0ed` |
| `wlan_drv_gen3.ko` (сток) | 4 083 019 | `249ebea1bab77648c79c18c559097356e147348cfed1933776d26338998cc42b` |
| `wmt_launcher` (сток, `/vendor/bin`) | 33 864 | `cce022d07302994ff155dfba76202cafffe64572f47bbed272eaa1e84bba15a1` |
| `ROMv4_be_patch_1_0_hdr.bin` | 229 384 | `83f7e9bc06628b2c3768b190de1c19ecb7846b0bd990e2728f72638b4340da6c` |
| `ROMv4_be_patch_1_1_hdr.bin` | 314 120 | `2203d8b76a497d85c0e8cd7daa6da0e8158f7a148a296150a46e1c977e9cd95d` |
| наш `wmt_drv.ko` (M40, 6.12) | 1 146 248 | `1e10a898be02ccffdcd05cd49d97f90c063a09941272f306b9d4cc74605dca40` |

Сток собран clang 11 (`Android (6443078 based on r383902)`), **.symtab есть, но
только глобальные символы** — все `static` (в т.ч. `mtk_wcn_soc_sw_init`,
`mtk_wcn_soc_normal_patch_dwn`, `mtk_wcn_soc_patch_dwn`) в таблице символов
отсутствуют. Локализация — по строкам и по `.rela.text`/`.rela.data`
(в relocatable `.ko` каждая `adrp`/`add` имеет запись; смещение цели восстанавливается
как `sym.st_value + r_addend` для символьной секции `.data`/`.rodata.str1.1`).
Инструменты: собственный ELF/reloc-парсер + `capstone` (`/tmp/opencode/re/`),
плюс `aarch64-linux-gnu-objdump` для `wmt_launcher`.

| что | как найдено | адрес |
|---|---|---|
| `mtk_wcn_soc_sw_init` | строка `"mtk_wcn_soc_sw_init"` (.rodata.str1.1+0x1071) ссылается из 0x2e30c/0x2e370/… | `.text+0x2e1c4` |
| `mtk_wcn_soc_normal_patch_dwn` | строка `"[WMT-IC][I]%s:normal patch download patch size(%d) fragNum(%d)"` → 0x2ebcc/0x2ebd8 | `.text+0x2eb94` (вход в ветку) |
| `mtk_wcn_soc_pda_patch_dwn` | строка `"mtk_wcn_soc_pda_patch_dwn"` | `.text+0x2ee78` (ветка) |
| `mtk_wcn_soc_patch_dwn(index)` | `"mtk_wcn_soc_patch_dwn"` + резка заголовка 28/30 | `.text+0x2e8xx` |
| `mtk_wcn_consys_get_options` | символ есть (глобальный) | `.text+0xb9cc` |
| `consys_ic_get_options` для MT6771 | элемент `consys_ic_ops[62]` (`.data+0x3e8`) | `.text+0x5364` |
| `wmt_dev_patch_get` | символ есть | `.text+0x52b6c` |

## 1. Главное: у стока `patch_num = 2`, у нас `1`

Файл `ROMv4_be_patch_1_0_hdr.bin` — **не единственный** патч и **не первый**.
В `/vendor/firmware` лежат два кандидата с одним и тем же 28-байтовым
`WMT_PATCH`-заголовком:

```
0x00..0x0f  "20220615154332a\n"   ucDateTime
0x10..0x13  "ALPS"                ucPLat
0x14..0x15  8a 00                 u2HwVer
0x16..0x17  8a 00                 u2SwVer
0x18..0x1b  u4PatchVer            <- ЗДЕСЬ же лежит patch_num/patch_seq и адрес
```

`u4PatchVer`: **младший байт** лаунчер трактует как `num<<4 | seq`, а всё 32-битное
слово целиком отдаёт ядру как адрес загрузки (поэтому «адрес» = `0x00098022` /
`0xf0078021` — в нём же закодирован и номер патча):

| файл | u4PatchVer | num | seq | адрес (`[12..15]` P_ADDRESS) | тело | фрагментов |
|---|---|---|---|---|---|---|
| `ROMv4_be_patch_1_1_hdr.bin` | `0xf0078021` | 2 | **1** | `21 80 07 f0` | 314 092 Б | **315** (314+92) |
| `ROMv4_be_patch_1_0_hdr.bin` | `0x00098022` | 2 | **2** | `22 80 09 00` | 229 356 Б | **230** (229+356) |

Доказательство — код `wmt_launcher` (`launcher_set_patch_info`, `0x5c90`; выдержки в
`refs/m43-stock-romv4/launcher-set-patch-info.txt`):

```
5ce8: mov x21, x1          ; x1 = 4 байта, прочитанные из файла со смещения 24
5cf4: ldrb w8, [x21]       ; info[0] = младший байт u4PatchVer
5d0c: lsr  w22, w8, #4     ; patch_num = info[0] >> 4          -> "patch num = [%d]"
5d28: ioctl(fd, 0x40040a00e, w22)   ; WMT_IOCTL_SET_PATCH_NUM
5d44: and  w22, w8, #0xf   ; patch_seq = info[0] & 0xf        -> "patch seq = [%d]"
5d50: ldr  w8, [x21]       ; полные 4 байта = адрес
5d64: stp  w22, w8, [sp]   ; {seq, addr}
5d84: ioctl(fd, 0x40080a00f, &{seq,addr,name})  ; WMT_IOCTL_SET_PATCH_INFO
```

и место чтения этих 4 байт (в том же файле, `0x34e0`–`0x35b8`):

```
34e0: lseek(fd, 22, SEEK_SET)      ; u2HwVer/u2SwVer
34f4: bl 0x5bf8                    ; «fingerprint»-сверка версии
3564: read(fd, sp+0x18, 4)         ; 4 байта по смещению 24 = u4PatchVer
3580: ... "read patch info:0x%02x,0x%02x,0x%02x,0x%02x"
35b8: bl launcher_set_patch_info(fd, sp+0x18, name, first)
```

Т.е. **`patch_num`/`patch_seq` — это не догадка, а буквально `num = info[0]>>4`,
`seq = info[0]&0xf`**, а сами файлы `1_0`/`1_1` — это «патч 2 из 2» и «патч 1 из 2».
Кто именно из файлов получит seq=1, решает launcher (перебор каталога + сверка
fingerprint по заголовку), но арифметика nibble однозначна.

**Что доказано, а что вывод:** доказано (по коду) — откуда лаунчер берёт `num`/`seq`
и что для любого из двух ROMv4-файлов `num = 2`; вывод (сильный, но не проверен на
железе) — что сток грузит оба файла: при `num = 2` драйвер запросит seq 1 и seq 2,
и если бы одного файла не было, загрузка патча падала бы на `GET_PATCH_INFO` —
а на стоке Wi-Fi/BT работают. Подтверждается одной строкой в logcat стоковой
загрузки: `patch num = [2]` + два `patch seq = [1]`/`[2]`.

Префикс имени для `0x0788` тоже подтверждён бинарём лаунчера
(`refs/m43-stock-romv4/launcher-chipid-0788-prefix.txt`):

```
3184: cmp w21, #0x788        ; w21 = chip_id от ядра (ioctl 0x80040a00c)
318c: ... -> 0x366c
3674: str xzr, [g_patch_prefix]
368c: str "ROMv4_be"         ; g_patch_prefix
```

## 2. Полная последовательность стока для `0x0788` (BTIF, non-PDA)

`mtk_wcn_soc_sw_init` (`0x2e1c4`), host=BTIF, `pda_dl_patch_flag = 0`
(`mtk_wcn_emi_addr_info` .data+0x1a8, поле +0x24 = 0):

1. `_wmt_soc_mode_ctrl(MTKSTP_BTIF_FULL_MODE)` → `init_table_1_2` (query stp default),
   `init_table_4` (set stp), `WMT_CTRL_STP_CONF{mode,en}`, `osal_sleep_ms(10)`,
   `init_table_5` (query stp).
2. **options** = `wmt_ic_ops_soc.u4Options` (поле +8, `.data+0xc28`), его пишет
   `mtk_wcn_consys_get_options()` (`0xb9cc`) из `consys_ic_ops[62]`;
   для MT6771 функция `0x5364` возвращает **`0x008436b5`**:
   ```
   5364: mov  w0, #0x36b5
   5368: movk w0, #0x84, lsl #16
   536c: ret
   ```
3. `bit0` options → `init_script(wmt_power_on_dlm_table=.data+0xc78, 3)` (`0x2e508`)
   — у нас бит 0 = 1, значит таблица уходит.
4. `wmt_core_ctrl(25 /*GET_PATCH_NUM*/)` (`0x2e3e4`); если 0 → `wmt_ctrl(PATCH_SEARCH)`
   (`srh_patch`, `0x2e490`).
5. `bit1` options → `set_mcuclk_table_1` (2), `bit2` → **`set_mcuclk_table_3` (4)**
   (`0x2e62c`, таблица `.data+0xd40`). Бит 2 у нас 1 ⇒ 4 команды:
   `…10 11 02 81 00 00 00 10 00 00 00 10`, `…0c 01 00 80 40 00 00 00 c0 …`,
   `…18 11 02 80 07 … 3f …`, `…00 11 02 81 04 … 07 …` (по 20 Б, evt `02 08 04 00 00 00 00 01`).
6. `for (idx = 0; idx < patch_num; idx++)`:
   a. `mtk_wcn_soc_patch_dwn(idx)`:
      - `WMT_CTRL_GET_PATCH_INFO(idx+1)` (`wmt_ctrl`, `0x18810`) → имя+адрес;
      - `WMT_CTRL_GET_PATCH` → `wmt_dev_patch_get` = `request_firmware(name, NULL)`
        (`0x52bbc`), отдаёт `fw->data` и `fw->size`;
      - копия в `osal_malloc(patchSize)`, резка заголовка: `patchSize > 0x1b` и
        `bit1` options ? 30 : **28** байт (`0x2e908`–`0x2e970`). У MT6771 бит 1 = 0
        ⇒ **28** (никакого CRC-среза — подтверждает M39);
      - `pda_dl_patch_flag == 0` → `mtk_wcn_soc_normal_patch_dwn` (`0x2eb94`);
      - ROM-база выбирается битами 21..24 options (`0x2ebfc`–`0x2edac`):
        bit21 → ROMv2 (`40`/`c8`), bit22 → ROMv3 (`08 05`/`2c 0b`), **bit23 → ROMv4**
        (`18 05`/`7c 0b`, `0x2ec6c`), bit24 → 4-байтовый адрес для 6765/3967/6761.
        Для `0x8436b5` выставлен ровно bit23:
        ```
        2ec88: mov  w11, #0x518
        2ec90: strh w11, [x9]       ; WMT_PATCH_ADDRESS_CMD[8..9]   = 18 05
        2ec94: mov  w9, #0xb7c
        2ec98: strh w9, [x10]       ; WMT_PATCH_P_ADDRESS_CMD[8..9] = 7c 0b
        ```
      - `tx(WMT_PATCH_ADDRESS_CMD, 20)` (`0x2edcc`) + `rx(8)` + `memcmp` с
        `WMT_PATCH_ADDRESS_EVT` (`0x2ee30`);
      - `WMT_PATCH_P_ADDRESS_CMD[12..15] = addr` (`0x2f460`, таблица `.data+0x1271`),
        `tx(…,20)` (`0x2f4d8`) + `rx(8)` + `memcmp` (`0x2f53c`);
      - фрагменты: `fragNum = patchSize/1000 (+1)`, `0x3e8` (`0x2eb94`–`0x2ebbc`);
        флаг `WMT_PATCH_CMD[4]` = 1 / 2 / 3 (`0x2ef08`–`0x2ef2c`), `cmdLen = fragSize+1`
        (`0x2ef38`), `memcpy(&WMT_PATCH_CMD[2], &cmdLen, 2)`, `memcpy(buf+off-5, WMT_PATCH_CMD, 5)`,
        `tx(fragSize+5)` (`0x2ef88`) + `rx(5)` (`0x2eff4`) + `memcmp` с `WMT_PATCH_EVT`
        (`0x2f028`). Никаких пауз/доп. команд между фрагментами **нет**;
      - `osal_free`, затем `WMT_CTRL_FREE_PATCH(idx+1)` = ctrlId **6**
        (`0x2f318`, `0x2f328`);
   b. `wmt_core_init_script(init_table_3, 1)` = **`WMT_RESET_CMD {01 07 01 00 04}`**
      (`0x2f338`, таблица `.data+0xde0`, evt `02 07 01 00 00`) — **после каждого патча**;
7. `bit2` → `init_script(set_mcuclk_table_4=.data+0xe58, 3)` (`0x2f86c`): `disable mcu hclk`,
   `disable mcu ratio`, `disable mcu clk`.
8. Далее обычный хвост (`set_chipid_script`, coex/ext component, crystal trim, …).

Итог для нашей платы: **315 фрагментов (1_1, addr `0xf0078021`) → reset → 230
фрагментов (1_0, addr `0x00098022`) → reset**, всего 545 фрагментов и два
`WMT_RESET_CMD`. Наш порт делает только вторую половину: 230 фрагментов и один reset
по адресу `0x98022`.

## 3. Отличия стока от нашего `.ko` (`1e10a898…`)

Сток — более новая ревизия того же gen3-кода: вместо цепочек `icId == 0x0788` он
использует **маску возможностей** `wmt_ic_ops_soc.u4Options` (поле +8; структура
88 Б против наших 80 Б). Для `0x0788` результат сравнения одинаковый:

| шаг | сток (бинарь) | наш `.ko` | вывод |
|---|---|---|---|
| DLM-таблица (3) | по `options bit0` (`0x2e3a0`) | `#if CFG_WMT_POWER_ON_DLM` + `icId != 6765/3967/6761` (`add x0,x24,#0x1e8` = `.data+0xad0`, `0x24064`) | совпадает |
| mcuclk 6797 (4) | `options bit2` → `.data+0xd40` (`0x2e62c`) | `add x0,x24,#0x260` + `icId ∈ {788,688,713,507,279}` (`0x23e28`) | совпадает |
| ROMv4 база | `bit23` → `strh 0x518`/`0x0b7c` | `icId&~0x100==0x688` → `strh` в `[x21,#0x58]`/`[x21,#0x70]` (`0x21d70`) | совпадает (`18 05`/`7c 0b`) |
| резка заголовка | 28 (CRC только `bit1`) | 28/48 по `t1100_patch_hdr_len` | 28 — верно; 48 — сдвиг на 20 Б |
| фрагменты | 1000 Б, флаги 1/2/3, tx+rx+memcmp | то же (`0x216d8`, `0x218b8`–`0x2198c`) | совпадает |
| FREE_PATCH | ctrl 6 перед reset | `wmt_ctrl_free_patch` внутри `patch_dwn` | совпадает |
| reset | `init_script(init_table_3,1)` после каждого патча | то же (для `patch_num=1`) | совпадает |
| mcuclk_4 (3) | после цикла (`0x2f86c`, `.data+0xe58`) | есть (`add x0,x24,#0x378` = `.data+0xc60`, `0x2435c`) | совпадает |
| **число патчей** | **2** (`u4PatchVer` nibble) | **1** (`t1100_rom_patch`, один файл) | **РАСХОЖДЕНИЕ** |
| лишнее у нас | — | `wmt_plat_pwr_ctrl(1)`+`sleep(100)`+`pwr_ctrl(0)`+`sleep(50)` (`0x237e8`), `sleep(2000)` (`0x23970`) | наши t1100-правки, к протоколу не относятся |

Т.е. **сама последовательность команд для `0x0788` идентична** (адресные команды,
флаги, размер фрагмента, reset). Единственное содержательное расхождение —
**количество патчей и их порядок**.

## 4. Почему это объясняет «229 из 230»

MCU ожидает первым патч **seq 1** (`1_1`, адрес `0xf0078021`, 315 фрагментов), а мы
шлём сразу seq 2 (`1_0`, `0x98022`). Дальше возможны два сценария, и оба сходятся с
наблюдаемым:

* MCU, получив не тот патч/не в том порядке, не подтверждает последний фрагмент
  (ему «не хватает» ранее загруженного куска), а следующие байты (включая
  `WMT_RESET_CMD`) уходят в patch-буфер ⇒ чип замолкает на STP до power-cycle;
* либо загрузка 1_0 без 1_1 оставляет MCU в промежуточном состоянии — ровно то, что
  видно как `hwcode = -3`, `patchmem = 0` после сброса (M37/M38).

Отдельно: наш тест «48 vs 28» из M40 мог быть невалиден — при 48 байтах в MCU уходит
тело, сдвинутое на 20 байт (`u4PatchVer`/`PatchType` — это не заголовок, а первые
байты тела), что само по себе ломает патч.

## 5. Что проверить дальше (по возрастанию цены)

1. Прогнать **два** патча в порядке seq: `1_1` (addr `0xf0078021`) → `WMT_RESET` →
   `1_0` (addr `0x00098022`) → `WMT_RESET`, резка 28 байт у обоих, без power-cycle
   между ними. Ожидание: 315 ack, reset ack, 230 ack, reset ack, затем
   `hwcode 0x788` и `patchmem != 0`.
2. Если reset после 1_1 не подтверждается — сравнить с M33: там последний фрагмент
   `1_0` (347 Б по STP). Для `1_1` последний кадр = 92+5+6 = 103 Б.
3. Диагностика: перед загрузкой 1_0 прочитать `patchmem[0x80098020]` — если сток
   кладёт 1_1 по `0xf0078021`, это видно по EMI (`0xf0078000`-регион, база EMI
   `0xf0080000`), а не по `0x8009_8xxx`.
4. Только после этого — STP-reinit/таймауты (M38 показал, что без правильного набора
   патчей это не лечит).

## 6. Выдержки дизассемблера

`refs/m43-stock-romv4/`:

* `stock-sw-init-options.txt` — options (`0x2e390`,`0x2e3a0`), DLM-таблица (`0x2e508`),
  `set_mcuclk_table_3` (`0x2e618`), `consys_ic_get_options` (`0x5364`);
* `stock-fragnum-and-rombase.txt` — `fragNum`/`0x3e8` (`0x2eb94`), выбор ROMv4
  (`0x2ec6c`), ADDRESS/P_ADDRESS tx/rx (`0x2edb0`–`0x2ee34`, `0x2f458`–`0x2f544`);
* `stock-fragloop-and-evt.txt` — цикл фрагментов, флаги 1/2/3, `cmdLen`,
  `WMT_PATCH_EVT`, `FREE_PATCH` (ctrl 6), reset `init_table_3` (count 1);
* `launcher-set-patch-info.txt` — `patch_num = info[0]>>4`, `seq = info[0]&0xf`,
  чтение 4 байт по смещению 24;
* `launcher-chipid-0788-prefix.txt` — `chip_id == 0x788` → префикс `"ROMv4_be"`;
* `ours-romv4-base.txt` — наш ROMv4 (`strh 0x518`/`0xb7c`) и `set_mcuclk_table_3`
  (count 4) для сравнения.

## 7. Публиковать нельзя

Файлы прошивок (`ROMv4_*.bin`), `.ko` и `wmt_launcher` в git не кладём — только
выдержки кода и sha256 (см. правило проекта).
