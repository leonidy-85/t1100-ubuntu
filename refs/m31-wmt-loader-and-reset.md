# M31 — `wmt_loader`/mt6765 про «start»-команду и последний блокер reset (13.11)

## 1. `wmt_loader` из стокового образа (`/home/l/aurora_root.img`)

```
debugfs -R "ls -l /vendor/bin" → wmt_loader 11 696 Б, wmt_launcher 33 864 Б
```

`wmt_loader` (aarch64, stripped) — только `/dev/wmtdetect`:

```
ioctl
/dev/wmtdetect
WMT driver has been ready.
/proc/driver/wmt_dbg
/proc/driver/wmt_aee
do WMT-DETECT module cleanup failed: %d
```

Никаких `patch`/`stp`/`start`-команд в нём нет: он делает только
`COMBO_IOCTL_SET_CHIP_ID`/`DO_MODULE_INIT` (это у нас уже воспроизводит
`wmtctl`).

`wmt_launcher` (aarch64, stripped) — демон, который отвечает ядру на
`srh_patch`/`srh_rom_patch` через `/dev/stpwmt`:

```
srh_rom_patch
srh_patch
/dev/stpwmt
patch info:0x%02x,0x%02x,0x%02x,0x%02x,0x%02x,0x%02x,0x%02x,0x%02x
read patch info:0x%02x,0x%02x,0x%02x,0x%02x
rom patch type = [%d]
invalid patch full name!
Stp Mode is not set, common interface use default: BTIF Mode
    -3: BTIF mode (common interface: BTIF)
Usage: wmt_launcher [-m mode] -p patchfolderpath
```

**Вывод: отдельной «start/run patch» команды в userspace нет.** Пользователь
отдаёт только имя файла и 4 байта адреса (`read patch info:0x…`), а «старт»
патча делает ядро командой `WMT_RESET_CMD` (`init_table_3`) — ровно то, что у
нас уходит и не получает ответа. «BTIF Mode» — дефолт лаунчера, совпадает с
нашим выбором.

## 2. mt6765 — тот же ROMv4-путь

`common_main/platform/mt6765.c:681`

```c
			if (consys_dl_rom_patch(consys_ver_id) == 0)
```

`mt6765.c:1096-1100` → `mtk_wcn_soc_rom_patch_dwn()` (запись в EMI, «PDA»-путь),
после чего в `mtk_wcn_soc_sw_init()` идёт **тот же** `init_table_3`:

```c
static struct init_script init_table_3[] = {
	INIT_CMD(WMT_RESET_CMD, WMT_RESET_EVT, "wmt reset"),
	...
};
static UINT8 WMT_RESET_CMD[] = { 0x01, 0x07, 0x01, 0x00, 0x04 };
```

Т.е. у mt6765 «старт» — тоже `{01 07 01 00 04}`; альтернативного payload в
публичном коде нет.

## 3. `P_ADDRESS` действительно отправлялся

Доказательство из кода (`mtk_wcn_soc_normal_patch_dwn`): обе команды идут
**до** цикла фрагментов и любая ошибка возвращает -1:

```c
	iRet = wmt_core_tx(&WMT_PATCH_ADDRESS_CMD[0], sizeof(...), &u4Res, ...);
	if (iRet || (u4Res != sizeof(WMT_PATCH_ADDRESS_CMD))) return -1;
	... wmt_core_rx(addressevtBuf, sizeof(WMT_PATCH_ADDRESS_EVT), &u4Res);
	...
	WMT_PATCH_P_ADDRESS_CMD[12..15] = addressByte[0..3];
	iRet = wmt_core_tx(&WMT_PATCH_P_ADDRESS_CMD[0], ...);
	... wmt_core_rx(..., sizeof(WMT_PATCH_P_ADDRESS_EVT), ...);
```

Мы доходим до 230/230 фрагментов и `patch dwn:0` ⇒ обе команды и оба EVT
прошли (`WMT_PATCH_ADDRESS_EVT`, `WMT_PATCH_P_ADDRESS_EVT`).

## 4. Что стало с reset после подавления assert

Правки (в `work/common`):
* `t1100_patch_active` — на время патча не вызывать `wmt_lib_trigger_assert`
  в `wmt_ctrl_rx`;
* перед каждой попыткой reset — `mtk_wcn_stp_set_wmt_trg_assert(0)`
  (`stp_core.c:3363`), чтобы снять латч, из-за которого `wmt_ctrl_rx`
  выходит мгновенно (`wmt_ctrl.c:271`: `if (mtk_wcn_stp_get_wmt_trg_assert() == 1
  && !is_wmt_last_close()) break;`);
* 3 попытки по 200 мс.

Результат — без изменений:

```
t1100: ROMv4 patch download -> 0
wmt_core_init_script_retry(702): read (wmt reset) iRet(-1) evt len err(rx:0, exp:5)
wmt_core_init_script_retry(691): write (wmt reset) iRet(-2) cmd len err(-2, 5)   ×2
mtk_wcn_soc_sw_init(1303): init_table_3 fail(-1) after retries
cpupcr = 0x00014ef8 (ROM)
```

Т.е. первая отправка уходит, ответа нет; **STP-состояние всё равно сбрасывается**
между попытками — по логу это делает coredump/assert-путь WMT
(`mtk_wcn_stp_coredump_start_ctrl: set f/w assert (0)/(1)`), который снимает
`WMT_STAT_STP_OPEN/EN` (см. `wmt_lib_hw_rst`, `wmt_lib.c:2096-2097`), поэтому
ретраи получают `-2` ещё до отправки.

## 5. Следующий (последний) шаг

Заглушить на время `t1100_patch_active` **весь** coredump/assert-путь, а не
только один вызов: `wmt_core_set_coredump_state()` / `mtk_wcn_stp_coredump_start_ctrl()`
и `wmt_lib_hw_rst()` в обработчике таймаута — тогда STP доживёт до 2-й/3-й
попытки reset, и станет видно, отвечает ли ROM на повтор. Если и тогда `rx:0` —
значит `{01 07 01 00 04}` для этого ROM/патча действительно не «старт», и нужен
дамп `cpupcr`/`WCIR` сразу после последнего фрагмента без reset (уже сделано:
патч сам не стартует), т.е. вопрос к вендорскому `wmt_loader` на реальном стоке
(его `dmesg` при загрузке Wi-Fi).
