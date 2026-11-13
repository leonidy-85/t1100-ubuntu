# M48 (RE) — последний фрагмент, EVT на `WMT_RESET_CMD` и зазор между патчами (сток)

Три вопроса, ответы **только по дизассемблеру** стокового `wmt_drv.ko`
(`c2c70b9bec3892e04af89de4a2e8e103e3e2071b2efb72a71508eafb02ed2d34`, 4.14.186,
clang 11, статические символы вырезаны). Адреса — смещения в `.text`.
Выдержки: `refs/m48-stock-last-fragment/*.txt`.

Локализация (напоминание): `mtk_wcn_soc_sw_init` = `0x2e1c4` (по строке
`"mtk_wcn_soc_sw_init"`), в него **инлайнен** `mtk_wcn_soc_patch_dwn(index)`
(верх цикла — `0x2e768`, `ctrlData.ctrlId=0x1a` GET_PATCH_INFO) и
`mtk_wcn_soc_normal_patch_dwn` (цикл фрагментов `0x2ee9c`…`0x2f068`).
Проверено обходом CFG: весь диапазон `0x2e1c4..0x30600` достижим из `0x2e1c4`
(одна функция). Второй похожий цикл в модуле (`0xd740`…`0xdfxx`, строки с
`index(%d)`) — это `wmt_ic_6632.c`/`wmt_ic_6630.c`, к SOC-пути отношения не имеет.

## 1. Последний фрагмент: EVT читается, отдельной ветки нет

Цикл (`refs/m48-stock-last-fragment/stock-fragloop.txt`):

```
; верх итерации (следующая итерация; первая входит сразу в тело с 0x2eec0)
2ee9c: ldp  w10, w3, [sp, #0x3c]   ; w10 = fragSeq (0-based), w3 = fragNum
2eea4: ldr  w11, [sp, #0x28]       ; w11 = остаток, ВКЛЮЧАЯ текущий фрагмент
2eea8: add  w10, w10, #1           ; fragSeq+1
2eeac: add  x8,  x8,  #0x3e8       ; buf += 1000
2eeb0: cmp  w10, w3
2eeb4: sub  w11, w11, #0x3e8       ; остаток -= 1000
2eebc: b.hs #0x2f6fc               ; fragSeq+1 >= fragNum -> выход из цикла

; тело: флаг и размер фрагмента
2ef04: ldr  w9, [sp, #0x24]        ; w9 = fragNum-1   (0x2ed90: sub w8,w8,#1)
2ef08: cmp  w10, #0
2ef10: mov  w8, #1
2ef14: cinc w8, w8, ne             ; 1 для первого, иначе 2
2ef18: cmp  w9, w10
2ef20: mov  w9, #3
2ef24: csel w8, w9, w8, eq         ; 3 для последнего (fragSeq == fragNum-1)
2ef28: mov  w9, #0x3e8             ; 1000
2ef30: csel w21, w11, w9, eq       ; fragSize = последний ? остаток : 1000
2ef38: add  w9, w21, #1            ; cmdLen = fragSize + 1
2ef54: strh w9, [sp, #0xc0]
2ef58: bl   memcpy                 ; memcpy(&WMT_PATCH_CMD[2], &cmdLen, 2)
2ef6c: bl   memcpy                 ; memcpy(buf+off-5, WMT_PATCH_CMD, 5)
2ef88: bl   wmt_core_tx            ; tx(buf+off-5, fragSize+5, rAW=false)
2ef94: ldr  w4, [sp, #0xd0]
2ef98: cmp  x23, x4
2ef9c: b.ne #0x2f57c               ; короткая запись -> ошибка

; RX и сверка — БЕЗУСЛОВНО, в том числе для последнего фрагмента
2efd8: bl   osal_memset            ; memset(evtBuf, 0, 8)
2eff4: bl   wmt_core_rx            ; rx(evtBuf, sizeof(WMT_PATCH_EVT)=5)
2f004: cmp  w4, #5
2f008: b.ne #0x2f614               ; нет EVT -> ошибка
2f028: bl   osal_memcmp            ; memcmp(evtBuf, WMT_PATCH_EVT, 5)
2f030: cbnz w0, #0x2f654           ; не тот EVT -> ошибка
2f068: b    #0x2ee9c               ; back-edge
```

Итог по вопросу 1:

* **Да, `WMT_PATCH_EVT` читается и после последнего фрагмента.** Выход из цикла
  проверяется **на следующей** итерации (`0x2eebc`), т.е. уже после
  `tx → rx(5) → memcmp` последнего фрагмента. Ветки «последний → не читать RX»
  в стоке нет.
* `cmdLen = fragSize + 1` — одинаковая формула для всех фрагментов (последний не
  исключение; поле `WMT_PATCH_CMD[2..3]`, little-endian, `UINT16`).
* Флаг `WMT_PATCH_CMD[4]` = 1 / 2 / 3; для последнего — `3`
  (`cmp w9(=fragNum-1),w10` + `csel`), т.е. никакого «особого» флага нет.
* `fragSize` последнего = остаток `patchSize - fragSeq*1000` (`csel w21,w11,…`);
  например для `1_0` (229 356 Б) последний фрагмент — 356 Б, кадр 361 Б;
  для `1_1` (314 092 Б) — 92 Б.
* Проверки `remainSize == 0` **нет**; единственное сравнение с `fragNum` —
  выбор флага/размера. Дополнительных команд/задержек в теле цикла нет
  (`osal_sleep_ms` в диапазоне `0x2e768..0x2f350` не вызывается вообще).
* После цикла: печать `patch dwn:%d frag(%d,%d) ok/fail` (`0x2f704`…`0x2f774`),
  признак ошибки `fragSeq != fragNum` → `-1` (`0x2f77c`–`0x2f780`).
* Хвост загрузки (`0x2f260`): если `emiInfo[0x44] != 0` — копия 16 байт
  (`osal_memcpy_toio`, `0x2f2d0`) из буфера патча в EMI по адресу
  `emi_ap_phy_addr + emiInfo[0x48]`. На MT6771 это **мертвый код**: поле `+0x44`
  в инициализаторе `mtk_wcn_emi_addr_info` (`.data+0x1a8`) = 0, и в модуле нет ни
  одной записи в `[reg+#0x44]`/`[reg+#0x48]` (`objdump | grep 'str w*, [x*, #0x44]'`
  → пусто). Дальше `osal_free` + `WMT_CTRL_FREE_PATCH` (ctrlId 6) + возврат.

## 2. `WMT_RESET_CMD`: EVT ждём, ошибка фатальна

`init_table_3` (`.data+0xde0`, 1 запись: cmd `01 07 01 00 04`, evt `02 07 01 00 00`)
отправляется **после каждого патча** набором `wmt_core_init_script`
(`0x2f330`–`0x2f338`; таблица подготовлена заранее в `[sp,#0xa8]`).

```
2f32c: cbnz w23, #0x2f7e0     ; patch_dwn вернул ошибку -> "patch dwn fail (%d),patch_index(%d)", return -19
2f330: ldr  x0, [sp, #0xa8]   ; init_table_3
2f334: mov  w1, #1
2f338: bl   wmt_core_init_script
2f33c: cbnz w0, #0x2f814
```

`wmt_core_init_script` (`0x1e5f4`, 28 байт) — обёртка:

```
1e5fc: mov w3, #1        ; dump_err_log = 1
1e600: mov w2, wzr       ; retry = 0
1e604: bl  wmt_core_init_script_retry
```

Т.е. `init_script_retry(script, count=1, retry=0, dump=1)`. Внутри
(`0x1e24c`, `refs/m48-stock-last-fragment/stock-reset-path.txt`) на каждую запись:

```
1e37c-1e38c: wmt_core_tx(script->cmd, script->cmdSz, &u4Res, FALSE)
1e398-1e3a4: u4Res != cmdSz -> ошибка (0x1e430)
1e3a8:       memset(evtBuf, 0, 0x100)
1e3bc-1e3d8: ctrlData{ctrlId=17 (WMT_CTRL_RX), evtBuf, evtSz, &u4Res}; wmt_ctrl
1e3e4-1e3f0: u4Res != evtSz (в т.ч. 0 при таймауте) -> 0x1e4d0:
             "[WMT-CORE][E]%s(%d):WMT-CORE: read (%s) iRet(%d) evt len err(rx:%d, exp:%d)"
1e3f4:       ldrb w8,[sp,#0x49]; cmp w8,#0x14   ; evt[1]==0x14 -> memcmp пропускается
1e408:       osal_memcmp(evtBuf, script->evt, u4Res) != 0 -> 0x1e50c "compare %s result error"
1e330: subs w21, w21, #1     ; счётчик повторов (здесь 0)
1e334: b.mi #0x1e59c         ; -> w0 = (обработано != count) ? -1 : 0
```

**Таймаут** — общий RX-путь `wmt_ctrl_rx` (`0x1a2xx`,
`refs/m48-stock-last-fragment/stock-rx-timeout.txt`):

* `mtk_wcn_stp_receive_data()` сначала без ожидания; если 0 байт — цикл ожидания
  на `wait_event` с `timeoutValue = WMT_LIB_RX_TIMEOUT / loopCnt`;
* `loopCnt = 4`, только если `wmt_lib_get_drv_status(WMTDRV_TYPE_WMT) ==
  DRV_STS_FUNC_ON`: `1a2d8: cmp w19,#0x2` (2 = `DRV_STS_FUNC_ON`), затем
  `1a340: csinc w26,w22,wzr,eq` (loopCnt) и `1a344: csel w28,w9,w8,eq`
  (`w8=0x7d0`=2000 при `0x1a31c`, `w9=0x1f4`=500 при `0x1a320`) ⇒ **при power-on
  loopCnt = 1 → 2000 мс**, при уже включённом драйвере — 4 × 500 мс;
* если STP ещё сообщает «есть данные», один раз добавляется
  `WMT_LIB_RX_EXTEND_TIMEOUT` = 4000 мс (`mov w9,#0xfa0`, `udiv w26,w9,w8`, `0x1a528`);
* на таймауте: `stp_dbg_poll_cpupcr(5, 1, 1)` (`0x1a680`–`0x1a690`), печать
  `wmt_dev_rx_timeout: timeout,jiffies(%lu),timeoutvalue(%d)` (`0x1a6bc`),
  и если в STP остались данные — `wmt_lib_trigger_assert(WMTDRV_TYPE_WMT, 44)`;
  возврат `-1` → наверх `evt len err` → `init_script_retry` вернёт `-1`.

**Что делает `sw_init` при отсутствии EVT:** не продолжает, а **прерывает
power-on**:

```
2f814: ; "[WMT-IC][E]%s(%d):init_table_3 fail(%d)"  (строка 0x51e = 1310)
2f83c: mov w0, #-0x13        ; -19
2f840: b   0x305d0           ; epilogue / return
```

Т.е. в стоке reset — **строгий** шаг: один заход, без повторов, при неудаче
`WMT_OPID_PWR_ON` завершается ошибкой `-19`.

## 3. Между патчами набора: ничего

```
2f32c: cbnz w23, #0x2f7e0          ; ошибка загрузки патча -> aborts
2f330: ldr  x0, [sp, #0xa8]        ; init_table_3
2f334: mov  w1, #1
2f338: bl   wmt_core_init_script   ; WMT_RESET_CMD
2f33c: cbnz w0, #0x2f814           ; ошибка reset -> aborts (-19)
2f340: ldr  x8, [sp, #0xa0]        ; patch_num
2f344: add  x22, x22, #1           ; patch_index++
2f348: cmp  x22, x8
2f34c: b.ne #0x2e768               ; -> верх инлайненного patch_dwn(idx+1)
2f350: b    #0x2f844               ; набор кончился
```

Между reset патча `i` и загрузкой патча `i+1` **нет ничего**: ни `STP close/open`,
ни `hw_check`, ни чтения регистров, ни `osal_sleep_ms`, ни `wmt_core_ctrl`.
Счётчики не переносятся — они локальны и инициализируются заново на входе в
`patch_dwn` (`0x2e768`): `patchSize = 0` (`str xzr,[sp,#0xd8]`),
`memset(gFullPatchName)`, затем GET_PATCH_INFO(`idx+1`) → GET_PATCH → `malloc` →
копия → резка 28 Б → `normal_patch_dwn` со свежими `fragSeq = 0` (`0x2ed7c`) и
`остаток = patchSize` (`0x2ed78`).

После последнего патча (`0x2f350` → `0x2f844`): `options bit2` →
`set_mcuclk_table_4` (3 команды, `0x2f86c`).

## 4. Сверка с нашим `patches/wifi/0013` + `0014` (сборка `wmt_drv.ko` `a723a4d9…`)

Сборка `a723a4d9…` = вендорский gen3 + `0013-common-rom-patch-from-firmware.patch`
+ `0014-common-rom-patch-delivery.patch` (M46). По трём местам:

| место | сток | наш `a723a4d9` | расхождение |
|---|---|---|---|
| EVT на последнем фрагменте | читается всегда (`0x2eff4`), ошибка при 0 байт | `0013`: `if (fragSeq == fragNum - 1) { iRet = 0; ++fragSeq; osal_sleep_ms(100); break; }` — RX **пропускается**, добавлена пауза 100 мс | **ДА** |
| `WMT_RESET_CMD` | `init_script(…, retry=0)`; ошибка → `-19`, power-on прерывается | `0013`: до 3 попыток с `osal_sleep_ms(200)` между; `0014`: ошибка принудительно `iRet = 0` (best effort) | **ДА** |
| между патчами | пусто (`0x2f340`–`0x2f34c`) | `0014`: печать `reset ack after patch`, 3 чтения `0xf0078000`, затем `STP_CLOSE/OPEN/STP_CONF(MODE=MAND)/STP_CONF(EN=1)` + чтение `0x80000008`, плюс переключение `t1100_patch_active` | **ДА** |

Совпадает: резка 28 Б (`body_size = fw->size - 28`), адрес = `fw->data[24..27]`
(то же, что отдаёт launcher), порядок патчей по `seq` (`1_1` → `1_0`), 1000 Б на
фрагмент, флаги 1/2/3, `FREE_PATCH` после каждого патча, `mcuclk_table_4` в конце.

## 5. Что из этого следует

1. В стоке **нет** ни одного из трёх послаблений, которые есть у нас. Если чип не
   подтверждает последний фрагмент `1_1`, сток бы тоже упал (его `patch_dwn`
   вернул бы `-1`, и `sw_init` вышел бы с `-7`). Значит расхождение не в этих
   трёх местах, а в **содержимом/транспорте** кадров `1_1` либо в нашем RX-пути.
2. Быстрая проверка «чип или хост»: при таймауте на последнем фрагменте `1_1`
   читать `cpupcr` (0x80000000) и `mtk_stp_check_rx_has_pending_data()`; сток в
   этой же ситуации делает `stp_dbg_poll_cpupcr(5,1,1)` и, если в STP есть
   данные, `trigger_assert(…, 44)`.
3. Если подтвердится, что чип молчит и на стоке (то есть `1_1` для нашей платы не
   нужен) — проверять гипотезу «`patch_num` в launcher'е = 1»: у нас `num` берётся
   из nibble заголовка, и оба файла дают `num = 2`; если у вендора на этой
   сборке даунлоадер получает `patch_num = 1` (например, launcher отбраковывает
   `1_1` по fingerprint), то второй `WMT_RESET_CMD` в стоке просто не
   отправляется.
4. Тест «как в стоке» (три правки сразу, без ретраев и без reinit): ждать EVT
   всегда, reset один раз и падать при ошибке. Это единственная конфигурация, в
   которой поведение сравнимо со стоком; текущие M45/M46-послабления маскируют
   настоящую ошибку.

## 6. Файлы

```
refs/m48-stock-last-fragment/stock-fragloop.txt       0x2ee9c..0x2f068
refs/m48-stock-last-fragment/stock-inter-patch.txt    0x2f32c..0x2f354, 0x2e768, 0x2f844
refs/m48-stock-last-fragment/stock-reset-path.txt     0x1e5f4, 0x1e37c..0x1e414, 0x1e4d0, 0x2f814
refs/m48-stock-last-fragment/stock-rx-timeout.txt     0x1a2f0..0x1a348, 0x1a520, 0x1a680
refs/m48-stock-last-fragment/ours-0013-0014.txt       выдержки наших патчей
```
