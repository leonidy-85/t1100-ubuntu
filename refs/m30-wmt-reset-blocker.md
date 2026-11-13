# M30 — `-2` расшифрован; блокер теперь «wmt reset» без ответа (13.11)

## 1. Что такое `-2` и `err(-2, 5)` (цитата)

`wmt_core_init_script_retry()` печатает
`write (%s) iRet(%d) cmd len err(%d, %d)` = `iRet`, `*writtenSize`, `cmdSz`.
`-2` приходит из `wmt_ctrl_tx_ex()` (`common_main/core/wmt_ctrl.c:345-357`):

```c
	/* if STP is not enabled yet, can't use this function. Use tx_raw instead */
	if (!osal_test_bit(WMT_STAT_STP_OPEN, &pDev->state) ||
	    !osal_test_bit(WMT_STAT_STP_EN, &pDev->state)) {
		WMT_ERR_FUNC("wmt state(0x%lx)\n", pDev->state.data);
		osal_assert(osal_test_bit(WMT_STAT_STP_EN, &pDev->state));
		osal_assert(osal_test_bit(WMT_STAT_STP_OPEN, &pDev->state));
		iRet = -2;
		if (writtenSize)
			*writtenSize = iRet;      /* -> err(-2, ...) */
		return iRet;
	}
```

То есть `iRet(-2)` = **STP не открыт/не включён** (`WMT_STAT_STP_OPEN`/`_EN`),
а второй аргумент — это `writtenSize`, куда в ошибке кладётся тот же `-2`
(поэтому в логе `err(-2, 5)`, хотя ожидалось 5 байт).

## 2. Кто сбрасывает STP: таймаут RX на последнем фрагменте патча

В M29 мы просто игнорировали отсутствие `WMT_PATCH_EVT` на последнем фрагменте,
но сам вызов `wmt_core_rx()` **всё равно ждал 2 с**, а по таймауту
`wmt_ctrl_rx()` делает `wmt_lib_trigger_assert(WMTDRV_TYPE_WMT, 44)`
(`wmt_ctrl.c`, ветка `wmt_dev_rx_timeout`) — in-band assert рвёт STP, и следующая
команда получает `-2`.

Исправлено: на последнем фрагменте RX **не читается вовсе** (ROM прыгает в патч
и EVT не шлёт):

```c
		if (fragSeq == fragNum - 1) {
			WMT_INFO_FUNC("t1100: last fragment sent, ROM jumps (no EVT expected)\n");
			iRet = 0;
			++fragSeq;
			osal_sleep_ms(100);   /* дать ROM применить патч */
			break;
		}
```

Плюс `init_table_3` («wmt reset») теперь с 3 попытками и паузой 200 мс.

## 3. Результат: `-2` ушёл, но ROM молчит на «wmt reset»

```
[ 41.931] t1100: last fragment sent, ROM jumps (no EVT expected)
[ 42.033] t1100: ROMv4 patch download -> 0
[ 44.121] [WMT-CORE][E]wmt_core_init_script_retry(702): read (wmt reset) iRet(-1) evt len err(rx:0, exp:5)
[ 44.329] [WMT-CORE][E]wmt_core_init_script_retry(691): write (wmt reset) iRet(-2) cmd len err(-2, 5)
[ 44.533] [WMT-CORE][E]wmt_core_init_script_retry(691): write (wmt reset) iRet(-2) cmd len err(-2, 5)
[ 44.533] [WMT-IC][E]mtk_wcn_soc_sw_init(1285):init_table_3 fail(-1) after retries
```

То есть: первая попытка **отправлена успешно** (`cmdSz=5`), ответа нет
(`rx:0`), таймаут → assert → STP закрыт → 2-я и 3-я попытки падают на TX (`-2`).

Сама команда (`wmt_ic_soc.c:143`):

```c
static UINT8 WMT_RESET_CMD[] = { 0x01, 0x07, 0x01, 0x00, 0x04 };  /* opcode 0x07, payload 0x04 */
```

## 4. Состояние BTIF/STP после отказа (проверено)

```
BTIF: IER=0x00000001  IIR=0x00000001  LSR=0x00000060  DMA_EN=0x00000004
      /proc/interrupts: 395 (mtk btif irq) = 94028  -> RX по BTIF работал всё время патча
      IFR0 = 0x1befff5d (bit31 = 0, клок открыт)
cpupcr = 0x00014eea  (ROM, < 0xa5800)
```

Очередь RX пуста (IIR «нет прерывания», LSR `THRE|TEMT`), т.е. ROM **ничего не
прислал** в ответ на `0x07/0x04` — это не «потеряли байты».

## 5. Что осталось выяснить (предложение, без «перебора команд»)

1. Ответ на `0x07` не приходит **после** патча, хотя `0x08` (REG_READ, `hw_check`)
   до патча отвечал. Проверить по вендорскому коду, не требует ли ROMv4 после
   загрузки **другого** «стартового» действия: в `wmt_ic_soc.c` для icId `0x0788`
   есть только ROMv4-адреса, но сама последовательность (`init_table_3`) писалась
   под ROMv2/3; на MT6771 вендор мог стартовать патч **самим последним
   фрагментом** (тогда reset не нужен вовсе — его EVT и не приходит).
2. Проверить гипотезу «патч уже стартовал»: после успешной загрузки посмотреть
   `cpupcr` **без** reset (мы видели `0x14xxx`, но замер делался после assert'а,
   который мог перезапустить ROM) — нужен прогон, где reset не отправляется
   вообще (`t1100_skip_reset=1`), и замер `cpupcr` сразу после последнего
   фрагмента.
3. Если reset всё же нужен — не давать assert'у рвать STP: на время патча
   подавить `wmt_lib_trigger_assert` (флаг), чтобы ретраи могли отправлять
   команду, и увеличить таймаут RX для этой команды.

## 6. Артефакты

| что | sha256 |
|---|---|
| `wmt_drv.ko` (skip-RX + delay + retry) | `1933ab0238dcb38a3bb718ca4b5ae82ff37f729276bb54abde685e8a331022ad` |
| `mtk_btif_drv.ko` (гейт CLR) | `e29eaecb70157b1c27ed190b7849c308cc5f6e5e8cae3341af6c2a896b40ef34` |
| патч вендорского пути | `patches/wifi/0013-common-rom-patch-from-firmware.patch` |

## 7. Прогон без reset (`t1100_skip_reset=1`) — патч сам не стартует

Добавлен параметр `t1100_skip_reset` (пропуск `init_table_3`). Прогон:

```
t1100: ROMv4 patch download -> 0
t1100: skip init_table_3 (reset) on request
... 3 s позже:
[wlan]t1100_wlan_probe: paldo on + wlanProbe
[wlan]wlanPollingCpupcr: i:0,cpupcr:00014f08 ; i:1,cpupcr:00014f08 ; i:2,cpupcr:0000560e
```

`cpupcr` остаётся в ROM ⇒ **последний фрагмент патч не запускает**, «стартовая»
команда нужна. Значит блокер именно в том, что ROM не отвечает (и, судя по
поведению, не выполняет) `WMT_RESET_CMD {01 07 01 00 04}`.

Заодно это снимает вопрос «а не стартует ли патч сам» — нет.
